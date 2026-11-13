package com.noisex.service;

import com.noisex.exception.BusinessException;
import com.noisex.exception.ErrorCode;
import com.noisex.exception.NotFoundException;
import com.noisex.exception.RateLimitException;
import com.noisex.model.domain.ChatRoomData;
import com.noisex.model.domain.SonarData;
import com.noisex.model.dto.AcceptSonarResponse;
import com.noisex.model.dto.SonarDataResponse;
import com.noisex.util.IdGenerator;
import com.noisex.util.RedisKeys;
import io.micrometer.core.instrument.Counter;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class SonarService {

    private final RedisTemplate<String, Object> redisTemplate;
    private final StringRedisTemplate stringRedisTemplate;
    private final MatchEngine matchEngine;
    private final ChatService chatService;
    private final com.noisex.websocket.NoiseXWebSocketHandler webSocketHandler;
    private final com.noisex.service.BlockService blockService;
    private final com.noisex.service.PushService pushService;
    private final Counter sonarSentCounter;
    private final Counter sonarAcceptedCounter;

    private static final String SONAR_QUEUE_PREFIX = RedisKeys.SONAR_QUEUE_PREFIX;
    private static final String RATE_LIMIT_PREFIX = RedisKeys.RATE_LIMIT_PREFIX;
    private static final String RECEIVED_PREFIX = RedisKeys.SONAR_RECEIVED_PREFIX;
    private static final String LISTENER_PREFIX = RedisKeys.LISTENER_PREFIX;
    private static final String ONLINE_KEY = RedisKeys.ONLINE;
    private static final String USER_LISTENING_GEOHASHES_PREFIX =
            RedisKeys.USER_LISTENING_GEOHASHES_PREFIX;

    @Value("${noisex.sonar.max-per-hour}")
    private int maxSonarPerHour;

    @Value("${noisex.sonar.max-content-length}")
    private int maxContentLength;

    @Value("${noisex.sonar.duplicate-window-seconds}")
    private int duplicateWindowSeconds;

    private static final DefaultRedisScript<Long> RATE_LIMIT_SCRIPT =
            new DefaultRedisScript<>(
                    "local count = redis.call('INCR', KEYS[1]) "
                            + "if count == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end "
                            + "return count",
                    Long.class);

    private static final DefaultRedisScript<Long> ACCEPT_SONAR_SCRIPT =
            new DefaultRedisScript<>(
                    "for i, v in ipairs(redis.call('LRANGE', KEYS[1], 0, -1)) do "
                            + "local decoded = cjson.decode(v) "
                            + "if decoded['id'] == ARGV[1] then "
                            + "redis.call('LREM', KEYS[1], 1, v) "
                            + "return 1 "
                            + "end "
                            + "end "
                            + "return 0",
                    Long.class);

    private static final DefaultRedisScript<Long> SONAR_DUPLICATE_SCRIPT =
            new DefaultRedisScript<>(
                    "local last = redis.call('GET', KEYS[1]) "
                            + "if last == ARGV[1] then return 1 end "
                            + "redis.call('SET', KEYS[1], ARGV[1]) "
                            + "redis.call('EXPIRE', KEYS[1], ARGV[2]) "
                            + "return 0",
                    Long.class);

    /** 发送声呐 1. 检查频率限制 2. 将声呐放入对应 Geohash 网格的 FIFO 队列 3. 触发匹配引擎 */
    public String sendSonar(String userId, String content, String geohash) {
        // 频率限制检查（Lua 原子操作：increment + expire）
        String rateKey = RATE_LIMIT_PREFIX + userId;
        Long count =
                stringRedisTemplate.execute(
                        RATE_LIMIT_SCRIPT, Collections.singletonList(rateKey), "3600");
        if (count != null && count > maxSonarPerHour) {
            throw new RateLimitException("每小时最多发送" + maxSonarPerHour + "次声呐");
        }

        // 声呐内容重复检测
        String sonarDuplicateKey = RedisKeys.SONAR_DUPLICATE_PREFIX + userId;
        Long isDuplicate =
                stringRedisTemplate.execute(
                        SONAR_DUPLICATE_SCRIPT,
                        Collections.singletonList(sonarDuplicateKey),
                        content,
                        String.valueOf(duplicateWindowSeconds));
        if (isDuplicate != null && isDuplicate == 1) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "请勿发送重复内容的声呐");
        }

        // 创建声呐对象
        String sonarId = IdGenerator.sonarId();
        SonarData sonar =
                SonarData.builder()
                        .id(sonarId)
                        .userId(userId)
                        .content(content)
                        .geohash(geohash)
                        .timestamp(System.currentTimeMillis())
                        .build();

        // 放入对应网格的 FIFO 队列
        String queueKey = SONAR_QUEUE_PREFIX + geohash;
        redisTemplate.opsForList().leftPush(queueKey, sonar);
        // 始终刷新队列 TTL，防止新声呐因队列过期而丢失
        redisTemplate.expire(queueKey, Duration.ofHours(1));

        log.info("Sonar sent: id={}, userId={}, geohash={}", sonarId, userId, geohash);

        redisTemplate.opsForSet().add(ONLINE_KEY, userId);

        matchEngine.onNewSonar(geohash, userId);

        sonarSentCounter.increment();
        return sonarId;
    }

    /** 获取用户收到的声呐 */
    public List<SonarDataResponse> getReceivedSonars(String userId) {
        String key = RECEIVED_PREFIX + userId;
        List<Object> raw = redisTemplate.opsForList().range(key, 0, -1);
        if (raw == null || raw.isEmpty()) {
            return Collections.emptyList();
        }

        List<SonarDataResponse> result = new ArrayList<>();
        for (Object obj : raw) {
            if (obj instanceof SonarData sonar) {
                String distance = calculateDistance(sonar.getGeohash());
                result.add(
                        new SonarDataResponse(
                                sonar.getId(), sonar.getContent(), distance, sonar.getTimestamp()));
            }
        }
        return result;
    }

    /** 响应声呐，创建对话房间 */
    public AcceptSonarResponse acceptSonar(String userId, String sonarId) {
        String key = RECEIVED_PREFIX + userId;
        List<Object> raw = redisTemplate.opsForList().range(key, 0, -1);
        SonarData matchedSonar = null;
        if (raw != null) {
            for (Object obj : raw) {
                if (obj instanceof SonarData sonar && sonar.getId().equals(sonarId)) {
                    matchedSonar = sonar;
                    break;
                }
            }
        }
        if (matchedSonar == null) {
            throw new NotFoundException("声呐不存在或已过期: " + sonarId);
        }

        // 防止自匹配：不能接受自己发送的声呐
        if (matchedSonar.getUserId().equals(userId)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "不能接受自己发送的声呐");
        }

        Long removed =
                stringRedisTemplate.execute(
                        ACCEPT_SONAR_SCRIPT, Collections.singletonList(key), sonarId);
        if (removed == null || removed == 0) {
            throw new NotFoundException("声呐不存在或已过期: " + sonarId);
        }

        ChatRoomData room = chatService.createRoom(matchedSonar, userId);
        webSocketHandler.notifyMatched(matchedSonar.getUserId(), room);
        webSocketHandler.notifyMatched(userId, room);
        pushService.sendPush(
                matchedSonar.getUserId(),
                "匹配成功",
                "有人接受了你的声呐",
                java.util.Map.of("roomId", room.getId(), "type", "matched"));
        pushService.sendPush(
                userId,
                "匹配成功",
                "你接受了一个声呐",
                java.util.Map.of("roomId", room.getId(), "type", "matched"));
        log.info("Sonar accepted: id={}, userId={}, roomId={}", sonarId, userId, room.getId());
        sonarAcceptedCounter.increment();
        return new AcceptSonarResponse(
                room.getId(), room.getSignalCode(), room.getSonarContent(), room.getExpiresAt());
    }

    /** 忽略声呐 */
    public void ignoreSonar(String userId, String sonarId) {
        String key = RECEIVED_PREFIX + userId;
        List<Object> raw = redisTemplate.opsForList().range(key, 0, -1);
        if (raw != null) {
            for (Object obj : raw) {
                if (obj instanceof SonarData sonar && sonar.getId().equals(sonarId)) {
                    redisTemplate.opsForList().remove(key, 1, sonar);
                    log.info("Sonar ignored: id={}, userId={}", sonarId, userId);
                    return;
                }
            }
        }
    }

    /** 将声呐推送给用户（匹配引擎调用） */
    public void pushSonarToUser(String userId, SonarData sonar) {
        if (blockService.isBlocked(userId, sonar.getUserId())) {
            log.debug("Sonar blocked: sonar={} -> listener={} (blocked)", sonar.getId(), userId);
            return;
        }
        String key = RECEIVED_PREFIX + userId;
        redisTemplate.opsForList().leftPush(key, sonar);
        redisTemplate.expire(key, Duration.ofHours(1));
        webSocketHandler.notifyNewSonar(userId, sonar);
        pushService.sendPush(
                userId, "收到新声呐", sonar.getContent(), java.util.Map.of("type", "sonar"));
    }

    /** 注册为收听者（开启收听模式） 将用户加入当前 Geohash 网格的收听者集合，并触发匹配 */
    public void registerListener(String userId, String geohash) {
        String userGeohashesKey = USER_LISTENING_GEOHASHES_PREFIX + userId;
        // 2026-11-02 幽灵格子修复：注册即原子替换。旧逻辑纯 ADD 且无 TTL——
        // 客户端重启丢失旧格子记忆、或历史兜底常量写入的错误格子（真机 wx4g0s
        // 幽灵实锤）永久残留，直接导致"附近 0 人"对不上格子。
        Set<Object> previous = redisTemplate.opsForSet().members(userGeohashesKey);
        if (previous != null) {
            for (Object old : previous) {
                if (!String.valueOf(old).equals(geohash)) {
                    redisTemplate.opsForSet().remove(LISTENER_PREFIX + old, userId);
                }
            }
        }
        redisTemplate.delete(userGeohashesKey);
        redisTemplate.opsForSet().add(userGeohashesKey, geohash);
        // 监听注册 30min TTL，由 WS ping 周期续期（见 NoiseXWebSocketHandler）；
        // 客户端异常消失（断网/杀进程未触发清理）后残留自动过期。
        redisTemplate.expire(userGeohashesKey, Duration.ofMinutes(30));
        redisTemplate.opsForSet().add(LISTENER_PREFIX + geohash, userId);
        redisTemplate.opsForSet().add(ONLINE_KEY, userId);
        matchEngine.onNewListener(geohash, userId);
        log.info(
                "Listener registered: userId={}, geohash={} (previous cells replaced)",
                userId,
                geohash);
    }

    /** WS ping 续期监听注册 TTL（客户端每 30s ping 一次；无注册时为空操作） */
    public void touchListenerTTL(String userId) {
        redisTemplate.expire(USER_LISTENING_GEOHASHES_PREFIX + userId, Duration.ofMinutes(30));
    }

    /** 注销收听者（关闭收听模式） 将用户从指定 Geohash 网格的收听者集合中移除 */
    public void unregisterListener(String userId, String geohash) {
        String key = LISTENER_PREFIX + geohash;
        redisTemplate.opsForSet().remove(key, userId);
        redisTemplate.opsForSet().remove(USER_LISTENING_GEOHASHES_PREFIX + userId, geohash);
        // 仅当用户没有其他 geohash 在监听时才从 ONLINE 移除
        Set<Object> remaining =
                redisTemplate.opsForSet().members(USER_LISTENING_GEOHASHES_PREFIX + userId);
        if (remaining == null || remaining.isEmpty()) {
            redisTemplate.opsForSet().remove(ONLINE_KEY, userId);
        }
        log.info("Listener unregistered: userId={}, geohash={}", userId, geohash);
    }

    /** 清理用户的所有收听者记录（WebSocket 断线时调用） 根据用户 listening_geohashes Set 精准删除 */
    public void unregisterListenerFromAll(String userId) {
        String userGeohashesKey = USER_LISTENING_GEOHASHES_PREFIX + userId;
        Set<Object> geohashes = redisTemplate.opsForSet().members(userGeohashesKey);
        if (geohashes != null && !geohashes.isEmpty()) {
            for (Object geohashObj : geohashes) {
                String geohash = String.valueOf(geohashObj);
                redisTemplate.opsForSet().remove(LISTENER_PREFIX + geohash, userId);
            }
            redisTemplate.delete(userGeohashesKey);
            log.info(
                    "Listener cleaned up on disconnect: userId={}, removed from {} geohash cells",
                    userId,
                    geohashes.size());
        }
    }

    /**
     * 查询附近活跃用户数（用于雷达 blip 真实化）
     *
     * <p><b>真实计数，不做模糊化</b>（2026-10-31 产品决策：没有人就如实上报 0，杜绝假数据—— 反表演原则同样适用于平台自身）。计数口径见 {@link
     * MatchEngine#countNearbyListeners}：排除自己、仅统计 WS 在线 listener、跳过被拉黑用户。
     *
     * <p>{@code blipCount} 取 [0, 8]（雷达信号点渲染上限），随真实计数走：0 人即 0 个信号点。
     */
    public com.noisex.model.dto.NearbyActivityResponse getNearbyActivity(
            String userId, String geohash) {
        int raw = matchEngine.countNearbyListeners(geohash, userId);
        int nearbyCount = raw;
        int blipCount = Math.min(8, Math.max(0, raw));
        return new com.noisex.model.dto.NearbyActivityResponse(nearbyCount, blipCount);
    }

    private String calculateDistance(String geohash) {
        int precision = geohash.length();
        return switch (precision) {
            case 6 -> "~500m";
            case 5 -> "同城";
            case 4 -> "同区";
            case 3 -> "同省";
            case 2 -> "同国";
            default -> "全球";
        };
    }
}
