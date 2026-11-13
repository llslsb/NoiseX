package com.noisex.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.noisex.model.entity.CompensationEntity;
import com.noisex.model.entity.CompensationEntity.CompensationStatus;
import com.noisex.model.repository.CompensationRepository;
import com.noisex.util.IdGenerator;
import com.noisex.util.RedisKeys;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class CompensationService {

    private final CompensationRepository compensationRepository;
    private final BlockService blockService;
    private final AdminService adminService;
    private final RedisTemplate<String, Object> redisTemplate;
    private final StringRedisTemplate stringRedisTemplate;
    private final ObjectMapper objectMapper;

    private static final long RETRY_DELAY_MS = 5_000L;
    private static final int MAX_RETRIES = 3;

    @Transactional
    public CompensationEntity recordCompensation(String operation, Object payload) {
        String jsonPayload;
        try {
            jsonPayload = objectMapper.writeValueAsString(payload);
        } catch (JsonProcessingException e) {
            log.error("Failed to serialize compensation payload", e);
            jsonPayload = "{}";
        }
        long now = System.currentTimeMillis();
        CompensationEntity entity =
                CompensationEntity.builder()
                        .id(IdGenerator.nextId())
                        .operation(operation)
                        .payload(jsonPayload)
                        .status(CompensationStatus.PENDING)
                        .retryCount(0)
                        .maxRetries(MAX_RETRIES)
                        .createdAt(now)
                        .nextRetryAt(now + RETRY_DELAY_MS)
                        .build();
        return compensationRepository.save(entity);
    }

    @Transactional
    public void markDone(String compensationId) {
        compensationRepository.updateStatus(compensationId, CompensationStatus.DONE);
    }

    @Transactional
    public void markFailed(String compensationId) {
        compensationRepository.updateStatus(compensationId, CompensationStatus.FAILED);
    }

    // 必须开启事务：processBatch 内部经 this. 调用 markDone/markFailed（self-invocation），
    // 其 @Transactional 不会生效；若外层无事务，updateStatus(@Modifying) 将抛
    // TransactionRequiredException，补偿任务永远无法标记完成并每 10 秒重复重试。
    @Transactional
    @Scheduled(fixedRate = 10_000)
    public void retryPendingCompensations() {
        long now = System.currentTimeMillis();
        List<CompensationEntity> pending =
                compensationRepository.findByStatusAndNextRetryAtBefore(
                        CompensationStatus.PENDING, now);
        List<CompensationEntity> retrying =
                compensationRepository.findByStatusAndNextRetryAtBefore(
                        CompensationStatus.RETRYING, now);
        processBatch(pending);
        processBatch(retrying);
    }

    private void processBatch(List<CompensationEntity> tasks) {
        for (CompensationEntity task : tasks) {
            try {
                executeCompensation(task);
                markDone(task.getId());
                log.info("Compensation completed: id={}, op={}", task.getId(), task.getOperation());
            } catch (Exception e) {
                int newRetryCount = task.getRetryCount() + 1;
                if (newRetryCount >= task.getMaxRetries()) {
                    markFailed(task.getId());
                    log.error(
                            "Compensation failed after {} retries: id={}, op={}",
                            newRetryCount,
                            task.getId(),
                            task.getOperation(),
                            e);
                } else {
                    task.setRetryCount(newRetryCount);
                    task.setStatus(CompensationStatus.RETRYING);
                    task.setNextRetryAt(
                            System.currentTimeMillis() + RETRY_DELAY_MS * (1L << newRetryCount));
                    compensationRepository.save(task);
                    log.warn(
                            "Compensation retry {}/{}: id={}, op={}",
                            newRetryCount,
                            task.getMaxRetries(),
                            task.getId(),
                            task.getOperation(),
                            e);
                }
            }
        }
    }

    private void executeCompensation(CompensationEntity task) throws Exception {
        JsonNode payload = objectMapper.readTree(task.getPayload());
        switch (task.getOperation()) {
            case "block_user_redis" -> executeBlockUserRedis(payload);
            case "save_connection_redis" -> executeSaveConnectionRedis(payload);
            case "review_report_redis" -> executeReviewReportRedis(payload);
            default -> log.warn("Unknown compensation operation: {}", task.getOperation());
        }
    }

    private void executeBlockUserRedis(JsonNode payload) {
        String blockerId = payload.path("blockerId").asText();
        String blockedId = payload.path("blockedId").asText();
        String cacheKey = RedisKeys.BLOCK_PREFIX + blockerId;
        redisTemplate.opsForSet().add(cacheKey, blockedId);
        redisTemplate.expire(cacheKey, Duration.ofHours(24));
        log.info("Compensation: block_user_redis {} -> {}", blockerId, blockedId);
    }

    private void executeSaveConnectionRedis(JsonNode payload) {
        String roomId = payload.path("roomId").asText();
        String saveKey = RedisKeys.ROOM_SAVE_PREFIX + roomId;
        Set<Object> agreed = redisTemplate.opsForSet().members(saveKey);
        if (agreed != null && agreed.size() >= 2) {
            log.info("Compensation: save_connection_redis already confirmed for room={}", roomId);
        } else {
            log.warn(
                    "Compensation: save_connection_redis room {} save set missing/expired", roomId);
        }
    }

    private void executeReviewReportRedis(JsonNode payload) {
        String roomId = payload.path("roomId").asText();
        JsonNode userIdNodes = payload.path("userIds");
        List<String> userIds = new ArrayList<>();
        if (userIdNodes.isArray()) {
            userIdNodes.forEach(node -> userIds.add(node.asText()));
        }

        redisTemplate.delete(RedisKeys.ROOM_PREFIX + roomId);
        redisTemplate.delete(RedisKeys.ROOM_MESSAGES_PREFIX + roomId);
        redisTemplate.delete(RedisKeys.ROOM_DEEP_PREFIX + roomId);
        redisTemplate.delete(RedisKeys.ROOM_SAVE_PREFIX + roomId);
        redisTemplate.delete(RedisKeys.ROOM_READ_PREFIX + roomId);
        redisTemplate.delete(RedisKeys.ROOM_USERS_PREFIX + roomId);
        stringRedisTemplate.opsForZSet().remove(RedisKeys.ROOM_CREATED_AT_ZSET, roomId);
        for (String userId : userIds) {
            redisTemplate.opsForSet().remove(RedisKeys.USER_ROOMS_PREFIX + userId, roomId);
        }

        // 补齐封禁（payload 携带成员列表，与首审一致且幂等；旧版无 userIds 的补偿单退化为纯清理）
        for (String userId : userIds) {
            adminService.banUser(userId);
        }
        log.info(
                "Compensation: review_report_redis room={}, bannedUsers={}",
                roomId,
                userIds.size());
    }

    @Scheduled(fixedRate = 300_000)
    public void reconcileData() {
        long pendingCount = compensationRepository.countByStatus(CompensationStatus.PENDING);
        long retryingCount = compensationRepository.countByStatus(CompensationStatus.RETRYING);
        long failedCount = compensationRepository.countByStatus(CompensationStatus.FAILED);
        if (pendingCount > 0 || retryingCount > 0 || failedCount > 0) {
            log.warn(
                    "Reconciliation: pending={}, retrying={}, failed={}",
                    pendingCount,
                    retryingCount,
                    failedCount);
        }
    }
}
