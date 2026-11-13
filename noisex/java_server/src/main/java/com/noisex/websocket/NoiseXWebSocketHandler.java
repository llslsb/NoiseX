package com.noisex.websocket;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.noisex.model.domain.ChatRoomData;
import com.noisex.service.ChatService;
import com.noisex.util.RedisKeys;
import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

@Component
public class NoiseXWebSocketHandler extends TextWebSocketHandler {

    private static final Logger log = LoggerFactory.getLogger(NoiseXWebSocketHandler.class);

    private final ChatService chatService;
    private final RedisTemplate<String, Object> redisTemplate;
    private final ObjectMapper objectMapper;
    private final com.noisex.service.SonarService sonarService;

    private static final String ONLINE_KEY = RedisKeys.ONLINE;
    private static final String USER_ROOMS_PREFIX = RedisKeys.USER_ROOMS_PREFIX;

    // userId -> WebSocketSession
    private final ConcurrentHashMap<String, WebSocketSession> sessions = new ConcurrentHashMap<>();
    // userId -> last ping timestamp
    private final ConcurrentHashMap<String, Long> lastPingTime = new ConcurrentHashMap<>();

    // 2026-11-05 从 120s 压到 60s（勿回退）：鸿蒙/安卓后台会冻结 App——TCP 未断但
    // 已收不到消息，2 分钟的驱逐窗意味着后台头两分钟的消息通知全部丢失（实锤）。
    // 客户端 30s 一跳，60s 超时=容忍丢两跳，弱网误伤由客户端自动重连兜底
    private static final long HEARTBEAT_TIMEOUT_MS = 60_000L;

