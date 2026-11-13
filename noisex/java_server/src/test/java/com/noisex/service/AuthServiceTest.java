package com.noisex.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.model.dto.AuthResponse;
import com.noisex.model.repository.ReportRepository;
import com.noisex.model.repository.SavedConnectionRepository;
import com.noisex.model.repository.SavedMomentRepository;
import com.noisex.model.repository.UserBlockRepository;
import com.noisex.model.repository.UserProfileRepository;
import com.noisex.security.JwtTokenProvider;
import com.noisex.websocket.NoiseXWebSocketHandler;
import java.util.Collections;
import java.util.Set;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.data.redis.core.ZSetOperations;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock private JwtTokenProvider jwtTokenProvider;
    @Mock private RedisTemplate<String, Object> redisTemplate;
    @Mock private StringRedisTemplate stringRedisTemplate;
    @Mock private NoiseXWebSocketHandler webSocketHandler;
    @Mock private PushService pushService;
    @Mock private UserProfileRepository userProfileRepository;
    @Mock private SavedConnectionRepository savedConnectionRepository;
    @Mock private UserBlockRepository userBlockRepository;
    @Mock private ReportRepository reportRepository;
    @Mock private SavedMomentRepository savedMomentRepository;
    @Mock private ValueOperations<String, Object> valueOperations;
    @Mock private SetOperations<String, Object> setOperations;
    @Mock private ZSetOperations<String, Object> zSetOperations;

    private AuthService authService;

    @BeforeEach
    void setUp() {
        authService =
                new AuthService(
                        jwtTokenProvider,
                        redisTemplate,
                        stringRedisTemplate,
                        webSocketHandler,
                        pushService,
                        userProfileRepository,
                        savedConnectionRepository,
                        userBlockRepository,
                        reportRepository,
                        savedMomentRepository);
        lenient().when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        lenient().when(redisTemplate.opsForSet()).thenReturn(setOperations);
        lenient().when(redisTemplate.opsForZSet()).thenReturn(zSetOperations);
    }

    @Test
    void generateToken_shouldReturnTokenWithExpiration() {
        when(valueOperations.get(anyString())).thenReturn(null);
        when(jwtTokenProvider.generateToken("test-uuid")).thenReturn("jwt-token-123");
        when(jwtTokenProvider.getExpiration()).thenReturn(86400000L);

        AuthResponse response = authService.generateToken("test-uuid");

        assertNotNull(response);
        assertEquals("jwt-token-123", response.getToken());
        assertEquals(86400000L, response.getExpiresIn());
        verify(jwtTokenProvider).generateToken("test-uuid");
    }

    @Test
    void refreshToken_shouldReturnNewToken() {
        when(jwtTokenProvider.generateToken("user-123")).thenReturn("new-jwt-token");
        when(jwtTokenProvider.getExpiration()).thenReturn(86400000L);

        AuthResponse response = authService.refreshToken("user-123");

        assertNotNull(response);
        assertEquals("new-jwt-token", response.getToken());
    }

    @Test
    void resetIdentity_withNoRooms_shouldDeleteAllUserData() {
        when(setOperations.members("noisex:user:rooms:user-1")).thenReturn(Collections.emptySet());

        authService.resetIdentity("user-1");

        verify(redisTemplate).delete("noisex:auth:uuid:user-1");
        verify(redisTemplate).delete("noisex:push:token:user-1");
        verify(redisTemplate).delete("noisex:block:user-1");
        verify(redisTemplate).delete("noisex:user:rooms:user-1");
        verify(redisTemplate).delete("noisex:user:listening_geohashes:user-1");
        verify(redisTemplate).delete("noisex:sonar:received:user-1");
        verify(redisTemplate).delete("noisex:rate:sonar:user-1");
        verify(redisTemplate).delete("noisex:rate:msg:user-1");
        verify(setOperations).remove("noisex:online", "user-1");

        verify(userProfileRepository).deleteById("user-1");
        verify(savedConnectionRepository).deleteByUserId("user-1");
        verify(userBlockRepository).deleteByUserId("user-1");
        verify(reportRepository).deleteByReporterId("user-1");
        // 保存的片段是明文，重置身份漏删=隐私政策承诺落空（2026-11-06 补）
        verify(savedMomentRepository).deleteByUserId("user-1");
    }

    @Test
    void resetIdentity_withActiveRooms_shouldNotifyOtherPartyAndCleanup() {
        String roomId = "room-123";
        when(setOperations.members("noisex:user:rooms:user-1")).thenReturn(Set.of("room-123"));

        org.springframework.data.redis.core.ValueOperations<String, String> stringValueOps = mock();
        when(stringRedisTemplate.opsForValue()).thenReturn(stringValueOps);
        when(stringValueOps.get("noisex:room:users:room-123")).thenReturn("user-1,other-user");

        authService.resetIdentity("user-1");

        verify(webSocketHandler).notifyRoomExpired("other-user", roomId);
        verify(pushService).sendPush(eq("other-user"), anyString(), anyString(), anyMap());

        verify(redisTemplate).delete("noisex:room:room-123");
        verify(redisTemplate).delete("noisex:room:messages:room-123");
        verify(redisTemplate).delete("noisex:room:deep:room-123");
        verify(redisTemplate).delete("noisex:room:save:room-123");
        verify(redisTemplate).delete("noisex:room:read:room-123");
        verify(redisTemplate).delete("noisex:room:users:room-123");
        verify(zSetOperations).remove("noisex:room:created_at", roomId);
    }

    @Test
    void resetIdentity_withNullRooms_shouldNotThrow() {
        when(setOperations.members("noisex:user:rooms:user-1")).thenReturn(null);

        assertDoesNotThrow(() -> authService.resetIdentity("user-1"));

        verify(userProfileRepository).deleteById("user-1");
    }
}
