package com.noisex.service;

import com.noisex.model.entity.CompensationEntity;
import com.noisex.model.entity.UserBlockEntity;
import com.noisex.model.entity.UserBlockId;
import com.noisex.model.repository.UserBlockRepository;
import com.noisex.util.RedisKeys;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
public class BlockService {

    private final UserBlockRepository blockRepository;
    private final RedisTemplate<String, Object> redisTemplate;
    private final CompensationService compensationService;

    public BlockService(
            UserBlockRepository blockRepository,
            RedisTemplate<String, Object> redisTemplate,
            @Lazy CompensationService compensationService) {
        this.blockRepository = blockRepository;
        this.redisTemplate = redisTemplate;
        this.compensationService = compensationService;
    }

    private static final String BLOCK_PREFIX = RedisKeys.BLOCK_PREFIX;

    @Transactional
    public void blockUser(String blockerId, String blockedId) {
        UserBlockId id = new UserBlockId(blockerId, blockedId);
        if (!blockRepository.existsById(id)) {
            UserBlockEntity entity = new UserBlockEntity(id, System.currentTimeMillis());
            blockRepository.save(entity);

            CompensationEntity compensation =
                    compensationService.recordCompensation(
                            "block_user_redis",
                            Map.of("blockerId", blockerId, "blockedId", blockedId));

            try {
                String cacheKey = BLOCK_PREFIX + blockerId;
                redisTemplate.opsForSet().add(cacheKey, blockedId);
                redisTemplate.expire(cacheKey, Duration.ofHours(24));
                compensationService.markDone(compensation.getId());
            } catch (Exception e) {
                log.warn("Redis cache update failed for blockUser, compensation will retry", e);
            }

            log.info("User blocked: {} -> {}", blockerId, blockedId);
        }
    }

    public boolean isBlocked(String blockerId, String blockedId) {
        String cacheKey = BLOCK_PREFIX + blockerId;
        Boolean cached = redisTemplate.opsForSet().isMember(cacheKey, blockedId);
        if (cached != null && cached) {
            return true;
        }
        boolean blocked = blockRepository.existsById_BlockerIdAndId_BlockedId(blockerId, blockedId);
        if (blocked) {
            redisTemplate.opsForSet().add(cacheKey, blockedId);
            redisTemplate.expire(cacheKey, Duration.ofHours(24));
        }
        return blocked;
    }

    public Set<String> getBlockedList(String userId) {
        String cacheKey = BLOCK_PREFIX + userId;
        Set<Object> cached = redisTemplate.opsForSet().members(cacheKey);
        if (cached != null && !cached.isEmpty()) {
            return cached.stream().map(Object::toString).collect(Collectors.toSet());
        }
        List<UserBlockEntity> blocks = blockRepository.findById_BlockerId(userId);
        Set<String> blockedIds =
                blocks.stream().map(e -> e.getId().getBlockedId()).collect(Collectors.toSet());
        if (!blockedIds.isEmpty()) {
            for (String blockedId : blockedIds) {
                redisTemplate.opsForSet().add(cacheKey, blockedId);
            }
            redisTemplate.expire(cacheKey, Duration.ofHours(24));
        }
        return blockedIds;
    }

    /**
     * 解除拉黑关系
     *
     * @param blockerId 发起拉黑的用户 ID
     * @param blockedId 被拉黑的用户 ID
     */
    @Transactional
    public void unblockUser(String blockerId, String blockedId) {
        UserBlockId id = new UserBlockId(blockerId, blockedId);
        if (blockRepository.existsById(id)) {
            blockRepository.deleteById(id);

            // 清除 Redis 缓存
            String cacheKey = BLOCK_PREFIX + blockerId;
            redisTemplate.opsForSet().remove(cacheKey, blockedId);

            log.info("User unblocked: {} -> {}", blockerId, blockedId);
        }
    }
}
