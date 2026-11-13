package com.noisex.websocket;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

/**
 * WebSocket 端到端集成测试 连接 Docker 中运行的真实服务器验证完整 WebSocket 流程
 *
 * <p>前置条件：docker compose up -d（app:8080 健康） 运行方式：mvn test -Dtest=WebSocketE2ETest
 * -Dspring.profiles.active=test
 */
@Tag("e2e")
class WebSocketE2ETest extends WebSocketE2ETestBase {

    private TestWebSocketClient client1;
    private TestWebSocketClient client2;
    private String token1;
    private String token2;
    private String userId1;
    private String userId2;

    @BeforeEach
    void setUp() throws Exception {
        // 注册两个测试用户（anonymousUuid 必须是标准 UUID 格式）
        userId1 = UUID.randomUUID().toString();
        userId2 = UUID.randomUUID().toString();

        token1 = registerUserAndGetJwt(userId1);
        token2 = registerUserAndGetJwt(userId2);
    }

    @AfterEach
    void tearDown() throws Exception {
        if (client1 != null) client1.close();
        if (client2 != null) client2.close();
    }

    // ========== 连接与认证 ==========

    @Test
    void connect_withValidToken_shouldSucceed() throws Exception {
        client1 = connectWebSocket(token1);

        assertTrue(client1.isOpen(), "WebSocket 连接应该成功建立");
    }

    @Test
    void connect_withInvalidToken_shouldFail() {
        String invalidToken = "invalid.jwt.token";

        boolean failed = tryConnectWebSocketShouldFail(invalidToken);
        assertTrue(failed, "无效 JWT 应该被拒绝");
    }

    @Test
    void connect_withoutToken_shouldFail() {
        // 空字符串作为 token
        boolean failed = tryConnectWebSocketShouldFail("");
        assertTrue(failed, "无 token 应该被拒绝");
    }

    // ========== Ping/Pong ==========

    @Test
    void pingPong_shouldRespond() throws Exception {
        client1 = connectWebSocket(token1);

        // 发送 ping
        client1.sendMessage("{\"type\":\"ping\"}");

        // 等待 pong
        String response = client1.waitForMessageType("pong", DEFAULT_TIMEOUT_SECONDS);
        assertNotNull(response, "应该收到 pong 响应");

        JsonNode json = objectMapper.readTree(response);
        assertEquals("pong", json.get("type").asText());
    }

    // ========== 聊天消息 ==========

    @Test
    void chatMessage_shouldDeliverToOtherUser() throws Exception {
        // 两个用户连接 WebSocket
        client1 = connectWebSocket(token1);
        client2 = connectWebSocket(token2);

        // 先创建一个房间
        String roomId = createRoomViaRest();

        // 用户1 通过 WebSocket 发送聊天消息
        client1.sendJson("chat", Map.of("roomId", roomId, "content", "Hello from user1"));

        // 用户2 应该收到 chat 消息
        String received = client2.waitForMessageType("chat", DEFAULT_TIMEOUT_SECONDS + 2);
        assertNotNull(received, "用户2 应该收到用户1 的聊天消息");

        JsonNode json = objectMapper.readTree(received);
        assertEquals("chat", json.get("type").asText());
        assertEquals(roomId, json.get("roomId").asText());
        assertEquals("Hello from user1", json.get("content").asText());
        assertTrue(json.has("timestamp"), "消息应包含 timestamp");
    }

    // ========== 已读回执 ==========

    @Test
    void readReceipt_shouldNotifyOtherUser() throws Exception {
        client1 = connectWebSocket(token1);
        client2 = connectWebSocket(token2);

        String roomId = createRoomViaRest();

        // 先发一条消息确保房间可用
        client1.sendJson("chat", Map.of("roomId", roomId, "content", "Test message"));
        // 等用户2收到消息
        client2.waitForMessageType("chat", DEFAULT_TIMEOUT_SECONDS + 2);

        // 用户2 发送已读回执
        client2.sendJson("read", Map.of("roomId", roomId, "messageId", "msg-test-001"));

        // 用户1 应该收到 read_receipt
        String received = client1.waitForMessageType("read_receipt", DEFAULT_TIMEOUT_SECONDS);
        assertNotNull(received, "用户1 应该收到已读回执通知");

        JsonNode json = objectMapper.readTree(received);
        assertEquals("read_receipt", json.get("type").asText());
        assertEquals(roomId, json.get("roomId").asText());
        assertEquals("msg-test-001", json.get("messageId").asText());
    }

    // ========== 密钥交换 ==========

    @Test
    void keyExchange_shouldForwardPubKey() throws Exception {
        client1 = connectWebSocket(token1);
        client2 = connectWebSocket(token2);

        String roomId = createRoomViaRest();

        // 用户1 发送密钥交换
        String testPubKey = "BASE64_PUBLIC_KEY_TEST";
        client1.sendJson(
                "key_exchange",
                Map.of(
                        "roomId", roomId,
                        "pubKey", testPubKey));

        // 用户2 应该收到 key_exchange 转发
        String received = client2.waitForMessageType("key_exchange", DEFAULT_TIMEOUT_SECONDS);
        assertNotNull(received, "用户2 应该收到密钥交换消息");

        JsonNode json = objectMapper.readTree(received);
        assertEquals("key_exchange", json.get("type").asText());
        assertEquals(roomId, json.get("roomId").asText());
        assertEquals(testPubKey, json.get("pubKey").asText());
    }

