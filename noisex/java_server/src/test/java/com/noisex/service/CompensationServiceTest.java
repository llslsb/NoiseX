package com.noisex.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.noisex.model.entity.CompensationEntity;
import com.noisex.model.entity.CompensationEntity.CompensationStatus;
import com.noisex.model.repository.CompensationRepository;
import com.noisex.util.RedisKeys;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;

@ExtendWith(MockitoExtension.class)
class CompensationServiceTest {

    @Mock private CompensationRepository compensationRepository;
    @Mock private BlockService blockService;
    @Mock private AdminService adminService;
    @Mock private RedisTemplate<String, Object> redisTemplate;
    @Mock private StringRedisTemplate stringRedisTemplate;

    /**
     * 不 mock ObjectMapper：payload 解析必须真实可用（mock 返回 null 会让补偿任务在 readTree 处
     * 静默走异常分支，掩盖被测逻辑）；手工构造注入真实实例，同时避免依赖 matcher 栈的 readTree stub。
     */
    private final ObjectMapper objectMapper = new ObjectMapper();

    private CompensationService compensationService;

    @BeforeEach
    void setUp() {
        compensationService =
                new CompensationService(
                        compensationRepository,
                        blockService,
                        adminService,
                        redisTemplate,
                        stringRedisTemplate,
                        objectMapper);
    }

    @Test
    void recordCompensation_shouldSaveWithPendingStatus() throws Exception {
        CompensationEntity savedEntity =
                CompensationEntity.builder()
                        .id("comp-1")
                        .operation("block_user_redis")
                        .payload("{\"blockerId\":\"u1\",\"blockedId\":\"u2\"}")
                        .status(CompensationStatus.PENDING)
                        .retryCount(0)
                        .maxRetries(3)
                        .createdAt(System.currentTimeMillis())
                        .nextRetryAt(System.currentTimeMillis() + 5000)
                        .build();

        when(compensationRepository.save(any(CompensationEntity.class))).thenReturn(savedEntity);

        CompensationEntity result =
                compensationService.recordCompensation(
                        "block_user_redis", Map.of("blockerId", "u1", "blockedId", "u2"));

        ArgumentCaptor<CompensationEntity> captor =
                ArgumentCaptor.forClass(CompensationEntity.class);
        verify(compensationRepository).save(captor.capture());

        CompensationEntity captured = captor.getValue();
        assertThat(captured.getOperation()).isEqualTo("block_user_redis");
        assertThat(captured.getStatus()).isEqualTo(CompensationStatus.PENDING);
        assertThat(captured.getRetryCount()).isEqualTo(0);
        assertThat(captured.getMaxRetries()).isEqualTo(3);
    }

    @Test
    void markDone_shouldUpdateStatus() {
        compensationService.markDone("comp-1");
        verify(compensationRepository).updateStatus("comp-1", CompensationStatus.DONE);
    }

    @Test
    void markFailed_shouldUpdateStatus() {
        compensationService.markFailed("comp-1");
        verify(compensationRepository).updateStatus("comp-1", CompensationStatus.FAILED);
    }

    @Test
    void retryPendingCompensations_noPending_shouldDoNothing() {
        when(compensationRepository.findByStatusAndNextRetryAtBefore(
                        eq(CompensationStatus.PENDING), anyLong()))
                .thenReturn(Collections.emptyList());
        when(compensationRepository.findByStatusAndNextRetryAtBefore(
                        eq(CompensationStatus.RETRYING), anyLong()))
                .thenReturn(Collections.emptyList());

        compensationService.retryPendingCompensations();

        verify(compensationRepository, never()).updateStatus(anyString(), any());
    }

    @Test
    void retryPendingCompensations_exceedMaxRetries_shouldMarkFailed() throws Exception {
        CompensationEntity task =
                CompensationEntity.builder()
                        .id("comp-1")
                        .operation("block_user_redis")
                        .payload("{\"blockerId\":\"u1\",\"blockedId\":\"u2\"}")
                        .status(CompensationStatus.RETRYING)
                        .retryCount(2)
                        .maxRetries(3)
                        .createdAt(System.currentTimeMillis())
                        .nextRetryAt(0L)
                        .build();

        when(compensationRepository.findByStatusAndNextRetryAtBefore(
                        eq(CompensationStatus.PENDING), anyLong()))
                .thenReturn(List.of(task));
        when(compensationRepository.findByStatusAndNextRetryAtBefore(
                        eq(CompensationStatus.RETRYING), anyLong()))
                .thenReturn(Collections.emptyList());

        compensationService.retryPendingCompensations();

        verify(compensationRepository).updateStatus("comp-1", CompensationStatus.FAILED);
    }

    @Test
    void retryPendingCompensations_reviewReportRedis_shouldCleanupAndBanUsers() throws Exception {
        CompensationEntity task =
                CompensationEntity.builder()
                        .id("comp-ban-1")
                        .operation("review_report_redis")
                        .payload("{\"roomId\":\"room-1\",\"userIds\":[\"user-a\",\"user-b\"]}")
                        .status(CompensationStatus.PENDING)
                        .retryCount(0)
                        .maxRetries(3)
                        .createdAt(System.currentTimeMillis())
                        .nextRetryAt(0L)
                        .build();

        when(compensationRepository.findByStatusAndNextRetryAtBefore(
                        eq(CompensationStatus.PENDING), anyLong()))
                .thenReturn(List.of(task));
        when(compensationRepository.findByStatusAndNextRetryAtBefore(
                        eq(CompensationStatus.RETRYING), anyLong()))
                .thenReturn(Collections.emptyList());
        // 无参方法用 doReturn 家族 stub：不经 matcher 栈，不受同线程残留 matcher 影响
        org.springframework.data.redis.core.SetOperations<String, Object> setOps =
                mock(org.springframework.data.redis.core.SetOperations.class);
        doReturn(setOps).when(redisTemplate).opsForSet();
        org.springframework.data.redis.core.ZSetOperations<String, String> zSetOps =
                mock(org.springframework.data.redis.core.ZSetOperations.class);
        doReturn(zSetOps).when(stringRedisTemplate).opsForZSet();

        compensationService.retryPendingCompensations();

        verify(redisTemplate).delete(RedisKeys.ROOM_USERS_PREFIX + "room-1");
        verify(setOps).remove(RedisKeys.USER_ROOMS_PREFIX + "user-a", "room-1");
        verify(setOps).remove(RedisKeys.USER_ROOMS_PREFIX + "user-b", "room-1");
        verify(adminService).banUser("user-a");
        verify(adminService).banUser("user-b");
        verify(compensationRepository).updateStatus("comp-ban-1", CompensationStatus.DONE);
    }

    private String anyString() {
        return any(String.class);
    }
}
