package com.noisex.service;

import com.noisex.util.RedisKeys;
import com.noisex.websocket.NoiseXWebSocketHandler;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ZSetOperations;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class RoomExpiringService {

    private final RedisTemplate<String, Object> redisTemplate;
    private final StringRedisTemplate stringRedisTemplate;
    private final NoiseXWebSocketHandler webSocketHandler;
    private final PushService pushService;

    private static final String ROOM_PREFIX = RedisKeys.ROOM_PREFIX;
    private static final String USER_ROOMS_PREFIX = RedisKeys.USER_ROOMS_PREFIX;
    private static final String ROOM_USERS_PREFIX = RedisKeys.ROOM_USERS_PREFIX;
    private static final String ROOM_CREATED_AT_ZSET = RedisKeys.ROOM_CREATED_AT_ZSET;
    private static final long TWELVE_HOURS_MS = 12 * 3600 * 1000L;

    @Scheduled(fixedRate = 30, timeUnit = TimeUnit.MINUTES)
    public void checkExpiringRooms() {
        long now = System.currentTimeMillis();

        // 用 StringRedisTemplate 读原始成员：GenericJackson2JsonRedisSerializer 对
        // rangeByScore 结果整批反序列化，ZSet 里一条历史脏成员（未 JSON 引号包裹的裸
        // roomId，2026-10-28 遗留）即让整个调用抛 SerializationException——30min tick
        // 持续崩溃、过期清扫全瘫。改读原始字符串并就地自愈（O4 同款思路）。
        Set<ZSetOperations.TypedTuple<String>> tuples =
                stringRedisTemplate
                        .opsForZSet()
                        .rangeByScoreWithScores(ROOM_CREATED_AT_ZSET, 0, now);
        if (tuples == null || tuples.isEmpty()) return;

        int notified = 0;
        int healed = 0;

        for (ZSetOperations.TypedTuple<String> tuple : tuples) {
            Double score = tuple.getScore();
            String rawMember = tuple.getValue();
            String roomId = normalizeRoomId(rawMember);

            // 自愈：裸串成员删除后按 ChatService 写入方规范（JSON 模板）重写
            if (score != null && !rawMember.equals("\"" + roomId + "\"")) {
                stringRedisTemplate.opsForZSet().remove(ROOM_CREATED_AT_ZSET, rawMember);
                redisTemplate.opsForZSet().add(ROOM_CREATED_AT_ZSET, roomId, score);
                healed++;
            }

            String roomKey = ROOM_PREFIX + roomId;
            Map<Object, Object> raw = redisTemplate.opsForHash().entries(roomKey);

            if (raw.isEmpty()) {
                cleanUpExpiredRoomUserRef(roomId);
                redisTemplate.opsForZSet().remove(ROOM_CREATED_AT_ZSET, roomId);
                continue;
            }

            String expiresAtStr =
                    raw.get("expiresAt") != null ? raw.get("expiresAt").toString() : null;
            if (expiresAtStr == null) continue;

            long expiresAt = Long.parseLong(expiresAtStr);
            long remaining = expiresAt - now;

            if (remaining <= 0) {
                cleanUpExpiredRoomUserRef(roomId);
                redisTemplate.opsForZSet().remove(ROOM_CREATED_AT_ZSET, roomId);
                continue;
            }

            if (remaining < TWELVE_HOURS_MS) {
                String notifiedKey = "noisex:room:expiring_notified:" + roomId;
                if (Boolean.TRUE.equals(redisTemplate.hasKey(notifiedKey))) continue;

                double remainingHours = remaining / (3600.0 * 1000.0);
                webSocketHandler.notifyRoomExpiring(roomId, remainingHours);

                String expiringMsg = String.format("房间将在 %.1f 小时后过期", remainingHours);
                String roomUsersKey = ROOM_USERS_PREFIX + roomId;
                String usersValue = stringRedisTemplate.opsForValue().get(roomUsersKey);
                if (usersValue != null) {
                    String[] userIds = usersValue.split(",");
                    for (String userId : userIds) {
                        if (!userId.isEmpty()) {
                            pushService.sendPush(
                                    userId,
                                    "房间即将过期",
                                    expiringMsg,
                                    java.util.Map.of("roomId", roomId, "type", "room_expiring"));
                        }
                    }
                }

                redisTemplate.opsForValue().set(notifiedKey, "1");
                redisTemplate.expire(notifiedKey, java.time.Duration.ofMillis(remaining));

                notified++;
            }
        }

        if (notified > 0) {
            log.info("Room expiring notifications sent: {}", notified);
        }
        if (healed > 0) {
            log.info("Room expiry ZSet dirty members healed: {}", healed);
        }
    }

    /** 兼容历史脏数据：JSON 引号包裹成员去引号，裸串原样返回 */
    private String normalizeRoomId(String raw) {
        if (raw.length() >= 2 && raw.startsWith("\"") && raw.endsWith("\"")) {
            return raw.substring(1, raw.length() - 1);
        }
        return raw;
    }

    private void cleanUpExpiredRoomUserRef(String roomId) {
        String roomUsersKey = ROOM_USERS_PREFIX + roomId;
        String usersValue = stringRedisTemplate.opsForValue().get(roomUsersKey);
        if (usersValue != null) {
            String[] userIds = usersValue.split(",");
            for (String userId : userIds) {
                if (!userId.isEmpty()) {
                    redisTemplate.opsForSet().remove(USER_ROOMS_PREFIX + userId, roomId);
                }
            }
        }
        log.info("Expired room user refs cleaned up: {}", roomId);
    }
}