    public NoiseXWebSocketHandler(
            @Lazy ChatService chatService,
            RedisTemplate<String, Object> redisTemplate,
            ObjectMapper objectMapper,
            @Lazy com.noisex.service.SonarService sonarService) {
        this.chatService = chatService;
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
        this.sonarService = sonarService;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) {
        String userId = extractUserId(session);
        if (userId != null) {
            sessions.put(userId, session);
            lastPingTime.put(userId, System.currentTimeMillis());
            redisTemplate.opsForSet().add(ONLINE_KEY, userId);
            log.info("WebSocket connected: userId={}", userId);
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        String userId = extractUserId(session);
        if (userId != null) {
            sessions.remove(userId);
            lastPingTime.remove(userId);
            redisTemplate.opsForSet().remove(ONLINE_KEY, userId);
            // 清理该用户的所有 listener 记录，防止离线用户占位
            sonarService.unregisterListenerFromAll(userId);
            log.info("WebSocket disconnected: userId={}, status={}", userId, status);
        }
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message)
            throws Exception {
        String userId = extractUserId(session);
        if (userId == null) return;

        try {
            JsonNode json = objectMapper.readTree(message.getPayload());
            JsonNode typeNode = json.get("type");
            if (typeNode == null || !typeNode.isTextual()) {
                log.warn("WebSocket message missing type field from {}", userId);
                return;
            }
            String type = typeNode.asText();

            switch (type) {
                case "chat" -> handleChatMessage(userId, json);
                case "deep_confirm" -> handleDeepConfirm(userId, json);
                case "read" -> handleReadReceipt(userId, json);
                case "key_exchange" -> handleKeyExchange(userId, json);
                case "typing_start" -> handleTyping(userId, json, true);
                case "typing_stop" -> handleTyping(userId, json, false);
                case "ping" -> {
                    lastPingTime.put(userId, System.currentTimeMillis());
                    // 2026-11-02：ping 顺带续期监听注册 TTL（30min），防幽灵格子永久残留
                    try {
                        sonarService.touchListenerTTL(userId);
                    } catch (Exception ttlError) {
                        log.debug(
                                "Listener TTL touch failed for {}: {}",
                                userId,
                                ttlError.getMessage());
                    }
                    sendToUser(userId, createPong());
                }
                default -> log.warn("Unknown message type: {}", type);
            }
        } catch (Exception e) {
            log.error("Error handling WebSocket message from {}: {}", userId, e.getMessage());
        }
    }

    private void handleChatMessage(String senderId, JsonNode json) {
        JsonNode roomIdNode = json.get("roomId");
        JsonNode contentNode = json.get("content");
        if (roomIdNode == null
                || !roomIdNode.isTextual()
                || contentNode == null
                || !contentNode.isTextual()) {
            log.warn("Invalid chat message: missing or invalid roomId/content from {}", senderId);
            return;
        }
        String roomId = roomIdNode.asText();
        String content = contentNode.asText();
        if (roomId.isEmpty() || content.isEmpty()) {
            log.warn("Invalid chat message: empty roomId/content from {}", senderId);
            return;
        }

        String messageId;
        try {
            messageId = chatService.sendMessage(roomId, senderId, content);
        } catch (Exception e) {
            // 发送限制异常（连续消息/频率/重复等）反馈给客户端
            ObjectNode errorPayload = objectMapper.createObjectNode();
            errorPayload.put("type", "error");
            errorPayload.put("action", "chat");
            errorPayload.put("roomId", roomId);
            errorPayload.put("message", e.getMessage() != null ? e.getMessage() : "发送失败");
            sendToUser(senderId, errorPayload);
            return;
        }

        String receiverId = chatService.getOtherUserId(roomId, senderId);
        if (receiverId == null) return;

        // 获取房间的 signalCode 作为发送者标识（保护匿名性）
        String signalCode = chatService.getRoomSignalCode(roomId);

        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("type", "chat");
        payload.put("roomId", roomId);
        payload.put("messageId", messageId);
        payload.put("content", content);
        payload.put("sender", signalCode != null ? signalCode : senderId);
        payload.put("timestamp", System.currentTimeMillis());
        sendToUser(receiverId, payload);

        // B17：发送确认使用独立的 sent_ack 类型。此前复用 "chat" 类型回送，
        // 客户端 _handleChat 无法区分，会把发送者自己的消息当对方消息重复渲染。
        // 两端（ArkTS/Flutter）对未知 type 均忽略，新增类型无兼容性风险。
        ObjectNode ackPayload = payload.deepCopy();
        ackPayload.put("type", "sent_ack");
        ackPayload.put("sender", "me");
        sendToUser(senderId, ackPayload);

        // delivered 协议已下线（2026-11-02 产品拍板）：原 P1-A 逻辑只要对方 WS
        // 会话存在（App 在前台哪怕停在列表页/后台进程存活）就给发送者回
        // delivered，发送端立即画 ✓✓，语义与"对方已读"混淆。现口径：
        // ✓ = 服务器已收（sent_ack），✓✓ = 对方已读（对方打开聊天页触发
        // read → read_receipt）。delivered 帧不再产生，客户端的历史处理分支
        // 保留为死路径（对未知帧无副作用）。
    }

    /**
     * 处理 typing_start / typing_stop。
     *
     * <p>仅做信令转发：将对方"正在输入"状态广播给房间内的另一端，附 signalCode 保护匿名性。 不持久化、不入 Redis；客户端通过 4s 超时自动清除。
     *
     * <p>与计划文档 docs/superpowers/plans/2026-06-15-ux-revamp.md P1 typing 协议对齐。
     */
    private void handleTyping(String userId, JsonNode json, boolean isStart) {
        JsonNode roomIdNode = json.get("roomId");
        if (roomIdNode == null || !roomIdNode.isTextual() || roomIdNode.asText().isEmpty()) {
            log.warn("Invalid typing event: missing or invalid roomId from {}", userId);
            return;
        }
        String roomId = roomIdNode.asText();
        String receiverId = chatService.getOtherUserId(roomId, userId);
        if (receiverId == null) return;
        String signalCode = chatService.getRoomSignalCode(roomId);

        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("type", isStart ? "typing_start" : "typing_stop");
        payload.put("roomId", roomId);
        payload.put("sender", signalCode != null ? signalCode : userId);
        sendToUser(receiverId, payload);
    }

    private void handleDeepConfirm(String userId, JsonNode json) {
        JsonNode roomIdNode = json.get("roomId");
        if (roomIdNode == null || !roomIdNode.isTextual() || roomIdNode.asText().isEmpty()) {
            log.warn("Invalid deep_confirm: missing or invalid roomId from {}", userId);
            return;
        }
        String roomId = roomIdNode.asText();
        try {
            var result = chatService.unlockProfile(roomId, userId);
            boolean bothConfirmed = result.isUnlocked();
            String receiverId = chatService.getOtherUserId(roomId, userId);
            if (receiverId != null) {
                ObjectNode payloadToOther = objectMapper.createObjectNode();
                payloadToOther.put("type", "deep_confirmed");
                payloadToOther.put("roomId", roomId);
                payloadToOther.put("deepConnectionConfirmed", bothConfirmed);
                payloadToOther.put("bothDeepConfirmed", bothConfirmed);
                payloadToOther.put("bothConfirmed", bothConfirmed);
                payloadToOther.put("unlocked", bothConfirmed);
                sendToUser(receiverId, payloadToOther);
            }
            ObjectNode payloadToSelf = objectMapper.createObjectNode();
            payloadToSelf.put("type", "deep_confirmed");
            payloadToSelf.put("roomId", roomId);
            payloadToSelf.put("deepConnectionConfirmed", true);
            payloadToSelf.put("bothDeepConfirmed", bothConfirmed);
            payloadToSelf.put("bothConfirmed", bothConfirmed);
            payloadToSelf.put("unlocked", bothConfirmed);
            sendToUser(userId, payloadToSelf);
        } catch (Exception e) {
            log.debug("Deep confirm not yet eligible: {}", e.getMessage());
        }
    }

    private void handleReadReceipt(String userId, JsonNode json) {
        JsonNode roomIdNode = json.get("roomId");
        JsonNode messageIdNode = json.get("messageId");
        if (roomIdNode == null
                || !roomIdNode.isTextual()
                || roomIdNode.asText().isEmpty()
                || messageIdNode == null
                || !messageIdNode.isTextual()
                || messageIdNode.asText().isEmpty()) {
            log.warn("Invalid read receipt: missing or invalid roomId/messageId from {}", userId);
            return;
        }
        String roomId = roomIdNode.asText();
        String messageId = messageIdNode.asText();
        chatService.markAsRead(roomId, userId, messageId);
        String receiverId = chatService.getOtherUserId(roomId, userId);
        if (receiverId != null) {
            ObjectNode payload = objectMapper.createObjectNode();
            payload.put("type", "read_receipt");
            payload.put("roomId", roomId);
            payload.put("messageId", messageId);
            payload.put("readBy", userId);
            sendToUser(receiverId, payload);
        }
    }

    private void handleKeyExchange(String userId, JsonNode json) {
        JsonNode roomIdNode = json.get("roomId");
        JsonNode pubKeyNode = json.get("pubKey");
        if (roomIdNode == null
                || !roomIdNode.isTextual()
                || roomIdNode.asText().isEmpty()
                || pubKeyNode == null
                || !pubKeyNode.isTextual()
                || pubKeyNode.asText().isEmpty()) {
            log.warn("Invalid key_exchange: missing or invalid roomId/pubKey from {}", userId);
            return;
        }
        String roomId = roomIdNode.asText();
        String pubKey = pubKeyNode.asText();
        String receiverId = chatService.getOtherUserId(roomId, userId);
        if (receiverId != null) {
            ObjectNode payload = objectMapper.createObjectNode();
            payload.put("type", "key_exchange");
            payload.put("roomId", roomId);
            payload.put("pubKey", pubKey);
            sendToUser(receiverId, payload);
        }
    }

    public void notifyNewSonar(String userId, com.noisex.model.domain.SonarData sonar) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("type", "sonar_received");
        payload.put("sonarId", sonar.getId());
        payload.put("content", sonar.getContent());
        payload.put("timestamp", sonar.getTimestamp());
        sendToUser(userId, payload);
    }

