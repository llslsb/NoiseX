package com.noisex.service;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.mockito.Mockito.doReturn;

import com.noisex.model.domain.SonarData;
import com.noisex.websocket.NoiseXWebSocketHandler;
import java.util.Collections;
import java.util.Set;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.ListOperations;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
@org.mockito.junit.jupiter.MockitoSettings(strictness = org.mockito.quality.Strictness.LENIENT)
class MatchEngineTest {

    @Mock private RedisTemplate<String, Object> redisTemplate;

    @Mock private StringRedisTemplate stringRedisTemplate;

    @Mock private SonarService sonarService;

    @Mock private NoiseXWebSocketHandler webSocketHandler;

    @Mock private SetOperations<String, Object> setOperations;

    @Mock private ListOperations<String, Object> listOperations;

    @Mock private com.noisex.service.BlockService blockService;

    private MatchEngine matchEngine;

    @BeforeEach
    void setUp() {
        // 手动构造 MatchEngine 避免 @InjectMocks 与 @Lazy 冲突导致 NPE
        matchEngine =
                new MatchEngine(
                        redisTemplate,
                        stringRedisTemplate,
                        sonarService,
                        webSocketHandler,
                        blockService);
        ReflectionTestUtils.setField(matchEngine, "maxExpandLevel", 2);
        doReturn(setOperations).when(redisTemplate).opsForSet();
        doReturn(listOperations).when(redisTemplate).opsForList();
        doReturn(java.util.Collections.singleton("noisex:sonar:queue:wx4g0s"))
                .when(stringRedisTemplate)
                .keys(anyString());
    }

    // ========== onNewListener 测试 ==========

    @Test
    void onNewListener_noSonarsInQueue_shouldNotPush() {
        when(listOperations.leftPop(anyString())).thenReturn(null);

        matchEngine.onNewListener("wx4g0s", "listener-1");

        verify(sonarService, never()).pushSonarToUser(anyString(), any());
    }

    @Test
    void onNewListener_sonarFromSelf_shouldPutBackInQueue() {
        SonarData selfSonar =
                SonarData.builder()
                        .id("sonar-1")
                        .userId("listener-1")
                        .content("Hi")
                        .geohash("wx4g0s")
                        .timestamp(System.currentTimeMillis())
                        .build();

        when(listOperations.leftPop(anyString())).thenReturn(selfSonar);
        when(setOperations.isMember(anyString(), eq("listener-1"))).thenReturn(true);

        matchEngine.onNewListener("wx4g0s", "listener-1");

        verify(sonarService, never()).pushSonarToUser(anyString(), any());
        // 验证声呐被放回队列而不是丢弃
        verify(listOperations, atLeastOnce()).rightPush(anyString(), eq(selfSonar));
    }

    @Test
    void onNewListener_sonarSenderOffline_shouldPutBackInQueue() {
        SonarData offlineSonar =
                SonarData.builder()
                        .id("sonar-1")
                        .userId("offline-user")
                        .content("Hi")
                        .geohash("wx4g0s")
                        .timestamp(System.currentTimeMillis())
                        .build();

        when(listOperations.leftPop(anyString())).thenReturn(offlineSonar);
        when(setOperations.isMember(anyString(), eq("offline-user"))).thenReturn(false);

        matchEngine.onNewListener("wx4g0s", "listener-1");

        verify(sonarService, never()).pushSonarToUser(anyString(), any());
        // 验证声呐被放回队列而不是丢弃
        verify(listOperations, atLeastOnce()).rightPush(anyString(), eq(offlineSonar));
    }

    @Test
    void onNewListener_validSonar_shouldPushToListener() {
        SonarData validSonar =
                SonarData.builder()
                        .id("sonar-1")
                        .userId("online-user")
                        .content("Hello!")
                        .geohash("wx4g0s")
                        .timestamp(System.currentTimeMillis())
                        .build();

        when(listOperations.leftPop(anyString())).thenReturn(validSonar);
        when(setOperations.isMember(anyString(), eq("online-user"))).thenReturn(true);
        when(blockService.isBlocked(eq("listener-1"), eq("online-user"))).thenReturn(false);

        matchEngine.onNewListener("wx4g0s", "listener-1");

        verify(sonarService).pushSonarToUser("listener-1", validSonar);
    }

    @Test
    void onNewListener_shouldAddListenerToSet() {
        when(listOperations.leftPop(anyString())).thenReturn(null);

        matchEngine.onNewListener("wx4g0s", "listener-1");

        verify(setOperations).add(contains("listener:"), eq("listener-1"));
    }

    // ========== onNewSonar 测试 ==========

    @Test
    void onNewSonar_noListeners_shouldNotPush() {
        when(setOperations.members(anyString())).thenReturn(Collections.emptySet());

        matchEngine.onNewSonar("wx4g0s", "sender-1");

        verify(sonarService, never()).pushSonarToUser(anyString(), any());
    }

    @Test
    void onNewSonar_listenerIsSender_shouldSkip() {
        // listener 集合中只有发送者自己
        when(setOperations.members(anyString())).thenReturn(Set.of("sender-1"));

        matchEngine.onNewSonar("wx4g0s", "sender-1");

        verify(sonarService, never()).pushSonarToUser(anyString(), any());
        // 不应从队列取声呐
        verify(listOperations, never()).leftPop(anyString());
    }

