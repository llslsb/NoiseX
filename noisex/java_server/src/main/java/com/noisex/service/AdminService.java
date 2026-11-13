package com.noisex.service;

import com.noisex.exception.NotFoundException;
import com.noisex.model.dto.ReportAdminResponse;
import com.noisex.model.dto.SystemStatsResponse;
import com.noisex.model.entity.ReportEntity;
import com.noisex.model.repository.ReportRepository;
import com.noisex.util.RedisKeys;
import com.noisex.websocket.NoiseXWebSocketHandler;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class AdminService {

    /** 封禁标记与 JWT 黑名单共用 7 天 TTL：覆盖最长 JWT 有效期，到期自动解封 */
    private static final Duration BAN_TTL = Duration.ofDays(7);

    private final ReportRepository reportRepository;
    private final ReportService reportService;
    private final RedisTemplate<String, Object> redisTemplate;
    private final StringRedisTemplate stringRedisTemplate;
    private final MeterRegistry meterRegistry;
    private final CompensationService compensationService;
    private final NoiseXWebSocketHandler webSocketHandler;

    public AdminService(
            ReportRepository reportRepository,
            ReportService reportService,
            RedisTemplate<String, Object> redisTemplate,
            StringRedisTemplate stringRedisTemplate,
            MeterRegistry meterRegistry,
            @Lazy CompensationService compensationService,
            @Lazy NoiseXWebSocketHandler webSocketHandler) {
        this.reportRepository = reportRepository;
        this.reportService = reportService;
        this.redisTemplate = redisTemplate;
        this.stringRedisTemplate = stringRedisTemplate;
        this.meterRegistry = meterRegistry;
        this.compensationService = compensationService;
        this.webSocketHandler = webSocketHandler;
    }

    private static final String ONLINE_KEY = RedisKeys.ONLINE;
    private static final String USER_ROOMS_PREFIX = RedisKeys.USER_ROOMS_PREFIX;

    public List<ReportAdminResponse> getReports(String status) {
        ReportEntity.ReportStatus reportStatus;
        try {
            reportStatus =
                    (status != null)
                            ? ReportEntity.ReportStatus.valueOf(status)
                            : ReportEntity.ReportStatus.pending;
        } catch (IllegalArgumentException e) {
            reportStatus = ReportEntity.ReportStatus.pending;
        }

        List<ReportEntity> reports = reportRepository.findByStatus(reportStatus);
        List<ReportAdminResponse> result = new ArrayList<>();
        for (ReportEntity report : reports) {
            String phone = null;
            if (report.getPhoneNumber() != null) {
                phone = reportService.decryptPhoneNumber(report.getPhoneNumber());
            }
            result.add(
                    new ReportAdminResponse(
                            report.getId(),
                            report.getReporterId(),
                            report.getRoomId(),
                            report.getReason(),
                            phone,
                            report.getStatus().name(),
                            report.getCreatedAt(),
                            report.getReviewedAt()));
        }
        return result;
    }

    public void reviewReport(String reportId, String action) {
        ReportEntity report =
                reportRepository
                        .findById(reportId)
                        .orElseThrow(() -> new NotFoundException("举报不存在: " + reportId));

        ReportEntity.ReportStatus newStatus;
        try {
            newStatus = ReportEntity.ReportStatus.valueOf(action);
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("无效的审核操作: " + action);
        }

        report.setStatus(newStatus);
        report.setReviewedAt(System.currentTimeMillis());
        reportRepository.save(report);

        if (newStatus == ReportEntity.ReportStatus.banned) {
            banRoom(report.getRoomId(), reportId);
        }

        log.info("Report reviewed: id={}, action={}", reportId, action);
    }

    /**
     * 封禁：关闭房间并清理其全部 Redis 数据，拉黑双方当前 JWT 并写入封禁标记，踢掉活跃 WS 会话。
     *
     * <p>必须先读成员列表再删 key（删后再读恒为 null，拉黑不可达）；读用的 template 必须与写入方一致 （ROOM_USERS 由 StringRedisTemplate
     * 写入）。成员列表随补偿单落库，重试时仍能补齐封禁。
     */
    private void banRoom(String roomId, String reportId) {
        List<String> userIds = readRoomUsers(roomId);
        compensationService.recordCompensation(
                "review_report_redis", Map.of("roomId", roomId, "userIds", userIds));

        try {
            cleanupRoomData(roomId, userIds);
            for (String userId : userIds) {
                banUser(userId);
                webSocketHandler.kickUser(userId, "banned");
            }
        } catch (Exception e) {
            log.warn("Redis cleanup failed for banned room, compensation will retry", e);
        }

        log.info(
                "Room banned and closed: roomId={}, reportId={}, bannedUsers={}",
                roomId,
                reportId,
                userIds.size());
    }

    /** 读取房间成员（读失败不阻断封禁主流程，返回空列表走补偿兜底） */
    private List<String> readRoomUsers(String roomId) {
        List<String> userIds = new ArrayList<>();
        try {
            String usersValue =
                    stringRedisTemplate.opsForValue().get(RedisKeys.ROOM_USERS_PREFIX + roomId);
            if (usersValue != null) {
                for (String userId : usersValue.split(",")) {
                    if (!userId.isBlank()) {
                        userIds.add(userId.trim());
                    }
                }
            }
        } catch (Exception e) {
            log.warn("Failed to read room users before ban: roomId={}", roomId, e);
        }
        return userIds;
    }

    /** 删除房间的全部 Redis 数据，并把 roomId 从双方"我的房间"集合移除（对齐 HourglassService 清理范式） */
    private void cleanupRoomData(String roomId, List<String> userIds) {
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
    }

    /**
     * 拉黑该匿名身份：缓存中的当前 JWT 加入黑名单（立即失效），并写 {@code noisex:user:banned:<uid>} 封禁标记——同一 UUID 重新注册拿到新
     * token 也会被过滤器拒绝，封禁期内无法再获得可用会话。 幂等，供封禁首审与补偿重试（CompensationService）共用。
     */
    public void banUser(String userId) {
        Object cachedToken =
                redisTemplate.opsForValue().get(RedisKeys.AUTH_UUID_CACHE_PREFIX + userId);
        if (cachedToken != null && !cachedToken.toString().isBlank()) {
            blacklistToken(cachedToken.toString());
        }
        stringRedisTemplate.opsForValue().set(RedisKeys.USER_BANNED_PREFIX + userId, "1", BAN_TTL);
        log.info("User banned: userId={}, currentTokenBlacklisted={}", userId, cachedToken != null);
    }

    public void blacklistToken(String token) {
        stringRedisTemplate.opsForSet().add(RedisKeys.JWT_BLACKLIST, token);
        stringRedisTemplate.expire(RedisKeys.JWT_BLACKLIST, BAN_TTL);
    }

    public SystemStatsResponse getSystemStats() {
        Set<Object> onlineUsers = redisTemplate.opsForSet().members(ONLINE_KEY);
        long onlineCount = onlineUsers != null ? onlineUsers.size() : 0;

        long pendingReports = reportRepository.countByStatus(ReportEntity.ReportStatus.pending);

        long activeRooms = 0;
        java.util.Set<String> roomKeys =
                redisTemplate.execute(
                        (org.springframework.data.redis.core.RedisCallback<java.util.Set<String>>)
                                connection -> {
                                    java.util.Set<String> result = new java.util.HashSet<>();
                                    try (org.springframework.data.redis.core.Cursor<byte[]> cursor =
                                            connection
                                                    .keyCommands()
                                                    .scan(
                                                            org.springframework.data.redis.core
                                                                    .ScanOptions.scanOptions()
                                                                    .match(
                                                                            RedisKeys.ROOM_PREFIX
                                                                                    + "*")
                                                                    .count(100)
                                                                    .build())) {
                                        while (cursor.hasNext()) {
                                            result.add(new String(cursor.next()));
                                        }
                                    }
                                    return result;
                                });
        if (roomKeys != null) {
            activeRooms = roomKeys.size();
        }

        double sonarSentTotal = getCounterValue("noisex.sonar.sent.total");
        double sonarAcceptedTotal = getCounterValue("noisex.sonar.accepted.total");
        double roomCreatedTotal = getCounterValue("noisex.room.created.total");
        double messageSentTotal = getCounterValue("noisex.chat.message.sent.total");

        return new SystemStatsResponse(
                onlineCount,
                pendingReports,
                activeRooms,
                sonarSentTotal,
                sonarAcceptedTotal,
                roomCreatedTotal,
                messageSentTotal);
    }

    private double getCounterValue(String name) {
        Counter counter = meterRegistry.find(name).counter();
        return counter != null ? counter.count() : 0;
    }
}
