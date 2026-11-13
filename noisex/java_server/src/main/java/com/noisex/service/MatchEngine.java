package com.noisex.service;

import com.noisex.model.domain.SonarData;
import com.noisex.util.RedisKeys;
import java.time.Duration;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

/**
 * 匹配引擎：负责声呐与收听者的匹配逻辑，支持 geohash 逐级扩展搜索相邻网格
 *
 * <p>核心方法：
 *
 * <ul>
 *   <li>{@link #onNewSonar} — 新声呐入队列时，遍历已有 listener 推送
 *   <li>{@link #onNewListener} — 新 listener 注册时，从已有声呐队列取声呐推送
 * </ul>
 *
 * <p>自匹配防护：发送者ID跳过 + pop后二次校验 + ChatService/createRoom校验，三层防御
 */
@Slf4j
@Service
public class MatchEngine {

    private final RedisTemplate<String, Object> redisTemplate;
    private final org.springframework.data.redis.core.StringRedisTemplate stringRedisTemplate;
    private final SonarService sonarService;
    private final com.noisex.websocket.NoiseXWebSocketHandler webSocketHandler;
    private final com.noisex.service.BlockService blockService;

    private static final String SONAR_QUEUE_PREFIX = RedisKeys.SONAR_QUEUE_PREFIX;
    private static final String LISTENER_PREFIX = RedisKeys.LISTENER_PREFIX;
    private static final String ONLINE_KEY = RedisKeys.ONLINE;
    private static final String PROCESSED_SONAR_PREFIX = "noisex:sonar:processed:";

    @org.springframework.beans.factory.annotation.Value("${noisex.match.max-expand-level}")
    private int maxExpandLevel;

    public MatchEngine(
            RedisTemplate<String, Object> redisTemplate,
            org.springframework.data.redis.core.StringRedisTemplate stringRedisTemplate,
            @Lazy SonarService sonarService,
            com.noisex.websocket.NoiseXWebSocketHandler webSocketHandler,
            com.noisex.service.BlockService blockService) {
        this.redisTemplate = redisTemplate;
        this.stringRedisTemplate = stringRedisTemplate;
        this.sonarService = sonarService;
        this.webSocketHandler = webSocketHandler;
        this.blockService = blockService;
    }

    /**
     * 新声呐入队列时调用 遍历已有 listener，将声呐推送给第一个符合条件的 listener
     *
     * @param geohash 声呐所在的 geohash 网格
     * @param senderId 声呐发送者 ID
     */
    public void onNewSonar(String geohash, String senderId) {
        // 先在同级网格匹配，再逐级扩大搜索范围（缩短 geohash 前缀匹配更广范围的 listener）
        for (int level = 0; level <= maxExpandLevel; level++) {
            String searchGeohash = geohash;
            if (level > 0) {
                int newLength = Math.max(1, geohash.length() - level);
                searchGeohash = geohash.substring(0, newLength);
            }

            // level=0 精确匹配同级网格，level>0 用 keys 扫描所有子网格的 listener。
            // O4：记录成员来源集合 key，供对不在线成员自愈移除
            Map<Object, String> listeners = new LinkedHashMap<>();
            if (level == 0) {
                collectListeners(LISTENER_PREFIX + searchGeohash, listeners);
            } else {
                Set<String> listenerKeys =
                        stringRedisTemplate.keys(LISTENER_PREFIX + searchGeohash + "*");
                if (listenerKeys != null && !listenerKeys.isEmpty()) {
                    for (String key : listenerKeys) {
                        collectListeners(key, listeners);
                    }
                }
            }

            if (listeners.isEmpty()) continue;

            for (Map.Entry<Object, String> entry : listeners.entrySet()) {
                Object obj = entry.getKey();
                String listenerId = normalizeUserId(obj);
                // 跳过发送者自己
                if (listenerId.equals(senderId)) continue;
                // O4 自愈：listener 集合无 TTL，断线未清理或历史序列化残留的成员
                // 会让每次匹配空转（先弹出声呐后推送失败，造成声呐丢失）。发现
                // 不在线成员立即从来源集合移除，避免反复命中。
                if (!isUserOnline(listenerId)) {
                    redisTemplate.opsForSet().remove(entry.getValue(), obj);
                    log.info("Removed stale listener member={} from {}", obj, entry.getValue());
                    continue;
                }
                // 跳过被屏蔽的
                if (blockService.isBlocked(listenerId, senderId)) continue;

                // 从声呐原始 geohash 队列取出最新的声呐推送给 listener
                String queueKey = SONAR_QUEUE_PREFIX + geohash;
                Object raw = redisTemplate.opsForList().leftPop(queueKey);
                if (raw instanceof SonarData sonar) {
                    // 二次校验：弹出的声呐发送者不能是当前 listener（防止自匹配）
                    if (sonar.getUserId().equals(listenerId)) {
                        // 自匹配声呐推到队尾，不阻塞 leftPop 取其他声呐
                        redisTemplate.opsForList().rightPush(queueKey, sonar);
                        continue;
                    }
                    try {
                        sonarService.pushSonarToUser(listenerId, sonar);
                        log.info(
                                "Sonar pushed to listener: sonar={} -> listener={} in geohash {} (matched at level {})",
                                sonar.getId(),
                                listenerId,
                                searchGeohash,
                                level);
                        return; // 一次只推给一个 listener
                    } catch (Exception e) {
                        // 推送失败，放回队列不丢失
                        redisTemplate.opsForList().rightPush(queueKey, sonar);
                        log.error(
                                "Failed to push sonar {} to listener {}, put back in queue: {}",
                                sonar.getId(),
                                listenerId,
                                e.getMessage());
                    }
                }
            }
        }
        // 无匹配的 listener，声呐留在队列中等待
        log.debug("No eligible listener found for sonar from {} in geohash {}", senderId, geohash);
    }

