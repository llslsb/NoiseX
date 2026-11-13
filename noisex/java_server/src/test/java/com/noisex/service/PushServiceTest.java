package com.noisex.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class PushServiceTest {

    @Mock private RedisTemplate<String, Object> redisTemplate;

    @Mock private ObjectMapper objectMapper;

    @Mock private SetOperations<String, Object> setOperations;

    @Mock private ValueOperations<String, Object> valueOperations;

    private PushService pushService;

    @BeforeEach
    void setUp() {
        pushService = new PushService(redisTemplate, objectMapper);
        ReflectionTestUtils.setField(pushService, "pushEnabled", true);
        lenient().when(redisTemplate.opsForSet()).thenReturn(setOperations);
        lenient().when(redisTemplate.opsForValue()).thenReturn(valueOperations);
    }

    @Test
    void registerToken_shouldStoreInRedis() {
        pushService.registerToken("user-1", "push-token-abc", "hms");

        verify(valueOperations).set(contains("push:token:"), eq("push-token-abc"), any());
    }

    @Test
    void getToken_shouldReturnFromRedis() {
        when(valueOperations.get(anyString())).thenReturn("push-token-abc");

        String token = pushService.getToken("user-1");

        assertEquals("push-token-abc", token);
    }

    @Test
    void getToken_noToken_shouldReturnNull() {
        when(valueOperations.get(anyString())).thenReturn(null);

        String token = pushService.getToken("user-1");

        assertNull(token);
    }

    @Test
    void unregisterToken_shouldDeleteFromRedis() {
        pushService.unregisterToken("user-1");

        verify(redisTemplate).delete(contains("push:token:"));
    }

    @Test
    void sendPush_userOnline_shouldNotSend() {
        when(setOperations.isMember(anyString(), eq("user-1"))).thenReturn(true);

        pushService.sendPush("user-1", "title", "body");

        // Should not attempt to get token since user is online
        verify(valueOperations, never()).get(contains("push:token:"));
    }

    @Test
    void sendPush_pushDisabled_shouldNotSend() {
        ReflectionTestUtils.setField(pushService, "pushEnabled", false);

        pushService.sendPush("user-1", "title", "body");

        verify(setOperations, never()).isMember(anyString(), anyString());
    }

    @Test
    void sendPush_noPushToken_shouldNotSend() {
        when(setOperations.isMember(anyString(), eq("user-1"))).thenReturn(false);
        when(valueOperations.setIfAbsent(anyString(), any(), any())).thenReturn(true);
        when(valueOperations.get(contains("push:token:"))).thenReturn(null);

        pushService.sendPush("user-1", "title", "body");
    }

    @Test
    void sendPush_withData_userOnline_shouldNotSend() {
        when(setOperations.isMember(anyString(), eq("user-1"))).thenReturn(true);

        pushService.sendPush(
                "user-1", "title", "body", Map.of("roomId", "room-1", "type", "message"));

        verify(valueOperations, never()).get(contains("push:token:"));
    }

    @Test
    void sendPush_withData_noPushToken_shouldNotSend() {
        when(setOperations.isMember(anyString(), eq("user-1"))).thenReturn(false);
        when(valueOperations.setIfAbsent(anyString(), any(), any())).thenReturn(true);
        when(valueOperations.get(contains("push:token:"))).thenReturn(null);

        pushService.sendPush(
                "user-1", "title", "body", Map.of("roomId", "room-1", "type", "message"));
    }

    @Test
    void sendPush_withNullData_shouldNotCrash() {
        when(setOperations.isMember(anyString(), eq("user-1"))).thenReturn(false);
        when(valueOperations.setIfAbsent(anyString(), any(), any())).thenReturn(true);
        when(valueOperations.get(contains("push:token:"))).thenReturn(null);

        pushService.sendPush("user-1", "title", "body", null);
    }
}
