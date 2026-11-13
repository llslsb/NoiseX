package com.noisex.service;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.model.entity.ReportEntity;
import com.noisex.model.repository.ReportRepository;
import com.noisex.util.RedisKeys;
import com.noisex.websocket.NoiseXWebSocketHandler;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisCallback;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.data.redis.core.ZSetOperations;

@ExtendWith(MockitoExtension.class)
class AdminServiceTest {

    @Mock private ReportRepository reportRepository;

    @Mock private ReportService reportService;

    @Mock private RedisTemplate<String, Object> redisTemplate;

    @Mock private StringRedisTemplate stringRedisTemplate;

    @Mock private MeterRegistry meterRegistry;

    @Mock private CompensationService compensationService;

    @Mock private NoiseXWebSocketHandler webSocketHandler;

    private AdminService adminService;

    @BeforeEach
    void setUp() {
        adminService =
                new AdminService(
                        reportRepository,
                        reportService,
                        redisTemplate,
                        stringRedisTemplate,
                        meterRegistry,
                        compensationService,
                        webSocketHandler);
    }

    @Test
    void getReports_withPendingStatus_shouldCallRepository() {
        when(reportRepository.findByStatus(ReportEntity.ReportStatus.pending))
                .thenReturn(java.util.List.of());

        adminService.getReports("pending");

        verify(reportRepository).findByStatus(ReportEntity.ReportStatus.pending);
    }

    @Test
    void getReports_withNullStatus_shouldCallFindAll() {
        when(reportRepository.findByStatus(ReportEntity.ReportStatus.pending))
                .thenReturn(java.util.List.of());

        adminService.getReports(null);

        verify(reportRepository).findByStatus(ReportEntity.ReportStatus.pending);
    }

    @SuppressWarnings("unchecked")
    @Test
    void reviewReport_withActionBanned_shouldBlacklistTokenAndCallReportService() {
        ReportEntity report =
                ReportEntity.builder()
                        .id("report-1")
                        .reporterId("user-a")
                        .roomId("room-1")
                        .reason("spam")
                        .status(ReportEntity.ReportStatus.pending)
                        .createdAt(System.currentTimeMillis())
                        .build();

        when(reportRepository.findById("report-1")).thenReturn(Optional.of(report));
        when(reportRepository.save(report)).thenReturn(report);

        // ROOM_USERS 由 StringRedisTemplate 写入，读取也必须走 stringRedisTemplate
        ValueOperations<String, String> stringValueOps = mock(ValueOperations.class);
        when(stringRedisTemplate.opsForValue()).thenReturn(stringValueOps);
        when(stringValueOps.get(RedisKeys.ROOM_USERS_PREFIX + "room-1"))
                .thenReturn("user-a,user-b");

        // JWT 黑名单对象必须是 AuthService 缓存的真实 JWT，而不是推送 token
        ValueOperations<String, Object> valueOps = mock(ValueOperations.class);
        when(redisTemplate.opsForValue()).thenReturn(valueOps);
        when(valueOps.get(RedisKeys.AUTH_UUID_CACHE_PREFIX + "user-a")).thenReturn("jwt-a");
        when(valueOps.get(RedisKeys.AUTH_UUID_CACHE_PREFIX + "user-b")).thenReturn("jwt-b");

        SetOperations<String, String> stringSetOps = mock(SetOperations.class);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOps);

        ZSetOperations<String, String> stringZSetOps = mock(ZSetOperations.class);
        when(stringRedisTemplate.opsForZSet()).thenReturn(stringZSetOps);

        SetOperations<String, Object> roomSetOps = mock(SetOperations.class);
        when(redisTemplate.opsForSet()).thenReturn(roomSetOps);

        adminService.reviewReport("report-1", "banned");

        verify(reportRepository).save(report);
        assertThat(report.getStatus()).isEqualTo(ReportEntity.ReportStatus.banned);
        assertThat(report.getReviewedAt()).isNotNull();

        // 拉黑的是缓存 JWT；推送 token 不再进入 JWT 黑名单
        ArgumentCaptor<String> blacklisted = ArgumentCaptor.forClass(String.class);
        verify(stringSetOps, times(2)).add(eq(RedisKeys.JWT_BLACKLIST), blacklisted.capture());
        assertThat(blacklisted.getAllValues()).containsExactlyInAnyOrder("jwt-a", "jwt-b");
        verify(valueOps, never()).get(contains(RedisKeys.PUSH_TOKEN_PREFIX));

        // 双方均写入 7 天封禁标记 + 踢掉活跃 WS 会话
        verify(stringValueOps)
                .set(RedisKeys.USER_BANNED_PREFIX + "user-a", "1", Duration.ofDays(7));
        verify(stringValueOps)
                .set(RedisKeys.USER_BANNED_PREFIX + "user-b", "1", Duration.ofDays(7));
        verify(webSocketHandler).kickUser("user-a", "banned");
        verify(webSocketHandler).kickUser("user-b", "banned");