    /**
     * 新 listener 出现时调用 将用户加入 listener 集合，并从队列取声呐推送给它
     *
     * @param geohash listener 所在的 geohash 网格
     * @param listenerId listener 用户 ID
     */
    public void onNewListener(String geohash, String listenerId) {
        // 标记用户为收听状态
        redisTemplate.opsForSet().add(LISTENER_PREFIX + geohash, listenerId);

        // 逐级扩大搜索范围，从所有匹配前缀的声呐队列中取声呐
        for (int level = 0; level <= maxExpandLevel; level++) {
            String searchGeohash = geohash;
            if (level > 0) {
                int newLength = Math.max(1, geohash.length() - level);
                searchGeohash = geohash.substring(0, newLength);
            }

            // 扫描匹配前缀的所有声呐队列
            Set<String> queueKeys =
                    stringRedisTemplate.keys(SONAR_QUEUE_PREFIX + searchGeohash + "*");
            if (queueKeys == null || queueKeys.isEmpty()) continue;

            for (String queueKey : queueKeys) {
                Object raw = redisTemplate.opsForList().leftPop(queueKey);
                if (raw instanceof SonarData sonar) {
                    // 去重检查
                    String processedKey = PROCESSED_SONAR_PREFIX + listenerId;
                    Boolean alreadyProcessed =
                            redisTemplate.opsForSet().isMember(processedKey, sonar.getId());
                    if (Boolean.TRUE.equals(alreadyProcessed)) {
                        redisTemplate.opsForList().rightPush(queueKey, sonar);
                        log.debug(
                                "Sonar {} already processed for listener {}, put back",
                                sonar.getId(),
                                listenerId);
                        continue;
                    }

                    // 确保声呐发送者仍在线且不是自己
                    if (isUserOnline(sonar.getUserId())
                            && !sonar.getUserId().equals(listenerId)
                            && !blockService.isBlocked(listenerId, sonar.getUserId())) {
                        try {
                            sonarService.pushSonarToUser(listenerId, sonar);
                        } catch (Exception e) {
                            redisTemplate.opsForList().rightPush(queueKey, sonar);
                            log.error(
                                    "Failed to push sonar {} to listener {}, put back: {}",
                                    sonar.getId(),
                                    listenerId,
                                    e.getMessage());
                            continue;
                        }
                        redisTemplate.opsForSet().add(processedKey, sonar.getId());
                        redisTemplate.expire(processedKey, Duration.ofHours(1));

                        log.info(
                                "Sonar pushed to listener: sonar={} -> listener={} (matched at level {}, queue={})",
                                sonar.getId(),
                                listenerId,
                                level,
                                queueKey);
                        return;
                    }
                    // 发送者不在线或是自己，放回队列
                    redisTemplate.opsForList().rightPush(queueKey, sonar);
                    log.debug(
                            "Skipped sonar from {} (online={}, self={}), put back in queue",
                            sonar.getUserId(),
                            isUserOnline(sonar.getUserId()),
                            sonar.getUserId().equals(listenerId));
                }
            }
        }
        // 无匹配，用户保持在收听队列中等待
        log.debug("No match found for listener {} in geohash {}", listenerId, geohash);
    }

