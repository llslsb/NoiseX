package com.noisex.service;

import com.noisex.exception.BusinessException;
import com.noisex.exception.ErrorCode;
import com.noisex.exception.NotFoundException;
import com.noisex.model.domain.ChatRoomData;
import com.noisex.model.domain.SonarData;
import com.noisex.model.dto.*;
import com.noisex.util.IdGenerator;
import com.noisex.util.RedisKeys;
import com.noisex.websocket.NoiseXWebSocketHandler;
import io.micrometer.core.instrument.Counter;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.ThreadLocalRandom;
import java.util.stream.Collectors;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.domain.Range;
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.data.redis.connection.stream.RecordId;
import org.springframework.data.redis.core.RedisCallback;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class ChatService {

    private final RedisTemplate<String, Object> redisTemplate;
    private final StringRedisTemplate stringRedisTemplate;
    private final NoiseXWebSocketHandler webSocketHandler;
    private final ProfileService profileService;
    private final com.noisex.service.PushService pushService;
    private final CompensationService compensationService;
    private final BlockService blockService;
    private final Counter roomCreatedCounter;
    private final Counter messageSentCounter;

    public ChatService(
            RedisTemplate<String, Object> redisTemplate,
            StringRedisTemplate stringRedisTemplate,
            NoiseXWebSocketHandler webSocketHandler,
            ProfileService profileService,
            com.noisex.service.PushService pushService,
            @Lazy CompensationService compensationService,
            BlockService blockService,
            Counter roomCreatedCounter,
            Counter messageSentCounter) {
        this.redisTemplate = redisTemplate;
        this.stringRedisTemplate = stringRedisTemplate;
        this.webSocketHandler = webSocketHandler;
        this.profileService = profileService;
        this.pushService = pushService;
        this.compensationService = compensationService;
        this.blockService = blockService;
        this.roomCreatedCounter = roomCreatedCounter;
        this.messageSentCounter = messageSentCounter;
    }

    private static final String ROOM_PREFIX = RedisKeys.ROOM_PREFIX;
    private static final String MESSAGES_PREFIX = RedisKeys.ROOM_MESSAGES_PREFIX;
    private static final String USER_ROOMS_PREFIX = RedisKeys.USER_ROOMS_PREFIX;
    private static final String DEEP_CONFIRM_PREFIX = RedisKeys.ROOM_DEEP_PREFIX;
    private static final String SAVE_PREFIX = RedisKeys.ROOM_SAVE_PREFIX;
    private static final String READ_PREFIX = RedisKeys.ROOM_READ_PREFIX;
    private static final String MSG_RATE_PREFIX = RedisKeys.MSG_RATE_PREFIX;
    private static final String MSG_LAST_PREFIX = RedisKeys.MSG_LAST_PREFIX;
    private static final String ROOM_USERS_PREFIX = RedisKeys.ROOM_USERS_PREFIX;
    private static final String MSG_COUNT_PREFIX = "noisex:room:msgcount:";
    private static final String ROOM_CREATED_AT_ZSET = RedisKeys.ROOM_CREATED_AT_ZSET;

    private static final DefaultRedisScript<Long> MSG_RATE_LIMIT_SCRIPT =
            new DefaultRedisScript<>(
                    "local count = redis.call('INCR', KEYS[1]) "
                            + "if count == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end "
                            + "return count",
                    Long.class);

    private static final DefaultRedisScript<Long> MSG_DUPLICATE_SCRIPT =
            new DefaultRedisScript<>(
                    "local last = redis.call('GET', KEYS[1]) "
                            + "if last == ARGV[1] then return 1 end "
                            + "redis.call('SET', KEYS[1], ARGV[1]) "
                            + "redis.call('EXPIRE', KEYS[1], ARGV[2]) "
                            + "return 0",
                    Long.class);

    @Value("${noisex.room.lifetime-hours}")
    private int roomLifetimeHours;

    @Value("${noisex.room.unlock-window-hours}")
    private int unlockWindowHours;

    @Value("${noisex.room.unlock-threshold-messages}")
    private int unlockThresholdMessages;

    @Value("${noisex.room.unlock-min-message-length}")
    private int unlockMinMessageLength;

    @Value("${noisex.chat.max-message-length}")
    private int maxMessageLength;

    @Value("${noisex.chat.msg-rate-seconds}")
    private int msgRateSeconds;

    @Value("${noisex.chat.duplicate-window-seconds}")
    private int duplicateWindowSeconds;

    /** 创建对话房间 */
    public ChatRoomData createRoom(SonarData sonar, String listenerId) {
        // 防止自匹配：声呐发送者和接受者不能是同一人
        if (sonar.getUserId().equals(listenerId)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "不能与自己创建对话房间");
        }

        String roomId = IdGenerator.roomId();
        String signalCode = "RX-" + (1000 + ThreadLocalRandom.current().nextInt(9000));

        ChatRoomData room =
                ChatRoomData.builder()
                        .id(roomId)
                        .sonarContent(sonar.getContent())
                        .signalCode(signalCode)
                        .userIdA(sonar.getUserId())
                        .userIdB(listenerId)
                        .createdAt(System.currentTimeMillis())
                        .expiresAt(System.currentTimeMillis() + roomLifetimeHours * 3600L * 1000L)
                        .unlocked(false)
                        .deepConnectionAchieved(false)
                        .build();

        String roomKey = ROOM_PREFIX + roomId;
        Map<String, String> roomMap = new HashMap<>();
        roomMap.put("id", room.getId());
        roomMap.put("sonarContent", room.getSonarContent());
        roomMap.put("signalCode", room.getSignalCode());
        roomMap.put("userIdA", room.getUserIdA());
        roomMap.put("userIdB", room.getUserIdB());
        roomMap.put("createdAt", String.valueOf(room.getCreatedAt()));
        roomMap.put("expiresAt", String.valueOf(room.getExpiresAt()));
        roomMap.put("unlocked", "false");
        roomMap.put("deepConnectionAchieved", "false");
        redisTemplate.opsForHash().putAll(roomKey, roomMap);
        redisTemplate.expire(roomKey, Duration.ofHours(roomLifetimeHours));

        String roomUsersKey = ROOM_USERS_PREFIX + roomId;
        stringRedisTemplate
                .opsForValue()
                .set(
                        roomUsersKey,
                        sonar.getUserId() + "," + listenerId,
                        Duration.ofHours(roomLifetimeHours));

        redisTemplate.opsForSet().add(USER_ROOMS_PREFIX + sonar.getUserId(), roomId);
        redisTemplate.expire(USER_ROOMS_PREFIX + sonar.getUserId(), Duration.ofDays(7));
        redisTemplate.opsForSet().add(USER_ROOMS_PREFIX + listenerId, roomId);
        redisTemplate.expire(USER_ROOMS_PREFIX + listenerId, Duration.ofDays(7));

        redisTemplate.opsForZSet().add(ROOM_CREATED_AT_ZSET, roomId, room.getCreatedAt());

        log.info("Room created: id={}, A={}, B={}", roomId, sonar.getUserId(), listenerId);
        roomCreatedCounter.increment();
        return room;
    }

    /** 发送消息 */
    public String sendMessage(String roomId, String senderId, String content) {
        ChatRoomData room = getRoomData(roomId);
        if (room == null) {
            throw new NotFoundException("房间不存在: " + roomId);
        }
        if (!room.getUserIdA().equals(senderId) && !room.getUserIdB().equals(senderId)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "你不属于该房间");
        }

        // 反作弊: 内容长度限制
        if (content.length() > maxMessageLength) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "消息过长，最多" + maxMessageLength + "字");
        }

        // XSS 防护: 转义 HTML 特殊字符
        content = content.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");

        String rateKey = MSG_RATE_PREFIX + senderId;
        Long rateCount =
                stringRedisTemplate.execute(
                        MSG_RATE_LIMIT_SCRIPT,
                        Collections.singletonList(rateKey),
                        String.valueOf(msgRateSeconds));
        if (rateCount != null && rateCount > 1) {
            throw new BusinessException(ErrorCode.RATE_LIMIT, "发送过快，请稍后再试");
        }

        String lastKey = MSG_LAST_PREFIX + roomId + ":" + senderId;
        Long isDuplicate =
                stringRedisTemplate.execute(
                        MSG_DUPLICATE_SCRIPT,
                        Collections.singletonList(lastKey),
                        content,
                        String.valueOf(duplicateWindowSeconds));
        if (isDuplicate != null && isDuplicate == 1) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "请勿发送重复内容");
        }

        // 深度交流未达成时，禁止连续发送超过5条消息（防骚扰）
        // 检查发生在写入前，取最近maxConsecutive条，若全是同一sender则拒绝第(maxConsecutive+1)条
        int maxConsecutiveMessages = 5;
        if (!room.isDeepConnectionAchieved()) {
            String streamKey0 = MESSAGES_PREFIX + roomId;
            org.springframework.data.redis.connection.Limit recentLimit =
                    org.springframework.data.redis.connection.Limit.unlimited();
            recentLimit.count(maxConsecutiveMessages);
            List<?> recentMessages =
                    redisTemplate
                            .opsForStream()
                            .reverseRange(streamKey0, Range.unbounded(), recentLimit);
            log.info(
                    "Consecutive check: roomId={}, senderId={}, recentSize={}",
                    roomId,
                    senderId,
                    recentMessages != null ? recentMessages.size() : -1);
            if (recentMessages != null && recentMessages.size() >= maxConsecutiveMessages) {
                boolean allSameSender = true;
                for (Object raw : recentMessages) {
                    @SuppressWarnings("unchecked")
                    MapRecord<String, Object, Object> rec = (MapRecord<String, Object, Object>) raw;
                    Object s = rec.getValue().get("sender");
                    if (s == null || !s.toString().equals(senderId)) {
                        allSameSender = false;
                        break;
                    }
                }
                log.info("Consecutive check: allSameSender={}", allSameSender);
                if (allSameSender) {
                    throw new BusinessException(ErrorCode.RATE_LIMIT, "请等待对方回复后再继续发送");
                }
            }
        }

        String streamKey = MESSAGES_PREFIX + roomId;
        Map<String, String> messageMap = new HashMap<>();
        messageMap.put("sender", senderId);
        messageMap.put("content", content);
        messageMap.put("timestamp", String.valueOf(System.currentTimeMillis()));
        RecordId messageId = redisTemplate.opsForStream().add(streamKey, messageMap);
        if (messageId == null) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "消息存储失败");
        }
        redisTemplate.expire(streamKey, Duration.ofHours(roomLifetimeHours));

        // 增量更新消息计数 Hash（用于 checkDeepConnection 增量判断）
        String countKey = MSG_COUNT_PREFIX + roomId;
        redisTemplate.opsForHash().increment(countKey, senderId, 1);
        redisTemplate.expire(countKey, Duration.ofHours(roomLifetimeHours));

        checkDeepConnection(roomId, room);

        // 离线推送
        String receiverId = getOtherUserId(room, senderId);
        // 推送脱敏（勿回退，2026-11-05 用户抓到通知栏显示密文）：NoiseX 是端到端加密，
        // 服务端存的 content 就是密文，原样进通知栏等于把乱码推给用户，更违反
        // CLAUDE.md"聊天消息推送应脱敏"红线——通知只提示有消息，内容点开看
        pushService.sendPush(
                receiverId, "新消息", "收到一条新消息，点击查看", Map.of("roomId", roomId, "type", "message"));
        messageSentCounter.increment();
        return messageId.getValue();
    }

    /** 获取用户的活跃房间列表 */
    public List<RoomResponse> getRooms(String userId) {
        String key = USER_ROOMS_PREFIX + userId;
        Set<Object> roomIds = redisTemplate.opsForSet().members(key);
        if (roomIds == null || roomIds.isEmpty()) {
            return Collections.emptyList();
        }

        // D-M9-1 根治（2026-11-05）：我拉黑了对方 → 相关房间从我的列表消失。
        // 客户端会话级兜底（重启即丢、盖不住拉黑后对方新开的房间）不可靠，
        // 列表必须服务端权威过滤；blocker=当前用户口径与
        // POST /api/rooms/{roomId}/block（房间维度拉黑=拉黑对方）一致。
        // 取一次全量拉黑名单再内存过滤，避免逐房间打 Redis/MySQL；
        // 解除拉黑（unblockUser 会清缓存）后房间自动恢复可见。
        Set<String> blockedIds = blockService.getBlockedList(userId);

        List<String> roomIdStrs =
                roomIds.stream().map(Object::toString).collect(Collectors.toList());
        List<Object> pipelineResults =
                redisTemplate.executePipelined(
                        (RedisCallback<Object>)
                                connection -> {
                                    for (String roomId : roomIdStrs) {
                                        byte[] roomKeyBytes =
                                                stringRedisTemplate
                                                        .getStringSerializer()
                                                        .serialize(ROOM_PREFIX + roomId);
                                        connection.hashCommands().hGetAll(roomKeyBytes);
                                    }
                                    return null;
                                });

        List<RoomResponse> result = new ArrayList<>();
        for (int i = 0; i < pipelineResults.size(); i++) {
            Object raw = pipelineResults.get(i);
            if (raw instanceof Map) {
                @SuppressWarnings("unchecked")
                Map<Object, Object> rawMap = (Map<Object, Object>) raw;
                if (!rawMap.isEmpty()) {
                    ChatRoomData room = buildRoomDataFromMap(rawMap);
                    if (room != null) {
                        String otherUserId = getOtherUserId(room, userId);
                        if (otherUserId != null && blockedIds.contains(otherUserId)) {
                            continue;
                        }
                        result.add(toRoomResponse(room, userId));
                    }
                }
            }
        }
        // 按最新消息时间降序排序（最新消息的房间排在最前）
        result.sort(
                (a, b) -> {
                    long timeA =
                            a.getLastMessage() != null ? a.getLastMessage().getTimestamp() : 0L;
                    long timeB =
                            b.getLastMessage() != null ? b.getLastMessage().getTimestamp() : 0L;
                    return Long.compare(timeB, timeA);
                });
        return result;
    }

    /** 获取房间详情 */
    public RoomResponse getRoom(String roomId, String userId) {
        ChatRoomData room = getRoomData(roomId);
        if (room == null) {
            throw new NotFoundException("房间不存在: " + roomId);
        }
        if (!room.getUserIdA().equals(userId) && !room.getUserIdB().equals(userId)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "你不属于该房间");
        }
        return toRoomResponse(room, userId);
    }

    /** 获取房间消息历史 */
    public MessagesResponse getMessages(String roomId, String userId, long offset, int limit) {
        ChatRoomData room = getRoomData(roomId);
        if (room == null) {
            throw new NotFoundException("房间不存在: " + roomId);
        }
        if (!room.getUserIdA().equals(userId) && !room.getUserIdB().equals(userId)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "你不属于该房间");
        }

        String streamKey = MESSAGES_PREFIX + roomId;
        List<MapRecord<String, Object, Object>> messages = readStreamMessages(streamKey);

        List<MessageResponse> result = new ArrayList<>();
        if (messages != null) {
            int start = (int) Math.min(offset, messages.size());
            int end = (int) Math.min(offset + limit, messages.size());
            for (int i = start; i < end; i++) {
                MapRecord<String, Object, Object> msg = messages.get(i);
                Map<Object, Object> body = msg.getValue();
                String sender = getStrFromBody(body, "sender");
                result.add(
                        new MessageResponse(
                                msg.getId().getValue(),
                                sender.equals(userId) ? "me" : "other",
                                getStrFromBody(body, "content"),
                                getLongFromBody(body, "timestamp")));
            }
        }

        boolean hasMore = messages != null && messages.size() > offset + limit;
        return new MessagesResponse(result, hasMore);
    }

    /** 解锁资料 — 双方都确认深度交流 */
    public UnlockResponse unlockProfile(String roomId, String userId) {
        ChatRoomData room = getRoomData(roomId);
        if (room == null) {
            throw new NotFoundException("房间不存在: " + roomId);
        }
        if (!room.isDeepConnectionAchieved()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "尚未达到深度交流条件");
        }

        String confirmKey = DEEP_CONFIRM_PREFIX + roomId;
        stringRedisTemplate.opsForSet().add(confirmKey, userId);
        stringRedisTemplate.expire(confirmKey, Duration.ofHours(roomLifetimeHours));

        Long confirmedCount = stringRedisTemplate.opsForSet().size(confirmKey);
        if (confirmedCount != null && confirmedCount >= 2) {
            redisTemplate.opsForHash().put(ROOM_PREFIX + roomId, "unlocked", "true");

            String otherUserId = getOtherUserId(room, userId);
            ProfileResponse profile = profileService.getProfile(otherUserId);
            return new UnlockResponse(true, profile);
        }

        return new UnlockResponse(false, null);
    }

    /** 保存连接 */
    public SaveConnectionResponse saveConnection(String roomId, String userId) {
        ChatRoomData room = getRoomData(roomId);
        if (room == null) {
            throw new NotFoundException("房间不存在: " + roomId);
        }
        if (!room.isUnlocked()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "资料尚未解锁");
        }

        String saveKey = SAVE_PREFIX + roomId;
        String otherUserId = getOtherUserId(room, userId);

        // 检查当前用户是否已同意过，防止重复操作和弹窗循环
        Boolean alreadySaved = stringRedisTemplate.opsForSet().isMember(saveKey, userId);
        if (Boolean.TRUE.equals(alreadySaved)) {
            // 已同意过，直接返回当前状态
            Set<Object> agreed = redisTemplate.opsForSet().members(saveKey);
            if (agreed != null && agreed.size() >= 2) {
                // D4（2026-11-03 双端实测）：重复同意且双方已齐时补发
                // save_confirmed，让错过的端（如被弹窗打断/重连丢帧）立即
                // 对齐"双方已保存"状态，不必等下次列表刷新自愈
                webSocketHandler.notifySaveConfirmed(userId, roomId);
                webSocketHandler.notifySaveConfirmed(otherUserId, roomId);
                return new SaveConnectionResponse("confirmed", "双方已确认保存连接");
            }
            return new SaveConnectionResponse("waiting", "等待对方确认");
        }

        // 首次同意：加入保存集合
        redisTemplate.opsForSet().add(saveKey, userId);
        redisTemplate.expire(saveKey, Duration.ofHours(roomLifetimeHours));

        // 检查对方是否已同意
        Boolean otherAlreadySaved = stringRedisTemplate.opsForSet().isMember(saveKey, otherUserId);

        // 仅当对方还未同意时，才向对方发送保存连接请求
        if (!Boolean.TRUE.equals(otherAlreadySaved)) {
            webSocketHandler.notifySaveRequest(otherUserId, roomId, room.getSignalCode());
            // 离线推送：保存连接请求
            pushService.sendPush(
                    otherUserId,
                    "保存请求",
                    "对方希望保存这段连接",
                    Map.of("roomId", roomId, "type", "save_request"));
        }

        Set<Object> agreed = redisTemplate.opsForSet().members(saveKey);
        if (agreed != null && agreed.size() >= 2) {
            try {
                profileService.saveConnection(roomId, room.getUserIdA(), room.getUserIdB());
            } catch (Exception e) {
                log.error("MySQL saveConnection failed, recording compensation", e);
                compensationService.recordCompensation(
                        "save_connection_redis",
                        Map.of(
                                "roomId",
                                roomId,
                                "userIdA",
                                room.getUserIdA(),
                                "userIdB",
                                room.getUserIdB()));
            }
            // 通知双方连接已保存成功
            webSocketHandler.notifySaveConfirmed(room.getUserIdA(), roomId);
            webSocketHandler.notifySaveConfirmed(room.getUserIdB(), roomId);
            // 离线推送：连接已保存
            pushService.sendPush(
                    room.getUserIdA(),
                    "连接已保存",
                    "双方确认保存连接",
                    Map.of("roomId", roomId, "type", "save_confirmed"));
            pushService.sendPush(
                    room.getUserIdB(),
                    "连接已保存",
                    "双方确认保存连接",
                    Map.of("roomId", roomId, "type", "save_confirmed"));
            return new SaveConnectionResponse("confirmed", "双方已确认保存连接");
        }

        return new SaveConnectionResponse("waiting", "等待对方确认");
    }

    /** 标记消息已读 */
    public String markAsRead(String roomId, String userId, String messageId) {
        ChatRoomData room = getRoomData(roomId);
        if (room == null) {
            throw new NotFoundException("房间不存在: " + roomId);
        }
        String readKey = READ_PREFIX + roomId;
        redisTemplate.opsForHash().put(readKey, userId, messageId);
        redisTemplate.expire(readKey, Duration.ofHours(roomLifetimeHours));
        return messageId;
    }

    /** 获取用户在房间中的已读指针 */
    public String getReadPointer(String roomId, String userId) {
        String readKey = READ_PREFIX + roomId;
        Object val = redisTemplate.opsForHash().get(readKey, userId);
        return val != null ? val.toString() : null;
    }

    /**
     * 离开房间。
     *
     * <p>F2-2：用户主动 leaveRoom 时，向对方推送 peer_left 事件（带 signalCode）而非 room_expired。room_expired 仅保留给
     * TTL 自然到期场景（HourglassService），peer_left 携带 signalCode 让对方 UI 显示 "对方已离开"，不泄漏 userId。
     *
     * <p>对应计划 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F2-2。
     */
    public void leaveRoom(String roomId, String userId) {
        ChatRoomData room = getRoomData(roomId);
        if (room == null) {
            throw new NotFoundException("房间不存在: " + roomId);
        }

        String otherUserId = getOtherUserId(room, userId);
        webSocketHandler.notifyPeerLeft(otherUserId, roomId, room.getSignalCode());
        cleanupRoom(roomId, room);
        log.info("Room left: roomId={}, userId={}", roomId, userId);
    }

    /** 获取对方 userId */
    public String getOtherUserId(String roomId, String userId) {
        ChatRoomData room = getRoomData(roomId);
        if (room == null) return null;
        return getOtherUserId(room, userId);
    }

    /** 获取房间的 signalCode（用于 WebSocket 消息中保护匿名性） */
    public String getRoomSignalCode(String roomId) {
        ChatRoomData room = getRoomData(roomId);
        return room != null ? room.getSignalCode() : null;
    }

    // ========== 内部方法 ==========

    @SuppressWarnings({"unchecked"})
    private List<MapRecord<String, Object, Object>> readStreamMessages(String streamKey) {
        try {
            List<?> rawMessages = redisTemplate.opsForStream().range(streamKey, Range.unbounded());
            if (rawMessages == null) return Collections.emptyList();

            List<MapRecord<String, Object, Object>> result = new ArrayList<>();
            for (Object record : rawMessages) {
                result.add((MapRecord<String, Object, Object>) record);
            }
            return result;
        } catch (Exception e) {
            log.warn("Failed to read stream messages: {}", e.getMessage());
            return Collections.emptyList();
        }
    }

    private String getStrFromBody(Map<Object, Object> body, String key) {
        Object val = body.get(key);
        return val != null ? val.toString() : "";
    }

    private long getLongFromBody(Map<Object, Object> body, String key) {
        Object val = body.get(key);
        if (val == null) return 0L;
        return Long.parseLong(val.toString());
    }

    ChatRoomData getRoomData(String roomId) {
        String roomKey = ROOM_PREFIX + roomId;
        Map<Object, Object> raw = redisTemplate.opsForHash().entries(roomKey);
        if (raw.isEmpty()) return null;
        return buildRoomDataFromMap(raw);
    }

    private ChatRoomData buildRoomDataFromMap(Map<Object, Object> raw) {
        if (raw.isEmpty()) return null;
        return ChatRoomData.builder()
                .id(getStrFromBody(raw, "id"))
                .sonarContent(getStrFromBody(raw, "sonarContent"))
                .signalCode(getStrFromBody(raw, "signalCode"))
                .userIdA(getStrFromBody(raw, "userIdA"))
                .userIdB(getStrFromBody(raw, "userIdB"))
                .createdAt(getLongFromBody(raw, "createdAt"))
                .expiresAt(getLongFromBody(raw, "expiresAt"))
                .unlocked(Boolean.parseBoolean(getStrFromBody(raw, "unlocked")))
                .deepConnectionAchieved(
                        Boolean.parseBoolean(getStrFromBody(raw, "deepConnectionAchieved")))
                .build();
    }

    private String getOtherUserId(ChatRoomData room, String userId) {
        return room.getUserIdA().equals(userId) ? room.getUserIdB() : room.getUserIdA();
    }

    private void checkDeepConnection(String roomId, ChatRoomData room) {
        if (room.isDeepConnectionAchieved()) return;

        // 24h 解锁窗口检查：超过窗口后不再触发新的深度交流达成
        long windowDeadline = room.getCreatedAt() + unlockWindowHours * 3600L * 1000L;
        if (System.currentTimeMillis() > windowDeadline) {
            return;
        }

        // 增量计数: 使用 Redis Hash 存储双方有效消息数
        String countKey = MSG_COUNT_PREFIX + roomId;
        Object countAObj = redisTemplate.opsForHash().get(countKey, room.getUserIdA());
        Object countBObj = redisTemplate.opsForHash().get(countKey, room.getUserIdB());
        int countA = countAObj != null ? Integer.parseInt(countAObj.toString()) : 0;
        int countB = countBObj != null ? Integer.parseInt(countBObj.toString()) : 0;
        int totalCount = countA + countB;

        // 双方都有参与(各>=5) 且 总消息数达到阈值
        if (countA >= 5 && countB >= 5 && totalCount >= unlockThresholdMessages) {
            redisTemplate.opsForHash().put(ROOM_PREFIX + roomId, "deepConnectionAchieved", "true");
            log.info("Deep connection achieved in room {}", roomId);
            webSocketHandler.notifyDeepConfirmed(room.getUserIdA(), roomId, false);
            webSocketHandler.notifyDeepConfirmed(room.getUserIdB(), roomId, false);
            // 离线推送：深度连接达成
            pushService.sendPush(
                    room.getUserIdA(),
                    "深度连接",
                    "你们已达成深度交流！",
                    Map.of("roomId", roomId, "type", "deep_connection"));
            pushService.sendPush(
                    room.getUserIdB(),
                    "深度连接",
                    "你们已达成深度交流！",
                    Map.of("roomId", roomId, "type", "deep_connection"));
        }
    }

    private void cleanupRoom(String roomId, ChatRoomData room) {
        redisTemplate.delete(ROOM_PREFIX + roomId);
        redisTemplate.delete(MESSAGES_PREFIX + roomId);
        redisTemplate.delete(DEEP_CONFIRM_PREFIX + roomId);
        redisTemplate.delete(SAVE_PREFIX + roomId);
        redisTemplate.delete(READ_PREFIX + roomId);
        redisTemplate.delete(ROOM_USERS_PREFIX + roomId);
        redisTemplate.opsForSet().remove(USER_ROOMS_PREFIX + room.getUserIdA(), roomId);
        redisTemplate.opsForSet().remove(USER_ROOMS_PREFIX + room.getUserIdB(), roomId);
        redisTemplate.opsForZSet().remove(ROOM_CREATED_AT_ZSET, roomId);
    }

    private RoomResponse toRoomResponse(ChatRoomData room, String userId) {
        int messageCount = getMessageCount(room.getId());
        String lastReadMessageId = getReadPointer(room.getId(), userId);
        String otherUserId = getOtherUserId(room, userId);
        String peerReadMessageId =
                otherUserId != null ? getReadPointer(room.getId(), otherUserId) : null;
        String deepConfirmKey = DEEP_CONFIRM_PREFIX + room.getId();
        boolean deepConnectionConfirmed =
                Boolean.TRUE.equals(
                        stringRedisTemplate.opsForSet().isMember(deepConfirmKey, userId));
        Long confirmedCount = stringRedisTemplate.opsForSet().size(deepConfirmKey);
        boolean bothDeepConfirmed =
                room.isUnlocked() || (confirmedCount != null && confirmedCount >= 2);

        // 保存连接状态
        String saveKey = SAVE_PREFIX + room.getId();
        boolean saveConnectionConfirmed =
                Boolean.TRUE.equals(stringRedisTemplate.opsForSet().isMember(saveKey, userId));
        Long saveCount = redisTemplate.opsForSet().size(saveKey);
        boolean bothSaveConfirmed = saveCount != null && saveCount >= 2;

        return new RoomResponse(
                room.getId(),
                room.getSignalCode(),
                room.getSonarContent(),
                getLastMessage(room.getId(), userId),
                room.getCreatedAt(),
                room.getExpiresAt(),
                room.isUnlocked(),
                room.isDeepConnectionAchieved(),
                deepConnectionConfirmed,
                bothDeepConfirmed,
                saveConnectionConfirmed,
                bothSaveConfirmed,
                messageCount,
                lastReadMessageId,
                peerReadMessageId);
    }

    private MessageResponse getLastMessage(String roomId, String userId) {
        String streamKey = MESSAGES_PREFIX + roomId;
        try {
            org.springframework.data.redis.connection.Limit redisLimit =
                    org.springframework.data.redis.connection.Limit.unlimited();
            redisLimit.count(1);
            List<?> rawMessages =
                    redisTemplate
                            .opsForStream()
                            .reverseRange(streamKey, Range.unbounded(), redisLimit);
            if (rawMessages == null || rawMessages.isEmpty()) return null;

            @SuppressWarnings("unchecked")
            MapRecord<String, Object, Object> last =
                    (MapRecord<String, Object, Object>) rawMessages.get(0);
            Map<Object, Object> body = last.getValue();
            String sender = getStrFromBody(body, "sender");
            return new MessageResponse(
                    last.getId().getValue(),
                    sender.equals(userId) ? "me" : "other",
                    getStrFromBody(body, "content"),
                    getLongFromBody(body, "timestamp"));
        } catch (Exception e) {
            log.warn("Failed to get last message: {}", e.getMessage());
            return null;
        }
    }

    private int getMessageCount(String roomId) {
        String streamKey = MESSAGES_PREFIX + roomId;
        try {
            Long len = redisTemplate.opsForStream().size(streamKey);
            return len != null ? len.intValue() : 0;
        } catch (Exception e) {
            return 0;
        }
    }
}
