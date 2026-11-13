package com.noisex.service;

import com.noisex.model.dto.AuthResponse;
import com.noisex.model.repository.ReportRepository;
import com.noisex.model.repository.SavedConnectionRepository;
import com.noisex.model.repository.SavedMomentRepository;
import com.noisex.model.repository.UserBlockRepository;
import com.noisex.model.repository.UserProfileRepository;
import com.noisex.security.JwtTokenProvider;
import com.noisex.util.RedisKeys;
import com.noisex.websocket.NoiseXWebSocketHandler;
import java.time.Duration;
import java.util.Map;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class AuthService {

    private final JwtTokenProvider jwtTokenProvider;
    private final RedisTemplate<String, Object> redisTemplate;
    private final StringRedisTemplate stringRedisTemplate;
    @Lazy private final NoiseXWebSocketHandler webSocketHandler;
    @Lazy private final PushService pushService;
    private final UserProfileRepository userProfileRepository;
    private final SavedConnectionRepository savedConnectionRepository;
    private final UserBlockRepository userBlockRepository;
    private final ReportRepository reportRepository;
    private final SavedMomentRepository savedMomentRepository;

    private static final String UUID_CACHE_PREFIX = RedisKeys.AUTH_UUID_CACHE_PREFIX;

    public AuthResponse generateToken(String anonymousUuid) {
        String cacheKey = UUID_CACHE_PREFIX + anonymousUuid;
        Object cachedToken = redisTemplate.opsForValue().get(cacheKey);
        if (cachedToken != null) {
            try {
                jwtTokenProvider.validateTokenAndGetUuid(cachedToken.toString());
                log.debug(
                        "UUID already registered, returning valid cached token: {}", anonymousUuid);
                return new AuthResponse(cachedToken.toString(), jwtTokenProvider.getExpiration());
            } catch (Exception e) {
                log.debug("Cached token expired for UUID {}, generating new token", anonymousUuid);
            }
        }

        String token = jwtTokenProvider.generateToken(anonymousUuid);
        redisTemplate.opsForValue().set(cacheKey, token, Duration.ofDays(30));
        long expiresIn = jwtTokenProvider.getExpiration();
        return new AuthResponse(token, expiresIn);
    }

    public AuthResponse refreshToken(String userId) {
        String token = jwtTokenProvider.generateToken(userId);
        long expiresIn = jwtTokenProvider.getExpiration();
        return new AuthResponse(token, expiresIn);
    }

    /** Reset anonymous identity: clear all server-side data for the user. */
    @Transactional
    public void resetIdentity(String userId) {
        log.info("Identity reset requested for user: {}", userId);

        // 1. Clean up active rooms and notify the other party
        cleanupActiveRooms(userId);

        // 2. Delete user-level Redis keys
        deleteUserRedisKeys(userId);

        // 3. Delete MySQL data
        deleteUserData(userId);

        log.info("Identity reset completed for user: {}", userId);
    }

    private void cleanupActiveRooms(String userId) {
        Set<Object> roomIds =
                redisTemplate.opsForSet().members(RedisKeys.USER_ROOMS_PREFIX + userId);
        if (roomIds == null || roomIds.isEmpty()) {
            return;
        }

        for (Object roomIdObj : roomIds) {
            String roomId = roomIdObj.toString();

            // Read room users before deleting (must read first, same pattern as HourglassService)
            String roomUsersKey = RedisKeys.ROOM_USERS_PREFIX + roomId;
            String usersValue = stringRedisTemplate.opsForValue().get(roomUsersKey);

            // Notify the other party via WebSocket
            if (usersValue != null) {
                String[] userIds = usersValue.split(",");
                for (String uid : userIds) {
                    if (!uid.isEmpty() && !uid.equals(userId)) {
                        webSocketHandler.notifyRoomExpired(uid, roomId);
                        pushService.sendPush(
                                uid,
                                "对话已关闭",
                                "对方已离开",
                                Map.of("roomId", roomId, "type", "room_expired"));
                    }
                }
            }

            // Clean room Redis data
            redisTemplate.delete(RedisKeys.ROOM_PREFIX + roomId);
            redisTemplate.delete(RedisKeys.ROOM_MESSAGES_PREFIX + roomId);
            redisTemplate.delete(RedisKeys.ROOM_DEEP_PREFIX + roomId);
            redisTemplate.delete(RedisKeys.ROOM_SAVE_PREFIX + roomId);
            redisTemplate.delete(RedisKeys.ROOM_READ_PREFIX + roomId);
            redisTemplate.delete(RedisKeys.ROOM_USERS_PREFIX + roomId);
            redisTemplate.opsForZSet().remove(RedisKeys.ROOM_CREATED_AT_ZSET, roomId);

            // Remove roomId from both users' room sets
            if (usersValue != null) {
                String[] userIds = usersValue.split(",");
                for (String uid : userIds) {
                    if (!uid.isEmpty()) {
                        redisTemplate.opsForSet().remove(RedisKeys.USER_ROOMS_PREFIX + uid, roomId);
                    }
                }
            }

            log.info("Room cleaned up during identity reset: {}", roomId);
        }
    }

    private void deleteUserRedisKeys(String userId) {
        // 清理 geohash 收听者集合中的旧 userId（先读取再删除）
        Set<Object> listeningGeohashes =
                redisTemplate
                        .opsForSet()
                        .members(RedisKeys.USER_LISTENING_GEOHASHES_PREFIX + userId);
        if (listeningGeohashes != null) {
            for (Object geohashObj : listeningGeohashes) {
                redisTemplate
                        .opsForSet()
                        .remove(RedisKeys.LISTENER_PREFIX + geohashObj.toString(), userId);
            }
        }

        redisTemplate.delete(UUID_CACHE_PREFIX + userId);
        redisTemplate.delete(RedisKeys.PUSH_TOKEN_PREFIX + userId);
        redisTemplate.delete(RedisKeys.BLOCK_PREFIX + userId);
        redisTemplate.delete(RedisKeys.USER_ROOMS_PREFIX + userId);
        redisTemplate.delete(RedisKeys.USER_LISTENING_GEOHASHES_PREFIX + userId);
        redisTemplate.delete(RedisKeys.SONAR_RECEIVED_PREFIX + userId);
        redisTemplate.delete(RedisKeys.SONAR_DUPLICATE_PREFIX + userId);
        redisTemplate.delete(RedisKeys.RATE_LIMIT_PREFIX + userId);
        redisTemplate.delete(RedisKeys.MSG_RATE_PREFIX + userId);
        redisTemplate.opsForSet().remove(RedisKeys.ONLINE, userId);
    }

    private void deleteUserData(String userId) {
        userProfileRepository.deleteById(userId);
        savedConnectionRepository.deleteByUserId(userId);
        userBlockRepository.deleteByUserId(userId);
        reportRepository.deleteByReporterId(userId);
        // 保存的片段是明文，重置身份必须一并删除（2026-11-06 补漏，与隐私政策承诺对齐，勿删）
        savedMomentRepository.deleteByUserId(userId);
    }
}
