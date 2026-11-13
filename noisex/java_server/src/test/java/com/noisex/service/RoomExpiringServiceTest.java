package com.noisex.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.noisex.websocket.NoiseXWebSocketHandler;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.DefaultTypedTuple;
import org.springframework.data.redis.core.HashOperations;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.data.redis.core.ZSetOperations;

/**
 * 房间过期清扫回归测试。
 *
 * <p>脏数据自愈回归背景：ZSet {@code noisex:room:created_at} 中一条历史裸串成员（未 JSON 引号包裹）使
 * GenericJackson2JsonRedisSerializer 的 rangeByScore 整批反序列化抛 SerializationException，30min tick
 * 持续崩溃、过期清扫全瘫（2026-10-31 实锤）。 修复后清扫改用 StringRedisTemplate 读原始成员并就地自愈重写。
 */
@ExtendWith(MockitoExtension.class)
class RoomExpiringServiceTest {

    @Mock private RedisTemplate<String, Object> redisTemplate;

    @Mock private StringRedisTemplate stringRedisTemplate;

    @Mock private NoiseXWebSocketHandler webSocketHandler;

    @Mock private PushService pushService;

    @Mock private ZSetOperations<String, Object> jsonZSet;

    @Mock private ZSetOperations<String, String> stringZSet;

    @Mock private HashOperations<String, Object, Object> hashOps;

    @Mock private ValueOperations<String, String> stringValueOps;

    @Mock private ValueOperations<String, Object> jsonValueOps;

    @Mock private SetOperations<String, Object> setOps;

    private RoomExpiringService roomExpiringService;

    @BeforeEach
    void setUp() {
        roomExpiringService =
                new RoomExpiringService(
                        redisTemplate, stringRedisTemplate, webSocketHandler, pushService);
        lenient().when(redisTemplate.opsForZSet()).thenReturn(jsonZSet);
        lenient().when(stringRedisTemplate.opsForZSet()).thenReturn(stringZSet);
        lenient().when(redisTemplate.opsForHash()).thenReturn(hashOps);
        lenient().when(redisTemplate.opsForValue()).thenReturn(jsonValueOps);
        lenient().when(redisTemplate.opsForSet()).thenReturn(setOps);
        lenient().when(stringRedisTemplate.opsForValue()).thenReturn(stringValueOps);
    }

    private Set<ZSetOperations.TypedTuple<String>> tuples(Object... valueScorePairs) {
        Set<ZSetOperations.TypedTuple<String>> result = new LinkedHashSet<>();
        for (int i = 0; i < valueScorePairs.length; i += 2) {
            result.add(
                    new DefaultTypedTuple<>(
                            (String) valueScorePairs[i], (Double) valueScorePairs[i + 1]));
        }
        return result;
    }

    @Test
    void checkExpiringRooms_whenNoUserRooms_shouldDoNothing() {
        when(stringZSet.rangeByScoreWithScores(anyString(), anyDouble(), anyDouble()))
                .thenReturn(java.util.Collections.emptySet());

        roomExpiringService.checkExpiringRooms();

        verify(webSocketHandler, never()).notifyRoomExpiring(anyString(), anyDouble());
    }

    @Test
    void checkExpiringRooms_whenScanReturnsNull_shouldDoNothing() {
        when(stringZSet.rangeByScoreWithScores(anyString(), anyDouble(), anyDouble()))
                .thenReturn(null);

        roomExpiringService.checkExpiringRooms();

        verify(webSocketHandler, never()).notifyRoomExpiring(anyString(), anyDouble());
    }

    @Test
    void rawDirtyMemberIsHealedAndSweepContinues() {
        long now = System.currentTimeMillis();
        long expiresAt = now + 3600_000L; // 1h 后过期 → 命中临终通知分支
        when(stringZSet.rangeByScoreWithScores(anyString(), anyDouble(), anyDouble()))
                .thenReturn(tuples("room-111-dirty", 100.0, "\"room-222-clean\"", 200.0));

        when(hashOps.entries("noisex:room:room-111-dirty"))
                .thenReturn(Map.of("expiresAt", String.valueOf(expiresAt)));
        when(hashOps.entries("noisex:room:room-222-clean"))
                .thenReturn(Map.of("expiresAt", String.valueOf(expiresAt)));
        when(redisTemplate.hasKey(anyString())).thenReturn(false);
        when(stringValueOps.get(contains("room-111-dirty"))).thenReturn("user-9");
        when(stringValueOps.get(contains("room-222-clean"))).thenReturn("user-8");

        roomExpiringService.checkExpiringRooms();

        // 自愈：裸串成员按原始字节删除，再按 JSON 模板规范重写（分数保留）
        verify(stringZSet).remove("noisex:room:created_at", "room-111-dirty");
        ArgumentCaptor<Double> scoreCaptor = ArgumentCaptor.forClass(Double.class);
        verify(jsonZSet)
                .add(eq("noisex:room:created_at"), eq("room-111-dirty"), scoreCaptor.capture());
        assertEquals(100.0, scoreCaptor.getValue());

        // 规范成员不做自愈重写
        verify(jsonZSet, never())
                .add(eq("noisex:room:created_at"), eq("room-222-clean"), anyDouble());

        // 清扫未被打断：两个房间都走到临终通知
        verify(webSocketHandler).notifyRoomExpiring(eq("room-111-dirty"), anyDouble());
        verify(webSocketHandler).notifyRoomExpiring(eq("room-222-clean"), anyDouble());
        verify(pushService).sendPush(eq("user-9"), anyString(), contains("小时后过期"), any());
        verify(pushService).sendPush(eq("user-8"), anyString(), contains("小时后过期"), any());
    }

    @Test
    void alreadyExpiredRoomIsRemoved() {
        long now = System.currentTimeMillis();
        long expiresAt = now - 1000L; // 已过期
        when(stringZSet.rangeByScoreWithScores(anyString(), anyDouble(), anyDouble()))
                .thenReturn(tuples("\"room-333\"", 300.0));

        when(hashOps.entries("noisex:room:room-333"))
                .thenReturn(Map.of("expiresAt", String.valueOf(expiresAt)));
        when(stringValueOps.get("noisex:room:users:room-333")).thenReturn("user-7");

        roomExpiringService.checkExpiringRooms();

        // 过期房间：清用户反查引用 + 移出 ZSet；不发临终通知
        verify(setOps).remove("noisex:user:rooms:user-7", "room-333");
        verify(jsonZSet).remove("noisex:room:created_at", "room-333");
        verify(webSocketHandler, never()).notifyRoomExpiring(anyString(), anyDouble());
    }
}
