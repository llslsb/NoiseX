package com.noisex.websocket;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.noisex.model.domain.ChatRoomData;
import com.noisex.model.dto.UnlockResponse;
import com.noisex.service.ChatService;
import com.noisex.service.SonarService;
import com.noisex.util.RedisKeys;
import java.util.HashMap;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class WebSocketHandlerTest {

    @Mock private ChatService chatService;

    @Mock private RedisTemplate<String, Object> redisTemplate;

    @Mock private ObjectMapper objectMapper;

    @Mock private SonarService sonarService;

    @InjectMocks private NoiseXWebSocketHandler handler;

    private WebSocketSession session;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() {
        session = mock(WebSocketSession.class);
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("userId", "user-123");
        when(session.getAttributes()).thenReturn(attributes);
        when(session.isOpen()).thenReturn(true);

        SetOperations<String, Object> setOps = mock(SetOperations.class);
        when(redisTemplate.opsForSet()).thenReturn(setOps);
    }

    @SuppressWarnings("unchecked")
    @Test
    void afterConnectionEstablished_shouldRegisterSession() {
        handler.afterConnectionEstablished(session);

        SetOperations<String, Object> setOps = redisTemplate.opsForSet();
        verify(setOps).add(RedisKeys.ONLINE, "user-123");
    }

    @Test
    void afterConnectionClosed_shouldRemoveSession() {
        handler.afterConnectionEstablished(session);

        handler.afterConnectionClosed(session, CloseStatus.NORMAL);

        verify(sonarService).unregisterListenerFromAll("user-123");
    }

    @Test
    void handleTextMessage_chatType_shouldCallChatService() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        realHandler.afterConnectionEstablished(session);

        String payload = "{\"type\":\"chat\",\"roomId\":\"room-1\",\"content\":\"hello\"}";
        when(chatService.sendMessage("room-1", "user-123", "hello")).thenReturn("1700000000000-0");
        when(chatService.getOtherUserId("room-1", "user-123")).thenReturn("user-456");
        when(chatService.getRoomSignalCode("room-1")).thenReturn("SIG-001");

        realHandler.handleTextMessage(session, new TextMessage(payload));

        verify(chatService).sendMessage("room-1", "user-123", "hello");
    }

    @Test
    void handleTextMessage_pingType_shouldUpdateLastPingTime() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        realHandler.afterConnectionEstablished(session);

        String payload = "{\"type\":\"ping\"}";

        realHandler.handleTextMessage(session, new TextMessage(payload));

        ArgumentCaptor<TextMessage> messageCaptor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeastOnce()).sendMessage(messageCaptor.capture());
        assertThat(
                        messageCaptor.getAllValues().stream()
                                .anyMatch(m -> m.getPayload().contains("pong")))
                .isTrue();
    }

    @Test
    void handleTextMessage_deepConfirm_shouldSendOwnConfirmState() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        realHandler.afterConnectionEstablished(session);

        String payload = "{\"type\":\"deep_confirm\",\"roomId\":\"room-1\"}";
        when(chatService.unlockProfile("room-1", "user-123"))
                .thenReturn(new UnlockResponse(false, null));
        when(chatService.getOtherUserId("room-1", "user-123")).thenReturn(null);

        realHandler.handleTextMessage(session, new TextMessage(payload));

        ArgumentCaptor<TextMessage> messageCaptor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeastOnce()).sendMessage(messageCaptor.capture());
        assertThat(
                        messageCaptor.getAllValues().stream()
                                .map(TextMessage::getPayload)
                                .anyMatch(
                                        m ->
                                                m.contains("deep_confirmed")
                                                        && m.contains(
                                                                "deepConnectionConfirmed\":true")
                                                        && m.contains("bothDeepConfirmed\":false")))
                .isTrue();
    }

    @Test
    void handleTextMessage_deepConfirm_shouldKeepPreviousConfirmerStateWhenBothConfirmed()
            throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);
        WebSocketSession receiverSession = mock(WebSocketSession.class);
        Map<String, Object> receiverAttributes = new HashMap<>();
        receiverAttributes.put("userId", "user-456");
        when(receiverSession.getAttributes()).thenReturn(receiverAttributes);
        when(receiverSession.isOpen()).thenReturn(true);

        realHandler.afterConnectionEstablished(session);
        realHandler.afterConnectionEstablished(receiverSession);

        String payload = "{\"type\":\"deep_confirm\",\"roomId\":\"room-1\"}";
        when(chatService.unlockProfile("room-1", "user-123"))
                .thenReturn(new UnlockResponse(true, null));
        when(chatService.getOtherUserId("room-1", "user-123")).thenReturn("user-456");

        realHandler.handleTextMessage(session, new TextMessage(payload));

        ArgumentCaptor<TextMessage> receiverCaptor = ArgumentCaptor.forClass(TextMessage.class);
        verify(receiverSession, atLeastOnce()).sendMessage(receiverCaptor.capture());
        assertThat(
                        receiverCaptor.getAllValues().stream()
                                .map(TextMessage::getPayload)
                                .anyMatch(
                                        m ->
                                                m.contains("deep_confirmed")
                                                        && m.contains(
                                                                "deepConnectionConfirmed\":true")
                                                        && m.contains("bothDeepConfirmed\":true")))
                .isTrue();
    }

    @Test
    void notifyMatched_shouldSendToUser() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        realHandler.afterConnectionEstablished(session);

        ChatRoomData room =
                ChatRoomData.builder()
                        .id("room-1")
                        .signalCode("SIG-001")
                        .sonarContent("hello")
                        .expiresAt(999999L)
                        .build();

        realHandler.notifyMatched("user-123", room);

        ArgumentCaptor<TextMessage> messageCaptor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session).sendMessage(messageCaptor.capture());
        String sent = messageCaptor.getValue().getPayload();
        assertThat(sent).contains("matched");
        assertThat(sent).contains("room-1");
    }

    @Test
    void notifyRoomExpired_shouldSendToUser() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        realHandler.afterConnectionEstablished(session);

        realHandler.notifyRoomExpired("user-123", "room-1");

        ArgumentCaptor<TextMessage> messageCaptor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session).sendMessage(messageCaptor.capture());
        String sent = messageCaptor.getValue().getPayload();
        assertThat(sent).contains("room_expired");
        assertThat(sent).contains("room-1");
    }

    /** delivered 协议已下线（2026-11-02）：对方在线也不再回 delivered，✓✓ 只由 read_receipt 驱动 */
    @Test
    void handleTextMessage_chat_shouldNotEmitDeliveredWhenReceiverOnline() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        WebSocketSession receiverSession = mock(WebSocketSession.class);
        Map<String, Object> receiverAttrs = new HashMap<>();
        receiverAttrs.put("userId", "user-456");
        when(receiverSession.getAttributes()).thenReturn(receiverAttrs);
        when(receiverSession.isOpen()).thenReturn(true);

        realHandler.afterConnectionEstablished(session);
        realHandler.afterConnectionEstablished(receiverSession);

        when(chatService.sendMessage("room-1", "user-123", "hi")).thenReturn("mid-001");
        when(chatService.getOtherUserId("room-1", "user-123")).thenReturn("user-456");
        when(chatService.getRoomSignalCode("room-1")).thenReturn("SIG-001");

        String payload = "{\"type\":\"chat\",\"roomId\":\"room-1\",\"content\":\"hi\"}";
        realHandler.handleTextMessage(session, new TextMessage(payload));

        ArgumentCaptor<TextMessage> senderCaptor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeastOnce()).sendMessage(senderCaptor.capture());
        boolean hasDelivered =
                senderCaptor.getAllValues().stream()
                        .map(TextMessage::getPayload)
                        .anyMatch(m -> m.contains("\"type\":\"delivered\""));
        assertThat(hasDelivered).isFalse();
    }

    /** delivered 协议已下线：对方离线同样不回 delivered */
    @Test
    void handleTextMessage_chat_shouldNotEmitDeliveredWhenReceiverOffline() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        realHandler.afterConnectionEstablished(session);

        when(chatService.sendMessage("room-1", "user-123", "hi")).thenReturn("mid-001");
        when(chatService.getOtherUserId("room-1", "user-123")).thenReturn("user-456");
        when(chatService.getRoomSignalCode("room-1")).thenReturn("SIG-001");

        String payload = "{\"type\":\"chat\",\"roomId\":\"room-1\",\"content\":\"hi\"}";
        realHandler.handleTextMessage(session, new TextMessage(payload));

        ArgumentCaptor<TextMessage> senderCaptor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session, atLeastOnce()).sendMessage(senderCaptor.capture());
        boolean hasDelivered =
                senderCaptor.getAllValues().stream()
                        .map(TextMessage::getPayload)
                        .anyMatch(m -> m.contains("\"type\":\"delivered\""));
        assertThat(hasDelivered).isFalse();
    }

    /** P1-A：typing_start 应转发给房间另一方，并附 signalCode */
    @Test
    void handleTextMessage_typingStart_shouldForwardToPeer() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        WebSocketSession receiverSession = mock(WebSocketSession.class);
        Map<String, Object> receiverAttrs = new HashMap<>();
        receiverAttrs.put("userId", "user-456");
        when(receiverSession.getAttributes()).thenReturn(receiverAttrs);
        when(receiverSession.isOpen()).thenReturn(true);

        realHandler.afterConnectionEstablished(session);
        realHandler.afterConnectionEstablished(receiverSession);

        when(chatService.getOtherUserId("room-1", "user-123")).thenReturn("user-456");
        when(chatService.getRoomSignalCode("room-1")).thenReturn("SIG-001");

        String payload = "{\"type\":\"typing_start\",\"roomId\":\"room-1\"}";
        realHandler.handleTextMessage(session, new TextMessage(payload));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(receiverSession, atLeastOnce()).sendMessage(captor.capture());
        boolean hasTyping =
                captor.getAllValues().stream()
                        .map(TextMessage::getPayload)
                        .anyMatch(
                                m ->
                                        m.contains("\"type\":\"typing_start\"")
                                                && m.contains("\"roomId\":\"room-1\"")
                                                && m.contains("\"sender\":\"SIG-001\""));
        assertThat(hasTyping).isTrue();
    }

    /** P1-A：typing_stop 同理转发 */
    @Test
    void handleTextMessage_typingStop_shouldForwardToPeer() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        WebSocketSession receiverSession = mock(WebSocketSession.class);
        Map<String, Object> receiverAttrs = new HashMap<>();
        receiverAttrs.put("userId", "user-456");
        when(receiverSession.getAttributes()).thenReturn(receiverAttrs);
        when(receiverSession.isOpen()).thenReturn(true);

        realHandler.afterConnectionEstablished(session);
        realHandler.afterConnectionEstablished(receiverSession);

        when(chatService.getOtherUserId("room-1", "user-123")).thenReturn("user-456");
        when(chatService.getRoomSignalCode("room-1")).thenReturn("SIG-001");

        String payload = "{\"type\":\"typing_stop\",\"roomId\":\"room-1\"}";
        realHandler.handleTextMessage(session, new TextMessage(payload));

        ArgumentCaptor<TextMessage> captor = ArgumentCaptor.forClass(TextMessage.class);
        verify(receiverSession, atLeastOnce()).sendMessage(captor.capture());
        boolean hasTyping =
                captor.getAllValues().stream()
                        .map(TextMessage::getPayload)
                        .anyMatch(m -> m.contains("\"type\":\"typing_stop\""));
        assertThat(hasTyping).isTrue();
    }

    /** P1-A：typing 缺 roomId 时静默丢弃 */
    @Test
    void handleTextMessage_typing_withoutRoomId_shouldNotForward() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        realHandler.afterConnectionEstablished(session);

        String payload = "{\"type\":\"typing_start\"}";
        realHandler.handleTextMessage(session, new TextMessage(payload));

        verify(chatService, never()).getOtherUserId(any(), any());
    }

    /**
     * F2-1：notifyPeerLeft 应向对方推送 peer_left 事件，payload 包含 type/roomId/signalCode/leftAt 四字段。
     *
     * <p>对应计划 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F2-1。
     */
    @Test
    void notifyPeerLeft_shouldSendPayloadWithSignalCode() throws Exception {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        realHandler.afterConnectionEstablished(session);

        long before = System.currentTimeMillis();
        realHandler.notifyPeerLeft("user-123", "room-1", "SIG-001");
        long after = System.currentTimeMillis();

        ArgumentCaptor<TextMessage> messageCaptor = ArgumentCaptor.forClass(TextMessage.class);
        verify(session).sendMessage(messageCaptor.capture());
        String sent = messageCaptor.getValue().getPayload();

        assertThat(sent).contains("\"type\":\"peer_left\"");
        assertThat(sent).contains("\"roomId\":\"room-1\"");
        assertThat(sent).contains("\"signalCode\":\"SIG-001\"");

        // leftAt 必须是合法时间戳，落在调用前后区间内
        com.fasterxml.jackson.databind.JsonNode parsed = realMapper.readTree(sent);
        assertThat(parsed.has("leftAt")).isTrue();
        long leftAt = parsed.get("leftAt").asLong();
        assertThat(leftAt).isBetween(before, after);
    }

    /** F2-1：目标用户 session 不存在时应静默丢弃，不抛异常。 */
    @Test
    void notifyPeerLeft_shouldNoOpWhenSessionAbsent() {
        ObjectMapper realMapper = new ObjectMapper();
        NoiseXWebSocketHandler realHandler =
                new NoiseXWebSocketHandler(chatService, redisTemplate, realMapper, sonarService);

        // 不调用 afterConnectionEstablished，sessions map 为空
        assertThatCode(() -> realHandler.notifyPeerLeft("ghost-user", "room-1", "SIG-001"))
                .doesNotThrowAnyException();
    }
}
