package com.noisex.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.noisex.exception.BusinessException;
import com.noisex.exception.NotFoundException;
import com.noisex.exception.RateLimitException;
import com.noisex.model.domain.SonarData;
import com.noisex.model.dto.SonarDataResponse;
import com.noisex.websocket.NoiseXWebSocketHandler;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.Collections;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.data.redis.core.ListOperations;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class SonarServiceTest {

    @Mock private RedisTemplate<String, Object> redisTemplate;

    @Mock private StringRedisTemplate stringRedisTemplate;

    @Mock private MatchEngine matchEngine;

    @Mock private ChatService chatService;

    @Mock private NoiseXWebSocketHandler webSocketHandler;

    @Mock private ListOperations<String, Object> listOperations;

    @Mock private SetOperations<String, Object> setOperations;

    @Mock private BlockService blockService;

    @Mock private PushService pushService;

    private Counter sonarSentCounter;
    private Counter sonarAcceptedCounter;

    private SonarService sonarService;

    @BeforeEach
    void setUp() {
        MeterRegistry registry = new SimpleMeterRegistry();
        sonarSentCounter = Counter.builder("noisex.sonar.sent.total").register(registry);
        sonarAcceptedCounter = Counter.builder("noisex.sonar.accepted.total").register(registry);

        // 手动构造，避免 @InjectMocks 因 StringRedisTemplate 继承 RedisTemplate 导致类型擦除注入错误
        sonarService =
                new SonarService(
                        redisTemplate,
                        stringRedisTemplate,
                        matchEngine,
                        chatService,
                        webSocketHandler,
                        blockService,
                        pushService,
                        sonarSentCounter,
                        sonarAcceptedCounter);
        ReflectionTestUtils.setField(sonarService, "maxSonarPerHour", 3);
        ReflectionTestUtils.setField(sonarService, "maxContentLength", 140);
        ReflectionTestUtils.setField(sonarService, "duplicateWindowSeconds", 30);
        when(redisTemplate.opsForList()).thenReturn(listOperations);
        lenient().when(redisTemplate.opsForSet()).thenReturn(setOperations);
    }

    @Test
    void sendSonar_withinRateLimit_shouldSucceed() {
        when(stringRedisTemplate.execute(any(), anyList(), anyString())).thenReturn(1L);
        when(listOperations.leftPush(anyString(), any())).thenReturn(1L);

        String sonarId = sonarService.sendSonar("user-1", "Hello world", "wx4g0s");

        assertNotNull(sonarId);
        assertTrue(sonarId.startsWith("sonar-"));
        verify(matchEngine).onNewSonar("wx4g0s", "user-1");
    }

    @Test
    void sendSonar_exceedRateLimit_shouldThrow() {
        when(stringRedisTemplate.execute(any(), anyList(), anyString())).thenReturn(4L);

        assertThrows(
                RateLimitException.class,
                () -> sonarService.sendSonar("user-1", "Hello", "wx4g0s"));
    }

    @Test
    void getReceivedSonars_noSonars_shouldReturnEmpty() {
        when(listOperations.range(anyString(), eq(0L), eq(-1L)))
                .thenReturn(Collections.emptyList());

        List<SonarDataResponse> result = sonarService.getReceivedSonars("user-1");

        assertTrue(result.isEmpty());
    }

    @Test
    void getReceivedSonars_withSonars_shouldReturnList() {
        SonarData sonar =
                SonarData.builder()
                        .id("sonar-123")
                        .userId("user-2")
                        .content("Hi")
                        .geohash("wx4g0s")
                        .timestamp(System.currentTimeMillis())
                        .build();
        when(listOperations.range(anyString(), eq(0L), eq(-1L))).thenReturn(List.of(sonar));

        List<SonarDataResponse> result = sonarService.getReceivedSonars("user-1");

        assertEquals(1, result.size());
        assertEquals("sonar-123", result.get(0).getId());
        assertEquals("Hi", result.get(0).getContent());
    }

    @Test
    void acceptSonar_sonarNotFound_shouldThrow() {
        when(listOperations.range(anyString(), eq(0L), eq(-1L)))
                .thenReturn(Collections.emptyList());

        assertThrows(
                NotFoundException.class,
                () -> sonarService.acceptSonar("user-1", "sonar-nonexist"));
    }

    @Test
    void ignoreSonar_sonarNotFound_shouldNotThrow() {
        when(listOperations.range(anyString(), eq(0L), eq(-1L)))
                .thenReturn(Collections.emptyList());

        assertDoesNotThrow(() -> sonarService.ignoreSonar("user-1", "sonar-nonexist"));
    }

    @Test
    void pushSonarToUser_shouldCallPushService() {
        SonarData sonar =
                SonarData.builder()
                        .id("sonar-123")
                        .userId("user-2")
                        .content("Hi nearby")
                        .geohash("wx4g0s")
                        .timestamp(System.currentTimeMillis())
                        .build();
        when(blockService.isBlocked("user-1", "user-2")).thenReturn(false);
        when(listOperations.leftPush(anyString(), any())).thenReturn(1L);

        sonarService.pushSonarToUser("user-1", sonar);

        verify(pushService).sendPush(eq("user-1"), eq("收到新声呐"), eq("Hi nearby"), anyMap());
    }

    @Test
    void pushSonarToUser_blockedUser_shouldNotPush() {
        SonarData sonar =
                SonarData.builder()
                        .id("sonar-123")
                        .userId("user-2")
                        .content("Hi")
                        .geohash("wx4g0s")
                        .timestamp(System.currentTimeMillis())
                        .build();
        when(blockService.isBlocked("user-1", "user-2")).thenReturn(true);

        sonarService.pushSonarToUser("user-1", sonar);

        verify(pushService, never()).sendPush(anyString(), anyString(), anyString(), anyMap());
    }

    @Test
    void sendSonar_duplicateContent_shouldThrow() {
        // 频率限制通过
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> rateScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(SonarService.class, "RATE_LIMIT_SCRIPT");
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> dupScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(SonarService.class, "SONAR_DUPLICATE_SCRIPT");
        lenient()
                .when(stringRedisTemplate.execute(eq(rateScript), anyList(), anyString()))
                .thenReturn(1L);
        // 内容重复检测返回 1（重复）
        lenient()
                .when(stringRedisTemplate.execute(eq(dupScript), anyList(), any(), any()))
                .thenReturn(1L);

        assertThrows(
                BusinessException.class,
                () -> sonarService.sendSonar("user-1", "Same content", "wx4g0s"));
    }

    @Test
    void sendSonar_differentContent_shouldSucceed() {
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> rateScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(SonarService.class, "RATE_LIMIT_SCRIPT");
        org.springframework.data.redis.core.script.DefaultRedisScript<Long> dupScript =
                (org.springframework.data.redis.core.script.DefaultRedisScript<Long>)
                        ReflectionTestUtils.getField(SonarService.class, "SONAR_DUPLICATE_SCRIPT");
        when(stringRedisTemplate.execute(eq(rateScript), anyList(), anyString())).thenReturn(1L);
        // 内容不重复，返回 0
        when(stringRedisTemplate.execute(eq(dupScript), anyList(), any(), any())).thenReturn(0L);
        when(listOperations.leftPush(anyString(), any())).thenReturn(1L);

        String sonarId = sonarService.sendSonar("user-1", "New content", "wx4g0s");

        assertNotNull(sonarId);
        verify(matchEngine).onNewSonar("wx4g0s", "user-1");
    }

    // ========== getNearbyActivity 测试（P2-B 雷达 blip 真实化） ==========

    @Test
    void getNearbyActivity_rawZero_returnsZero() {
        // 真实附近无人在线：如实上报 0（2026-10-31 决策：废除 floor=3 假数据，反表演）
        when(matchEngine.countNearbyListeners(eq("wx4g0s"), eq("user-1"))).thenReturn(0);

        com.noisex.model.dto.NearbyActivityResponse resp =
                sonarService.getNearbyActivity("user-1", "wx4g0s");

        assertEquals(0, resp.getNearbyCount());
        assertEquals(0, resp.getBlipCount());
    }

    @Test
    void getNearbyActivity_rawMid_returnsRaw() {
        when(matchEngine.countNearbyListeners(eq("wx4g0s"), eq("user-1"))).thenReturn(5);

        com.noisex.model.dto.NearbyActivityResponse resp =
                sonarService.getNearbyActivity("user-1", "wx4g0s");

        // 中间值原样返回：nearbyCount=5，blipCount=min(8,5)=5
        assertEquals(5, resp.getNearbyCount());
        assertEquals(5, resp.getBlipCount());
    }

    @Test
    void getNearbyActivity_rawLarge_blipsCappedAt8() {
        when(matchEngine.countNearbyListeners(eq("wx4g0s"), eq("user-1"))).thenReturn(20);

        com.noisex.model.dto.NearbyActivityResponse resp =
                sonarService.getNearbyActivity("user-1", "wx4g0s");

        // 计数真实上报（不再 cap=12 截断）；blip 渲染上限 8
        assertEquals(20, resp.getNearbyCount());
        assertEquals(8, resp.getBlipCount());
    }
}