    /**
     * 统计附近活跃用户数（用于雷达 blip 真实化）
     *
     * <p>在用户当前 geohash + 扩展范围内，统计在线 listener 数量，排除自己。 仅返回数量，不返回身份，避免被孤立定位。
     *
     * @param geohash 用户当前 6 字符 geohash
     * @param excludeUserId 排除的用户 ID（通常为自己）
     * @return 在线附近 listener 数量
     */
    public int countNearbyListeners(String geohash, String excludeUserId) {
        Set<String> counted = new HashSet<>();
        for (int level = 0; level <= maxExpandLevel; level++) {
            String searchGeohash = geohash;
            if (level > 0) {
                int newLength = Math.max(1, geohash.length() - level);
                searchGeohash = geohash.substring(0, newLength);
            }

            Set<Object> listeners;
            if (level == 0) {
                listeners = redisTemplate.opsForSet().members(LISTENER_PREFIX + searchGeohash);
            } else {
                Set<String> listenerKeys =
                        stringRedisTemplate.keys(LISTENER_PREFIX + searchGeohash + "*");
                listeners = new HashSet<>();
                if (listenerKeys != null && !listenerKeys.isEmpty()) {
                    for (String key : listenerKeys) {
                        Set<Object> members = redisTemplate.opsForSet().members(key);
                        if (members != null) {
                            listeners.addAll(members);
                        }
                    }
                }
            }

            if (listeners == null || listeners.isEmpty()) continue;
            for (Object obj : listeners) {
                String listenerId = normalizeUserId(obj);
                if (listenerId.equals(excludeUserId)) continue;
                if (!isUserOnline(listenerId)) continue;
                if (blockService.isBlocked(listenerId, excludeUserId)) continue;
                counted.add(listenerId);
            }
        }
        return counted.size();
    }

    /** 读取 listener 集合并记录每个成员的来源 key（level>0 聚合时用于自愈移除） */
    private void collectListeners(String key, Map<Object, String> out) {
        Set<Object> members = redisTemplate.opsForSet().members(key);
        if (members == null) return;
        for (Object member : members) {
            out.put(member, key);
        }
    }

    /**
     * 归一化 listener 成员值。
     *
     * <p>历史版本曾把 JSON 序列化后的带引号字符串（如 {@code "anonymousUser"} 含双引号） 写进 listener 集合（联调缺陷 O4），该值与任何真实
     * userId 都不相等，会成为 永远无法匹配、又不会被现有清理路径移除的僵尸成员。这里剥离成对包裹的 双引号，兼容读取历史脏数据；配合 {@link #onNewSonar}
     * 的不在线自愈最终清空。
     */
    private String normalizeUserId(Object obj) {
        String value = String.valueOf(obj);
        if (value.length() >= 2 && value.startsWith("\"") && value.endsWith("\"")) {
            return value.substring(1, value.length() - 1);
        }
        return value;
    }

    /** 检查用户是否在线（通过 Redis Set 成员判断） */
    private boolean isUserOnline(String userId) {
        return Boolean.TRUE.equals(redisTemplate.opsForSet().isMember(ONLINE_KEY, userId));
    }
}