    // ========== 断线 ==========

    @Test
    void disconnect_shouldRemoveFromOnline() throws Exception {
        client1 = connectWebSocket(token1);
        assertTrue(client1.isOpen());

        // 验证用户在线：发 ping 能收到 pong
        client1.sendMessage("{\"type\":\"ping\"}");
        String pong = client1.waitForMessageType("pong", DEFAULT_TIMEOUT_SECONDS);
        assertNotNull(pong, "连接断开前应能收到 pong");

        // 断开连接
        client1.close();

        // 等待断线完成
        Thread.sleep(1000);

        // 验证连接已关闭
        assertFalse(client1.isOpen(), "连接应该已关闭");
    }

    // ========== 声呐匹配 ==========

    @Test
    void sonarMatch_shouldNotifyBothUsers() throws Exception {
        // 两个用户连接 WebSocket（加入 ONLINE 集合）
        client1 = connectWebSocket(token1);
        client2 = connectWebSocket(token2);

        // 用户2 注册为 listener（开启收听模式）
        var listenResponse =
                sendRestRequest("POST", "/api/sonar/listen?geohash=wx4g0s", token2, null);
        assertEquals(200, listenResponse.statusCode(), "用户2 注册 listener 应成功");

        // 用户1 发送声呐 → onNewSonar 找到用户2 → 推送声呐给用户2
        var sonarResponse1 =
                sendRestRequest(
                        "POST",
                        "/api/sonar",
                        token1,
                        "{\"content\":\"Hello nearby\",\"geohash\":\"wx4g0s\"}");
        assertEquals(200, sonarResponse1.statusCode(), "用户1 声呐发送应成功");

        // 用户2 应该收到声呐
        String receivedSonarId = waitForReceivedSonar(token2, 10);
        assertNotNull(receivedSonarId, "用户2 应该收到用户1的声呐");

        // 用户2 接受声呐
        var acceptResponse =
                sendRestRequest("POST", "/api/sonar/" + receivedSonarId + "/accept", token2, null);
        assertEquals(200, acceptResponse.statusCode(), "声呐接受应成功");

        // 双方应该通过 WebSocket 收到 matched 通知
        String matched1 = client1.waitForMessageType("matched", DEFAULT_TIMEOUT_SECONDS + 3);
        String matched2 = client2.waitForMessageType("matched", DEFAULT_TIMEOUT_SECONDS + 3);

        assertNotNull(matched1, "用户1 应该收到 matched 通知");
        assertNotNull(matched2, "用户2 应该收到 matched 通知");

        JsonNode json1 = objectMapper.readTree(matched1);
        JsonNode json2 = objectMapper.readTree(matched2);

        assertEquals("matched", json1.get("type").asText());
        assertEquals("matched", json2.get("type").asText());
        assertTrue(json1.has("roomId"), "matched 通知应包含 roomId");
        assertTrue(json2.has("roomId"), "matched 通知应包含 roomId");
        assertEquals(json1.get("roomId").asText(), json2.get("roomId").asText(), "双方的 roomId 应相同");
    }

    // ========== 辅助方法 ==========

    /** 通过 REST API 创建房间 匹配流程：用户2 listen → 用户1 sendSonar → onNewSonar 推送给用户2 → 用户2 accept */
    private String createRoomViaRest() throws Exception {
        // 确保两个用户都已通过 WebSocket 连接（在 ONLINE 集合中）
        if (client1 == null || !client1.isOpen()) {
            client1 = connectWebSocket(token1);
        }
        if (client2 == null || !client2.isOpen()) {
            client2 = connectWebSocket(token2);
        }

        // 用户2 注册为 listener（开启收听模式）
        sendRestRequest("POST", "/api/sonar/listen?geohash=wx4g0s", token2, null);

        // 用户1 发送声呐 → onNewSonar 找到用户2 → 推送声呐给用户2
        var sonarResponse1 =
                sendRestRequest(
                        "POST",
                        "/api/sonar",
                        token1,
                        "{\"content\":\"E2E test sonar\",\"geohash\":\"wx4g0s\"}");
        assertEquals(200, sonarResponse1.statusCode(), "用户1 声呐发送应成功");

        // 用户2 应该收到声呐
        String sonarId = waitForReceivedSonar(token2, 10);
        assertNotNull(sonarId, "用户2 应该收到用户1的声呐");

        // 用户2 接受声呐
        var acceptResponse =
                sendRestRequest("POST", "/api/sonar/" + sonarId + "/accept", token2, null);
        assertEquals(200, acceptResponse.statusCode(), "声呐接受应成功");

        JsonNode acceptJson = objectMapper.readTree(acceptResponse.body());
        return acceptJson.get("data").get("roomId").asText();
    }

    /** 轮询 received sonars 直到获取到声呐 ID */
    private String waitForReceivedSonar(String token, int maxRetries) throws Exception {
        for (int i = 0; i < maxRetries; i++) {
            Thread.sleep(500);
            var response = sendRestRequest("GET", "/api/sonar/received", token, null);
            if (response.statusCode() == 200) {
                JsonNode json = objectMapper.readTree(response.body());
                JsonNode data = json.get("data");
                if (data != null && data.isArray() && !data.isEmpty()) {
                    return data.get(0).get("id").asText();
                }
            }
        }
        return null;
    }
}
