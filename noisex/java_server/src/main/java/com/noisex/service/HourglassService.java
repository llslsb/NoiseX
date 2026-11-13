package com.noisex.service;

import com.noisex.util.RedisKeys;
import com.noisex.websocket.NoiseXWebSocketHandler;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.connection.Message;
import org.springframework.data.redis.connection.MessageListener;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class HourglassService implements MessageListener {

    private final RedisTemplate<String, Object> redisTemplate;
    private final StringRedisTemplate stringRedisTemplate;
    private final NoiseXWebSocketHandler webSocketHandler;
    private final PushService pushService;

    private static final String ROOM_PREFIX = RedisKeys.ROOM_PREFIX;
    private static final String MESSAGES_PREFIX = RedisKeys.ROOM_MESSAGES_PREFIX;
    private static final String DEEP_CONFIRM_PREFIX = RedisKeys.ROOM_DEEP_PREFIX;
    private static final String SAVE_PREFIX = RedisKeys.ROOM_SAVE_PREFIX;
    private static final String READ_PREFIX = RedisKeys.ROOM_READ_PREFIX;
    private static final String USER_ROOMS_PREFIX = RedisKeys.USER_ROOMS_PREFIX;
    private static final String ROOM_USERS_PREFIX = RedisKeys.ROOM_USERS_PREFIX;
    private static final String ROOM_CREATED_AT_ZSET = RedisKeys.ROOM_CREATED_AT_ZSET;

    @Override
    public void onMessage(Message message, byte[] pattern) {
        String expiredKey = new String(message.getBody());

        if (expiredKey.startsWith(ROOM_PREFIX)) {
            String roomId = expiredKey.substring(ROOM_PREFIX.length());
            log.info("Room expired: {}", roomId);

            notifyUsersAndCleanup(roomId);
        }
    }

    private void notifyUsersAndCleanup(String roomId) {
        webSocketHandler.notifyRoomExpiredByRoomId(roomId);

        String roomUsersKey = ROOM_USERS_PREFIX + roomId;
        String usersValue = stringRedisTemplate.opsForValue().get(roomUsersKey);
        if (usersValue != null) {
            String[] userIds = usersValue.split(",");
            for (String userId : userIds) {
                if (!userId.isEmpty()) {
                    pushService.sendPush(
                            userId,
                            "房间已过期",
                            "你的对话房间已关闭",
                            Map.of("roomId", roomId, "type", "room_expired"));
                }
            }
        }

        cleanupRoomData(roomId);
    }

    private void cleanupRoomData(String roomId) {
        // 必须先读取用户列表，再删除 key，否则后续 get 返回 null 导致用户活跃房间集合残留
        String roomUsersKey = ROOM_USERS_PREFIX + roomId;
        String usersValue = stringRedisTemplate.opsForValue().get(roomUsersKey);

        redisTemplate.delete(MESSAGES_PREFIX + roomId);
        redisTemplate.delete(DEEP_CONFIRM_PREFIX + roomId);
        redisTemplate.delete(SAVE_PREFIX + roomId);
        redisTemplate.delete(READ_PREFIX + roomId);
        redisTemplate.delete(ROOM_USERS_PREFIX + roomId);
        redisTemplate.opsForZSet().remove(ROOM_CREATED_AT_ZSET, roomId);

        if (usersValue != null) {
            String[] userIds = usersValue.split(",");
            for (String userId : userIds) {
                if (!userId.isEmpty()) {
                    redisTemplate.opsForSet().remove(USER_ROOMS_PREFIX + userId, roomId);
                }
            }
        }
        log.info("Room data cleaned up: {}", roomId);
    }
}
