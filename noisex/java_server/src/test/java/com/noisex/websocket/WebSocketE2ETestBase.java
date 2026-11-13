package com.noisex.websocket;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.websocket.*;
import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** WebSocket 端到端测试基类 直接连接 Docker 中运行的真实服务器（app:8080），不启动 Spring 容器 */
public abstract class WebSocketE2ETestBase {

    protected static final String BASE_URL = "http://localhost:8080";
    protected static final String WS_URL = "ws://localhost:8080/ws";
    protected static final ObjectMapper objectMapper = new ObjectMapper();
    protected static final long DEFAULT_TIMEOUT_SECONDS = 5;

    /** 通过 REST API 注册用户并获取 JWT */
    protected String registerUserAndGetJwt(String anonymousId) throws Exception {
        java.net.http.HttpClient client = java.net.http.HttpClient.newHttpClient();
        String body = "{\"anonymousUuid\":\"" + anonymousId + "\"}";
        java.net.http.HttpRequest request =
                java.net.http.HttpRequest.newBuilder()
                        .uri(URI.create(BASE_URL + "/api/auth/register"))
                        .header("Content-Type", "application/json")
                        .POST(java.net.http.HttpRequest.BodyPublishers.ofString(body))
                        .build();

        java.net.http.HttpResponse<String> response =
                client.send(request, java.net.http.HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            throw new RuntimeException(
                    "Register failed: " + response.statusCode() + " " + response.body());
        }

        JsonNode json = objectMapper.readTree(response.body());
        return json.get("data").get("token").asText();
    }

    /** 发送带 Bearer token 的 REST 请求 */
    protected java.net.http.HttpResponse<String> sendRestRequest(
            String method, String path, String token, String body) throws Exception {
        java.net.http.HttpClient client = java.net.http.HttpClient.newHttpClient();
        java.net.http.HttpRequest.Builder builder =
                java.net.http.HttpRequest.newBuilder()
                        .uri(URI.create(BASE_URL + path))
                        .header("Content-Type", "application/json")
                        .header("Authorization", "Bearer " + token);

        if (body != null) {
            builder.method(method, java.net.http.HttpRequest.BodyPublishers.ofString(body));
        } else {
            builder.method(method, java.net.http.HttpRequest.BodyPublishers.noBody());
        }

        return client.send(builder.build(), java.net.http.HttpResponse.BodyHandlers.ofString());
    }

    /** 建立 WebSocket 连接并返回消息收集器 */
    protected TestWebSocketClient connectWebSocket(String token) throws Exception {
        TestWebSocketClient client = new TestWebSocketClient();
        URI uri = new URI(WS_URL + "?token=" + token);

        jakarta.websocket.WebSocketContainer container = ContainerProvider.getWebSocketContainer();

        // 设置超时
        container.setDefaultMaxSessionIdleTimeout(DEFAULT_TIMEOUT_SECONDS * 1000 * 6);

        Session session = container.connectToServer(client, uri);
        client.setSession(session);

        // 等待连接建立
        if (!client.awaitConnected(DEFAULT_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            throw new RuntimeException("WebSocket connection timeout");
        }

        return client;
    }

    /** 尝试连接 WebSocket（预期失败） */
    protected boolean tryConnectWebSocketShouldFail(String token) {
        try {
            TestWebSocketClient client = new TestWebSocketClient();
            URI uri = new URI(WS_URL + "?token=" + token);

            jakarta.websocket.WebSocketContainer container =
                    ContainerProvider.getWebSocketContainer();

            Session session = container.connectToServer(client, uri);
            client.setSession(session);

            // 等待连接结果
            boolean connected = client.awaitConnected(3, TimeUnit.SECONDS);
            if (!connected) {
                return true; // 握手失败，符合预期
            }

            // 连接成功了但可能很快被关闭
            Thread.sleep(500);
            return !client.isOpen();
        } catch (Exception e) {
            return true; // 连接抛异常，符合预期
        }
    }

    /** WebSocket 测试客户端 收集所有收到的消息，支持等待特定类型的消息 */
    @ClientEndpoint
    public static class TestWebSocketClient {
        private Session session;
        private final List<String> receivedMessages = new ArrayList<>();
        private final CountDownLatch connectLatch = new CountDownLatch(1);
        private final AtomicReference<CloseReason> closeReason = new AtomicReference<>();

        public void setSession(Session session) {
            this.session = session;
        }

        @OnOpen
        public void onOpen(Session session) {
            this.session = session;
            connectLatch.countDown();
        }

        @OnMessage
        public void onMessage(String message) {
            synchronized (receivedMessages) {
                receivedMessages.add(message);
                receivedMessages.notifyAll();
            }
        }

        @OnClose
        public void onClose(Session session, CloseReason reason) {
            closeReason.set(reason);
            synchronized (receivedMessages) {
                receivedMessages.notifyAll();
            }
        }

        public boolean awaitConnected(long timeout, TimeUnit unit) throws InterruptedException {
            return connectLatch.await(timeout, unit);
        }

        public void sendMessage(String message) throws Exception {
            if (session != null && session.isOpen()) {
                session.getBasicRemote().sendText(message);
            }
        }

        public void sendJson(String type, java.util.Map<String, Object> fields) throws Exception {
            com.fasterxml.jackson.databind.node.ObjectNode node = objectMapper.createObjectNode();
            node.put("type", type);
            for (var entry : fields.entrySet()) {
                if (entry.getValue() instanceof String s) {
                    node.put(entry.getKey(), s);
                } else if (entry.getValue() instanceof Number n) {
                    node.put(entry.getKey(), n.doubleValue());
                } else if (entry.getValue() instanceof Boolean b) {
                    node.put(entry.getKey(), b);
                }
            }
            sendMessage(objectMapper.writeValueAsString(node));
        }

        /** 等待收到指定类型的消息，返回完整的 JSON */
        public String waitForMessageType(String type, long timeoutSeconds)
                throws InterruptedException {
            long deadline = System.currentTimeMillis() + timeoutSeconds * 1000;
            synchronized (receivedMessages) {
                while (System.currentTimeMillis() < deadline) {
                    for (String msg : receivedMessages) {
                        try {
                            JsonNode json = objectMapper.readTree(msg);
                            if (json.has("type") && type.equals(json.get("type").asText())) {
                                return msg;
                            }
                        } catch (Exception ignored) {
                        }
                    }
                    long remaining = deadline - System.currentTimeMillis();
                    if (remaining > 0) {
                        receivedMessages.wait(remaining);
                    }
                }
            }
            return null; // 超时
        }

        /** 等待收到任意消息 */
        public String waitForAnyMessage(long timeoutSeconds) throws InterruptedException {
            long deadline = System.currentTimeMillis() + timeoutSeconds * 1000;
            synchronized (receivedMessages) {
                while (receivedMessages.isEmpty() && System.currentTimeMillis() < deadline) {
                    long remaining = deadline - System.currentTimeMillis();
                    if (remaining > 0) {
                        receivedMessages.wait(remaining);
                    }
                }
                return receivedMessages.isEmpty()
                        ? null
                        : receivedMessages.get(receivedMessages.size() - 1);
            }
        }

        public List<String> getReceivedMessages() {
            synchronized (receivedMessages) {
                return new ArrayList<>(receivedMessages);
            }
        }

        public boolean isOpen() {
            return session != null && session.isOpen();
        }

        public CloseReason getCloseReason() {
            return closeReason.get();
        }

        public void close() throws Exception {
            if (session != null && session.isOpen()) {
                session.close();
            }
        }
    }
}
