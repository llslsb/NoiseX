package com.noisex.service;

import static org.mockito.Mockito.*;

import com.noisex.util.RedisKeys;
import com.noisex.websocket.NoiseXWebSocketHandler;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.connection.Message;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.data.redis.core.ZSetOperations;

@ExtendWith(MockitoExtension.class)
class HourglassServiceTest {

    @Mock private RedisTemplate<String, Object> redisTemplate;

    @Mock private StringRedisTemplate stringRedisTemplate;

    @Mock private NoiseXWebSocketHandler webSocketHandler;

    @Mock private PushService pushService;

    @Mock private ZSetOperations<String, Object> zSetOperations;

    @Mock private SetOperations<String, Object> setOperations;

    @Mock private ValueOperations<String, String> stringValueOperations;

    private HourglassService hourglassService;

    @BeforeEach
    void setUp() {
        hourglassService =
                new HourglassService(
                        redisTemplate, stringRedisTemplate, webSocketHandler, pushService);
        lenient().when(redisTemplate.opsForZSet()).thenReturn(zSetOperations);
        lenient().when(redisTemplate.opsForSet()).thenReturn(setOperations);
        lenient().when(stringRedisTemplate.opsForValue()).thenReturn(stringValueOperations);
    }

    @Test
    void onMessage_whenRoomKeyExpired_shouldNotifyAndCleanup() {
        String expiredKey = RedisKeys.ROOM_PREFIX + "room-1";
        Message message = mock(Message.class);
        when(message.getBody()).thenReturn(expiredKey.getBytes());

        hourglassService.onMessage(message, "pattern".getBytes());

        verify(webSocketHandler).notifyRoomExpiredByRoomId("room-1");
        verify(redisTemplate).delete(RedisKeys.ROOM_MESSAGES_PREFIX + "room-1");
        verify(redisTemplate).delete(RedisKeys.ROOM_DEEP_PREFIX + "room-1");
        verify(redisTemplate).delete(RedisKeys.ROOM_SAVE_PREFIX + "room-1");
    }

    @Test
    void onMessage_whenNonRoomKeyExpired_shouldDoNothing() {
        String expiredKey = "noisex:other:key";
        Message message = mock(Message.class);
        when(message.getBody()).thenReturn(expiredKey.getBytes());

        hourglassService.onMessage(message, "pattern".getBytes());

        verify(webSocketHandler, never()).notifyRoomExpiredByRoomId(anyString());
        verify(redisTemplate, never()).delete(anyString());
    }

    @Test
    void cleanupRoomData_shouldReadUserIdsBeforeDeletingRoomUsersKey() {
        String roomId = "room-1";
        String roomUsersKey = RedisKeys.ROOM_USERS_PREFIX + roomId;

        // 模拟 room users key 存在两个用户
        when(stringValueOperations.get(roomUsersKey)).thenReturn("user-a,user-b");

        // 触发过期清理
        String expiredKey = RedisKeys.ROOM_PREFIX + roomId;
        Message message = mock(Message.class);
        when(message.getBody()).thenReturn(expiredKey.getBytes());

        hourglassService.onMessage(message, "pattern".getBytes());

        // 验证用户活跃房间集合中被移除了过期 roomId
        verify(setOperations).remove(RedisKeys.USER_ROOMS_PREFIX + "user-a", roomId);
        verify(setOperations).remove(RedisKeys.USER_ROOMS_PREFIX + "user-b", roomId);

        // 验证 room users key 被删除
        verify(redisTemplate).delete(roomUsersKey);
    }

    @Test
    void cleanupRoomData_whenRoomUsersKeyAlreadyMissing_shouldNotThrow() {
        String roomId = "room-2";
        String roomUsersKey = RedisKeys.ROOM_USERS_PREFIX + roomId;

        // 模拟 room users key 已不存在（被提前清理或未创建）
        when(stringValueOperations.get(roomUsersKey)).thenReturn(null);

        String expiredKey = RedisKeys.ROOM_PREFIX + roomId;
        Message message = mock(Message.class);
        when(message.getBody()).thenReturn(expiredKey.getBytes());

        hourglassService.onMessage(message, "pattern".getBytes());

        // 不应尝试清理用户房间集合
        verify(setOperations, never()).remove(anyString(), any());
        // 但仍应删除其他 key
        verify(redisTemplate).delete(RedisKeys.ROOM_MESSAGES_PREFIX + roomId);
    }
}