        // 补偿单携带成员列表，重试时才能补齐封禁
        verify(compensationService)
                .recordCompensation(
                        eq("review_report_redis"),
                        eq(Map.of("roomId", "room-1", "userIds", List.of("user-a", "user-b"))));
    }

    @SuppressWarnings("unchecked")
    @Test
    void reviewReport_banned_shouldReadRoomUsersBeforeDeleting() {
        ReportEntity report =
                ReportEntity.builder()
                        .id("report-3")
                        .reporterId("user-a")
                        .roomId("room-3")
                        .reason("spam")
                        .status(ReportEntity.ReportStatus.pending)
                        .createdAt(System.currentTimeMillis())
                        .build();

        when(reportRepository.findById("report-3")).thenReturn(Optional.of(report));
        when(reportRepository.save(report)).thenReturn(report);

        ValueOperations<String, String> stringValueOps = mock(ValueOperations.class);
        when(stringRedisTemplate.opsForValue()).thenReturn(stringValueOps);
        when(stringValueOps.get(RedisKeys.ROOM_USERS_PREFIX + "room-3"))
                .thenReturn("user-a,user-b");

        ValueOperations<String, Object> valueOps = mock(ValueOperations.class);
        when(redisTemplate.opsForValue()).thenReturn(valueOps);
        when(valueOps.get(anyString())).thenReturn("jwt-x");

        SetOperations<String, String> stringSetOps = mock(SetOperations.class);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOps);
        ZSetOperations<String, String> stringZSetOps = mock(ZSetOperations.class);
        when(stringRedisTemplate.opsForZSet()).thenReturn(stringZSetOps);
        SetOperations<String, Object> roomSetOps = mock(SetOperations.class);
        when(redisTemplate.opsForSet()).thenReturn(roomSetOps);

        adminService.reviewReport("report-3", "banned");

        // 关键顺序：先读成员再删 ROOM_USERS（先删后读是历史缺陷，导致拉黑不可达）
        InOrder inOrder = inOrder(stringValueOps, redisTemplate);
        inOrder.verify(stringValueOps).get(RedisKeys.ROOM_USERS_PREFIX + "room-3");
        inOrder.verify(redisTemplate).delete(RedisKeys.ROOM_USERS_PREFIX + "room-3");
    }

    @SuppressWarnings("unchecked")
    @Test
    void reviewReport_banned_withMissingRoomUsers_shouldStillCloseRoomWithoutBan() {
        ReportEntity report =
                ReportEntity.builder()
                        .id("report-4")
                        .reporterId("user-a")
                        .roomId("room-4")
                        .reason("spam")
                        .status(ReportEntity.ReportStatus.pending)
                        .createdAt(System.currentTimeMillis())
                        .build();

        when(reportRepository.findById("report-4")).thenReturn(Optional.of(report));
        when(reportRepository.save(report)).thenReturn(report);

        ValueOperations<String, String> stringValueOps = mock(ValueOperations.class);
        when(stringRedisTemplate.opsForValue()).thenReturn(stringValueOps);
        when(stringValueOps.get(RedisKeys.ROOM_USERS_PREFIX + "room-4")).thenReturn(null);

        ZSetOperations<String, String> stringZSetOps = mock(ZSetOperations.class);
        when(stringRedisTemplate.opsForZSet()).thenReturn(stringZSetOps);

        adminService.reviewReport("report-4", "banned");

        // 成员缺失（已过期/被清）时不抛异常：房间照常清理，无封禁动作，补偿单记空成员列表兜底
        verify(redisTemplate).delete(RedisKeys.ROOM_USERS_PREFIX + "room-4");
        verify(redisTemplate, never()).opsForValue();
        verify(webSocketHandler, never()).kickUser(anyString(), anyString());
        verify(compensationService)
                .recordCompensation(
                        eq("review_report_redis"),
                        eq(Map.of("roomId", "room-4", "userIds", List.of())));
    }

    @Test
    void reviewReport_withActionDismissed_shouldOnlyCallReportService() {
        ReportEntity report =
                ReportEntity.builder()
                        .id("report-2")
                        .reporterId("user-a")
                        .roomId("room-2")
                        .reason("noise")
                        .status(ReportEntity.ReportStatus.pending)
                        .createdAt(System.currentTimeMillis())
                        .build();

        when(reportRepository.findById("report-2")).thenReturn(Optional.of(report));
        when(reportRepository.save(report)).thenReturn(report);

        adminService.reviewReport("report-2", "dismissed");

        verify(reportRepository).save(report);
        assertThat(report.getStatus()).isEqualTo(ReportEntity.ReportStatus.dismissed);
        verify(redisTemplate, never()).delete(anyString());
    }

    @SuppressWarnings("unchecked")
    @Test
    void blacklistToken_shouldAddToRedisSet() {
        SetOperations<String, String> stringSetOps = mock(SetOperations.class);
        when(stringRedisTemplate.opsForSet()).thenReturn(stringSetOps);

        adminService.blacklistToken("some-jwt-token");

        verify(stringSetOps).add(RedisKeys.JWT_BLACKLIST, "some-jwt-token");
        verify(stringRedisTemplate).expire(RedisKeys.JWT_BLACKLIST, Duration.ofDays(7));
    }

    @SuppressWarnings("unchecked")
    @Test
    void getSystemStats_shouldReturnOnlineUsersAndPendingReports() {
        SetOperations<String, Object> setOps = mock(SetOperations.class);
        when(redisTemplate.opsForSet()).thenReturn(setOps);
        when(setOps.members(RedisKeys.ONLINE)).thenReturn(Set.of("user1", "user2", "user3"));

        when(reportRepository.countByStatus(ReportEntity.ReportStatus.pending)).thenReturn(5L);

        when(redisTemplate.execute(any(RedisCallback.class))).thenReturn(Set.of());

        SimpleMeterRegistry simpleRegistry = new SimpleMeterRegistry();
        AdminService adminServiceWithRealRegistry =
                new AdminService(
                        reportRepository,
                        reportService,
                        redisTemplate,
                        stringRedisTemplate,
                        simpleRegistry,
                        compensationService,
                        webSocketHandler);

        var stats = adminServiceWithRealRegistry.getSystemStats();

        assertThat(stats.getOnlineUsers()).isEqualTo(3);
        assertThat(stats.getPendingReports()).isEqualTo(5);
    }
}