    public void notifyMatched(String userId, ChatRoomData room) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("type", "matched");
        payload.put("roomId", room.getId());
        payload.put("signalCode", room.getSignalCode());
        payload.put("sonarContent", room.getSonarContent());
        payload.put("expiresAt", room.getExpiresAt());
        sendToUser(userId, payload);
    }

    public void notifyRoomExpired(String userId, String roomId) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("type", "room_expired");
        payload.put("roomId", roomId);
        sendToUser(userId, payload);
    }

    /**
     * F2：对方主动离开房间时通知留下的一端。
     *
     * <p>区别于 {@link #notifyRoomExpired}：room_expired 表示房间 TTL 到期，双方都收到； peer_left
     * 表示其中一方主动离开，仅留下的一端收到，前端用于显示「对方已离开」而不是 undefined。
     *
     * <p>payload: <code>{type:"peer_left", roomId, signalCode, leftAt}</code>。 signalCode
     * 用对方在该房间的匿名代号，避免泄漏 userId。 若 otherUserId 不在当前 sessions 中（已离线），sendToUser 静默 no-op，不抛异常。
     *
     * <p>对应计划 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F2-1。
     */
    public void notifyPeerLeft(String otherUserId, String roomId, String signalCode) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("type", "peer_left");
        payload.put("roomId", roomId);
        payload.put("signalCode", signalCode);
        payload.put("leftAt", System.currentTimeMillis());
        sendToUser(otherUserId, payload);
    }

    public void notifyRoomExpiredByRoomId(String roomId) {
        for (Map.Entry<String, WebSocketSession> entry : sessions.entrySet()) {
            String userId = entry.getKey();
            Boolean isMember =
                    redisTemplate.opsForSet().isMember(USER_ROOMS_PREFIX + userId, roomId);
            if (Boolean.TRUE.equals(isMember)) {
                notifyRoomExpired(userId, roomId);
            }
        }
    }

    /** 通知房间即将过期（剩余时间 < 12 小时） */
    public void notifyRoomExpiring(String roomId, double remainingHours) {
        for (Map.Entry<String, WebSocketSession> entry : sessions.entrySet()) {
            String userId = entry.getKey();
            Boolean isMember =
                    redisTemplate.opsForSet().isMember(USER_ROOMS_PREFIX + userId, roomId);
            if (Boolean.TRUE.equals(isMember)) {
                ObjectNode payload = objectMapper.createObjectNode();
                payload.put("type", "room_expiring");
                payload.put("roomId", roomId);
                payload.put("remainingHours", remainingHours);
                sendToUser(userId, payload);
            }
        }
    }

    public void notifyDeepConfirmed(String userId, String roomId, boolean bothConfirmed) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("type", "deep_confirmed");
        payload.put("roomId", roomId);
        payload.put("deepConnectionConfirmed", false);
        payload.put("bothDeepConfirmed", bothConfirmed);
        payload.put("bothConfirmed", bothConfirmed);
        payload.put("unlocked", bothConfirmed);
        sendToUser(userId, payload);
    }

    public void notifySaveRequest(String userId, String roomId, String fromSignalCode) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("type", "save_request");
        payload.put("roomId", roomId);
        payload.put("fromSignalCode", fromSignalCode);
        sendToUser(userId, payload);
    }

    /** 通知双方连接已保存成功 */
    public void notifySaveConfirmed(String userId, String roomId) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("type", "save_confirmed");
        payload.put("roomId", roomId);
        sendToUser(userId, payload);
    }

    /** 通知发起方对方拒绝了保存连接 */
    public void notifySaveRefused(String userId, String roomId) {
        ObjectNode payload = objectMapper.createObjectNode();
        payload.put("type", "save_refused");
        payload.put("roomId", roomId);
        sendToUser(userId, payload);
    }

    /**
     * 强制下线（管理员封禁等场景）：以 1008 POLICY_VIOLATION 关闭该用户的 WS 会话。 不发送额外 payload——会话关闭后客户端的重连握手会被
     * WebSocketInterceptor 以黑名单/封禁标记拒绝， REST 请求由 JwtAuthenticationFilter 返回 401。无活跃会话时静默 no-op。
     */
    public void kickUser(String userId, String reason) {
        WebSocketSession session = sessions.get(userId);
        if (session == null || !session.isOpen()) {
            return;
        }
        try {
            session.close(CloseStatus.POLICY_VIOLATION.withReason(reason));
            log.info("WebSocket session kicked: userId={}, reason={}", userId, reason);
        } catch (IOException e) {
            log.warn("Failed to kick WebSocket session for {}: {}", userId, e.getMessage());
        }
    }

    private void sendToUser(String userId, Object payload) {
        WebSocketSession session = sessions.get(userId);
        if (session == null || !session.isOpen()) {
            // 诊断辅助：目标无活跃 WS session 时打 warn，便于排查"投递成功但客户端收不到"。
            // 典型场景：用户 WS 握手被拒（token 过期）但 REST 仍以匿名身份注册了 listener，
            // MatchEngine 把声呐投给该 listener，这里找不到 session 只能丢弃。
            // type 字段帮助区分是哪种推送（sonar_received / chat / matched 等）。
            String type = "";
            if (payload instanceof com.fasterxml.jackson.databind.node.ObjectNode node) {
                type = node.path("type").asText("");
            }
            log.warn("WS push dropped: userId={} has no active session (type={})", userId, type);
            return;
        }
        for (int attempt = 1; attempt <= 3; attempt++) {
            try {
                String json = objectMapper.writeValueAsString(payload);
                session.sendMessage(new TextMessage(json));
                return;
            } catch (IOException e) {
                log.warn(
                        "Failed to send WS message to {} (attempt {}/3): {}",
                        userId,
                        attempt,
                        e.getMessage());
                if (attempt < 3) {
                    try {
                        Thread.sleep(100L * attempt);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        return;
                    }
                }
            }
        }
        log.error("Failed to send WS message to {} after 3 retries", userId);
    }

    private ObjectNode createPong() {
        ObjectNode pong = objectMapper.createObjectNode();
        pong.put("type", "pong");
        return pong;
    }

    @Scheduled(fixedRate = 30_000L)
    public void checkHeartbeatTimeout() {
        long now = System.currentTimeMillis();
        for (Map.Entry<String, Long> entry : lastPingTime.entrySet()) {
            String userId = entry.getKey();
            if (now - entry.getValue() > HEARTBEAT_TIMEOUT_MS) {
                WebSocketSession session = sessions.get(userId);
                if (session != null && session.isOpen()) {
                    try {
                        session.close(CloseStatus.SERVER_ERROR);
                        log.warn("WebSocket heartbeat timeout, closing session: userId={}", userId);
                    } catch (IOException e) {
                        log.error(
                                "Failed to close timed-out session for {}: {}",
                                userId,
                                e.getMessage());
                    }
                }
            }
        }
    }

    private String extractUserId(WebSocketSession session) {
        Object userId = session.getAttributes().get("userId");
        return userId != null ? userId.toString() : null;
    }
}