    @Test
    void onNewSonar_listenerOffline_shouldSkip() {
        when(setOperations.members(anyString())).thenReturn(Set.of("offline-listener"));
        when(setOperations.isMember(anyString(), eq("offline-listener"))).thenReturn(false);

        matchEngine.onNewSonar("wx4g0s", "sender-1");

        verify(sonarService, never()).pushSonarToUser(anyString(), any());
    }

    @Test
    void onNewSonar_listenerBlocked_shouldSkip() {
        when(setOperations.members(anyString())).thenReturn(Set.of("blocked-listener"));
        when(setOperations.isMember(anyString(), eq("blocked-listener"))).thenReturn(true);
        when(blockService.isBlocked(eq("blocked-listener"), eq("sender-1"))).thenReturn(true);

        matchEngine.onNewSonar("wx4g0s", "sender-1");

        verify(sonarService, never()).pushSonarToUser(anyString(), any());
    }

    @Test
    void onNewSonar_validListener_shouldPushSonar() {
        SonarData sonar =
                SonarData.builder()
                        .id("sonar-1")
                        .userId("sender-1")
                        .content("Hello!")
                        .geohash("wx4g0s")
                        .timestamp(System.currentTimeMillis())
                        .build();

        when(setOperations.members(anyString())).thenReturn(Set.of("listener-1"));
        when(setOperations.isMember(anyString(), eq("listener-1"))).thenReturn(true);
        when(blockService.isBlocked(eq("listener-1"), eq("sender-1"))).thenReturn(false);
        when(listOperations.leftPop(anyString())).thenReturn(sonar);

        matchEngine.onNewSonar("wx4g0s", "sender-1");

        verify(sonarService).pushSonarToUser("listener-1", sonar);
    }

    // ========== countNearbyListeners 测试（P2-B 雷达 blip 真实化） ==========

    @Test
    void countNearbyListeners_excludesSelf() {
        // 同级网格只有自己
        when(setOperations.members(eq("noisex:listener:wx4g0s"))).thenReturn(Set.of("self"));
        // 扩展级别返回的 keys 也只命中同一份成员，避免重复计数干扰
        doReturn(Collections.emptySet()).when(stringRedisTemplate).keys(anyString());

        int count = matchEngine.countNearbyListeners("wx4g0s", "self");

        org.junit.jupiter.api.Assertions.assertEquals(0, count);
        verify(sonarService, never()).pushSonarToUser(anyString(), any());
    }

    @Test
    void countNearbyListeners_excludesOffline() {
        when(setOperations.members(eq("noisex:listener:wx4g0s")))
                .thenReturn(Set.of("user-online", "user-offline"));
        doReturn(Collections.emptySet()).when(stringRedisTemplate).keys(anyString());
        // 在线状态：online 在 noisex:online，offline 不在
        when(setOperations.isMember(eq("noisex:online"), eq("user-online"))).thenReturn(true);
        when(setOperations.isMember(eq("noisex:online"), eq("user-offline"))).thenReturn(false);
        when(blockService.isBlocked(anyString(), anyString())).thenReturn(false);

        int count = matchEngine.countNearbyListeners("wx4g0s", "self");

        org.junit.jupiter.api.Assertions.assertEquals(1, count);
    }

    @Test
    void countNearbyListeners_excludesBlocked() {
        when(setOperations.members(eq("noisex:listener:wx4g0s")))
                .thenReturn(Set.of("user-blocked", "user-ok"));
        doReturn(Collections.emptySet()).when(stringRedisTemplate).keys(anyString());
        when(setOperations.isMember(eq("noisex:online"), anyString())).thenReturn(true);
        when(blockService.isBlocked(eq("user-blocked"), eq("self"))).thenReturn(true);
        when(blockService.isBlocked(eq("user-ok"), eq("self"))).thenReturn(false);

        int count = matchEngine.countNearbyListeners("wx4g0s", "self");

        org.junit.jupiter.api.Assertions.assertEquals(1, count);
    }

    @Test
    void countNearbyListeners_dedupesAcrossLevels() {
        // 同级网格 level=0 命中 user-a；level>0 通过 keys 扫描的子网格也命中同一个 user-a
        when(setOperations.members(eq("noisex:listener:wx4g0s"))).thenReturn(Set.of("user-a"));
        doReturn(java.util.Collections.singleton("noisex:listener:wx4g0s2"))
                .when(stringRedisTemplate)
                .keys(anyString());
        when(setOperations.members(eq("noisex:listener:wx4g0s2"))).thenReturn(Set.of("user-a"));
        when(setOperations.isMember(eq("noisex:online"), eq("user-a"))).thenReturn(true);
        when(blockService.isBlocked(anyString(), anyString())).thenReturn(false);

        int count = matchEngine.countNearbyListeners("wx4g0s", "self");

        // 应去重为 1，而不是被计数多次
        org.junit.jupiter.api.Assertions.assertEquals(1, count);
    }

    @Test
    void countNearbyListeners_emptyResult_returnsZero() {
        when(setOperations.members(anyString())).thenReturn(Collections.emptySet());
        doReturn(Collections.emptySet()).when(stringRedisTemplate).keys(anyString());

        int count = matchEngine.countNearbyListeners("wx4g0s", "self");

        org.junit.jupiter.api.Assertions.assertEquals(0, count);
    }
}
