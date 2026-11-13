package com.noisex.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.noisex.model.entity.CompensationEntity;
import com.noisex.model.entity.CompensationEntity.CompensationStatus;
import com.noisex.model.repository.CompensationRepository;
import com.noisex.util.IdGenerator;
import java.util.HashSet;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 补偿任务事务回归测试。
 *
 * <p>背景:retryPendingCompensations(@Scheduled)内部经 this. 调用 markDone/markFailed
 * (self-invocation),其 @Transactional 不生效;若外层无事务,markDone/markFailed 中的 {@code @Modifying}
 * updateStatus 将抛 TransactionRequiredException,补偿任务永远无法 标记完成并每 10 秒重复重试(见 9f96bba 修复)。
 *
 * <p>为什么现有 CompensationServiceTest(纯 Mockito)发现不了:它直接 new 服务对象, 完全绕过 Spring 代理,加不加 @Transactional
 * 结果一样。本测试经 Spring 代理调用, 且用 {@code NOT_SUPPORTED} 保证测试方法自身不在事务中——若修复回退,本测试必然 以
 * TransactionRequiredException 失败。
 */
@DataJpaTest(
        properties = {
            "spring.flyway.enabled=false",
            "spring.jpa.hibernate.ddl-auto=create-drop",
            "spring.datasource.url=jdbc:h2:mem:comptx;MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE",
            "spring.datasource.driver-class-name=org.h2.Driver",
            "spring.datasource.username=sa",
            "spring.datasource.password=",
        })
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Import(CompensationService.class)
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class CompensationServiceTransactionTest {

    @Autowired private CompensationService compensationService;

    @Autowired private CompensationRepository compensationRepository;

    @MockBean private BlockService blockService;

    @MockBean private AdminService adminService;

    @MockBean private RedisTemplate<String, Object> redisTemplate;

    @MockBean private StringRedisTemplate stringRedisTemplate;

    private final SetOperations<String, Object> setOperations =
            org.mockito.Mockito.mock(SetOperations.class);

    /**
     * @DataJpaTest 切片不含 Jackson 自动配置,显式提供真实 ObjectMapper 供 payload 解析。
     */
    @TestConfiguration
    static class RealMapperConfig {
        @Bean
        ObjectMapper objectMapper() {
            return new ObjectMapper();
        }
    }

    @Test
    void retry_duePendingTask_shouldMarkDoneThroughRealTransaction() {
        CompensationEntity task =
                CompensationEntity.builder()
                        .id(IdGenerator.nextId())
                        .operation("save_connection_redis")
                        .payload("{\"roomId\":\"room-tx-pending\"}")
                        .status(CompensationStatus.PENDING)
                        .createdAt(System.currentTimeMillis())
                        .nextRetryAt(System.currentTimeMillis() - 1)
                        .build();
        compensationRepository.saveAndFlush(task);
        when(redisTemplate.opsForSet()).thenReturn(setOperations);
        when(setOperations.members(anyString()))
                .thenReturn(new HashSet<>(List.of("user-a", "user-b")));

        compensationService.retryPendingCompensations();

        CompensationEntity reloaded = compensationRepository.findById(task.getId()).orElseThrow();
        assertEquals(CompensationStatus.DONE, reloaded.getStatus());
    }

    @Test
    void retry_stuckRetryingTask_shouldAlsoMarkDone() {
        // 复刻线上事故场景:任务已卡在 RETRYING,每 10 秒重复重试且状态永远推不进
        CompensationEntity task =
                CompensationEntity.builder()
                        .id(IdGenerator.nextId())
                        .operation("save_connection_redis")
                        .payload("{\"roomId\":\"room-tx-retrying\"}")
                        .status(CompensationStatus.RETRYING)
                        .retryCount(1)
                        .createdAt(System.currentTimeMillis())
                        .nextRetryAt(System.currentTimeMillis() - 1)
                        .build();
        compensationRepository.saveAndFlush(task);
        when(redisTemplate.opsForSet()).thenReturn(setOperations);
        when(setOperations.members(anyString()))
                .thenReturn(new HashSet<>(List.of("user-a", "user-b")));

        compensationService.retryPendingCompensations();

        CompensationEntity reloaded = compensationRepository.findById(task.getId()).orElseThrow();
        assertEquals(CompensationStatus.DONE, reloaded.getStatus());
    }
}
