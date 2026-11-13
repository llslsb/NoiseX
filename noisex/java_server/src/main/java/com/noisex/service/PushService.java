package com.noisex.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.auth.oauth2.AccessToken;
import com.google.auth.oauth2.GoogleCredentials;
import com.noisex.util.RedisKeys;
import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.http.*;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

@Slf4j
@Service
@RequiredArgsConstructor
public class PushService {

    private final RedisTemplate<String, Object> redisTemplate;
    private final ObjectMapper objectMapper;

    private static final String PUSH_TOKEN_PREFIX = RedisKeys.PUSH_TOKEN_PREFIX;
    private static final String PUSH_CHANNEL_PREFIX = "noisex:push:channel:";
    private static final String ONLINE_KEY = RedisKeys.ONLINE;
    private static final String FCM_ACCESS_TOKEN_KEY = "noisex:push:fcm_access_token";

    private final RestTemplate restTemplate = createRestTemplate();

    private static RestTemplate createRestTemplate() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5000);
        factory.setReadTimeout(10000);
        return new RestTemplate(factory);
    }

    @Value("${noisex.push.enabled:false}")
    private boolean pushEnabled;

    // 2026-11-05 双平台 v3 统一实锤（勿回退）：鸿蒙与安卓的 Push REST API 都只认
    // v3 接口 + 各自项目的服务账号密钥自签 JWT（PS256）；v2 旧接口与 OAuth
    // client_credentials（client_id/client_secret 换 token）在两平台都被
    // 80200001 拒收，已整体废弃。密钥 JSON 从 AGC API Console 下载，只放
    // 服务器（600），严禁入库或进日志。
    @Value("${noisex.push.project-id:}")
    private String pushProjectId;

    @Value("${noisex.push.ohos.service-account-key-file:}")
    private String ohosServiceAccountKeyFile;

    @Value("${noisex.push.android.project-id:}")
    private String androidProjectId;

    @Value("${noisex.push.android.service-account-key-file:}")
    private String androidServiceAccountKeyFile;

    // category 必须与 AGC 已批自分类权益类目一致（本应用=IM 即时聊天）；
    // 不带或错配会被按资讯营销类处理：静默通知+频控，表现为"收不到推送"（勿删）
    @Value("${noisex.push.category:IM}")
    private String pushCategory;

    // 调测期置 true：测试消息不受频控（单项目每日 1000 条），通道验证后关掉
    @Value("${noisex.push.test-message:false}")
    private boolean pushTestMessage;

    @Value("${noisex.push.fcm.service-account-key:}")
    private String fcmServiceAccountKey;

    @Value("${noisex.push.fcm.project-id:}")
    private String fcmProjectId;

    public void registerToken(String userId, String pushToken, String channel) {
        String tokenKey = PUSH_TOKEN_PREFIX + userId;
        String channelKey = PUSH_CHANNEL_PREFIX + userId;
        redisTemplate.opsForValue().set(tokenKey, pushToken, Duration.ofDays(30));
        redisTemplate.opsForValue().set(channelKey, channel, Duration.ofDays(30));
        log.info("Push token registered for user: {}, channel: {}", userId, channel);
    }

    public String getToken(String userId) {
        String key = PUSH_TOKEN_PREFIX + userId;
        Object val = redisTemplate.opsForValue().get(key);
        return val != null ? val.toString() : null;
    }

    public String getChannel(String userId) {
        String key = PUSH_CHANNEL_PREFIX + userId;
        Object val = redisTemplate.opsForValue().get(key);
        return val != null ? val.toString() : "hms";
    }

    public void unregisterToken(String userId) {
        redisTemplate.delete(PUSH_TOKEN_PREFIX + userId);
        redisTemplate.delete(PUSH_CHANNEL_PREFIX + userId);
        log.info("Push token unregistered for user: {}", userId);
    }

    @Async("pushTaskExecutor")
    public void sendPush(String userId, String title, String body) {
        sendPush(userId, title, body, null);
    }

    @Async("pushTaskExecutor")
    public void sendPush(String userId, String title, String body, Map<String, String> data) {
        if (!pushEnabled) {
            log.debug("Push disabled, skipping notification for user: {}", userId);
            return;
        }

        Boolean isOnline = redisTemplate.opsForSet().isMember(ONLINE_KEY, userId);
        if (Boolean.TRUE.equals(isOnline)) {
            return;
        }

        String dedupeKey = "noisex:push:dedup:" + userId;
        Boolean dedupeSet =
                redisTemplate.opsForValue().setIfAbsent(dedupeKey, "1", Duration.ofSeconds(30));
        if (Boolean.FALSE.equals(dedupeSet)) {
            log.debug("Push deduplicated for user: {}", userId);
            return;
        }

        String pushToken = getToken(userId);
        if (pushToken == null || pushToken.isEmpty()) {
            log.debug("No push token for user: {}", userId);
            return;
        }

        String channel = getChannel(userId);
        // 2026-11-04 双通道路由（勿回退）：channel=ohos（鸿蒙 NEXT）与 channel=hms
        // （安卓 HMS Core）分属两个 AGC 项目，各用各的项目 ID 与服务账号密钥；
        // 老客户端若仍报 hms 而设备其实是鸿蒙，会打到安卓项目侧报 token 无效，
        // 客户端按平台上报正确 channel 后自愈
        switch (channel) {
            case "fcm" -> sendViaFcm(userId, pushToken, title, body, data);
            case "ohos" -> sendViaHuaweiV3(
                    userId,
                    pushToken,
                    title,
                    body,
                    data,
                    pushProjectId,
                    ohosServiceAccountKeyFile,
                    "OHOS");
            case "hms" -> sendViaHuaweiV3(
                    userId,
                    pushToken,
                    title,
                    body,
                    data,
                    androidProjectId,
                    androidServiceAccountKeyFile,
                    "Android HMS");
            default -> {
                log.warn("Unknown push channel: {} for user: {}, trying HMS", channel, userId);
                sendViaHuaweiV3(
                        userId,
                        pushToken,
                        title,
                        body,
                        data,
                        androidProjectId,
                        androidServiceAccountKeyFile,
                        "Android HMS");
            }
        }
    }

    /** 鸿蒙（新 AGC 项目）通道：v3 接口 + payload.notification 报文，杀死状态由系统通知栏展示。 */
    private void sendViaOhos(
            String userId, String pushToken, String title, String body, Map<String, String> data) {
        sendViaHuaweiV3(
                userId,
                pushToken,
                title,
                body,
                data,
                pushProjectId,
                ohosServiceAccountKeyFile,
                "OHOS");
    }

    /**
     * 安卓 HMS 通道：2026-11-05 实锤 v2/{appId} + OAuth client_credentials 已被华为 作废（80200001），安卓与鸿蒙统一走
     * v3/{projectId} + 服务账号自签 JWT——只是 项目 ID 与密钥文件不同。
     */
    private void sendViaHms(
            String userId, String pushToken, String title, String body, Map<String, String> data) {
        sendViaHuaweiV3(
                userId,
                pushToken,
                title,
                body,
                data,
                androidProjectId,
                androidServiceAccountKeyFile,
                "Android HMS");
    }

    /**
     * 华为 Push v3 统一发送核心（鸿蒙/安卓共用）： 服务账号密钥自签 JWT（PS256）放 Authorization 头 + push-type:0 通知消息头 +
     * payload.notification 报文。通知消息由 Push Kit 通道下发，应用被杀死也由 系统通知栏展示，这正是离线补推的立身之本（2026-11-04/05
     * 改造，勿回退）。
     */
    private void sendViaHuaweiV3(
            String userId,
            String pushToken,
            String title,
            String body,
            Map<String, String> data,
            String projectId,
            String serviceAccountKeyFile,
            String channelLabel) {
        // 配置不全时快速失败，避免拿空配置打线上接口还白耗三次重试
        if (projectId == null
                || projectId.isBlank()
                || serviceAccountKeyFile == null
                || serviceAccountKeyFile.isBlank()) {
            log.warn(
                    "{} push not configured (project-id/service-account-key-file missing),"
                            + " skip notification for user: {}",
                    channelLabel,
                    userId);
            return;
        }

        // 鉴权（勿回退，80200001 实锤）：服务账号密钥自签 JWT 直接放 Authorization 头，
        // 没有 OAuth 换 token 步骤；推送频率低，按官方建议每次现签（1h 内有效）
        String pushJwt;
        try {
            pushJwt =
                    HuaweiPushJwtFactory.buildJwt(
                            HuaweiPushJwtFactory.parse(
                                    Files.readString(Path.of(serviceAccountKeyFile))),
                            Instant.now());
        } catch (Exception e) {
            log.error(
                    "{} push JWT build failed (key file: {}): {}",
                    channelLabel,
                    serviceAccountKeyFile,
                    e.getMessage());
            return;
        }

        int maxRetries = 3;
        for (int attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                String url = "https://push-api.cloud.huawei.com/v3/" + projectId + "/messages:send";

                HttpHeaders headers = new HttpHeaders();
                headers.setContentType(MediaType.APPLICATION_JSON);
                headers.set("Authorization", "Bearer " + pushJwt);
                headers.set("push-type", "0");

                Map<String, Object> notification = new HashMap<>();
                notification.put("category", pushCategory);
                notification.put("title", title);
                notification.put("body", body);
                // 点击通知打开应用首页（actionType:0）
                notification.put("clickAction", Map.of("actionType", 0));
                // 服务器只对离线用户补推，前台展示交给 App 内 WS 通道；关掉避免补推时前台双弹
                notification.put("foregroundShow", false);
                // notifyId：同一房间新消息覆盖旧通知，不同房间各占一条；无 roomId 的
                // 系统类通知（如账号安全）按用户维度合并
                String notifyScope =
                        (data != null && data.get("roomId") != null) ? data.get("roomId") : userId;
                notification.put("notifyId", Math.abs(notifyScope.hashCode()));

                Map<String, Object> requestBody = new HashMap<>();
                requestBody.put("payload", Map.of("notification", notification));
                requestBody.put("target", Map.of("token", new String[] {pushToken}));
                Map<String, Object> pushOptions = new HashMap<>();
                // IM 离线补推 1 小时后没有提醒价值，沿用旧 v2 时代的 3600 秒
                pushOptions.put("ttl", 3600);
                if (pushTestMessage) {
                    pushOptions.put("testMessage", true);
                }
                requestBody.put("pushOptions", pushOptions);

                HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);
                ResponseEntity<String> response =
                        restTemplate.exchange(url, HttpMethod.POST, entity, String.class);

                if (response.getStatusCode().is2xxSuccessful()) {
                    log.info("{} push sent to user: {}, title: {}", channelLabel, userId, title);
                    return;
                } else {
                    // v3 拒绝原因（如 category 与自分类权益不符）都在响应体里，只记状态码
                    // 等于没记——排查"收不到推送"时全靠这行日志
                    log.warn(
                            "{} Push API non-2xx: {} body: {} (user: {}, attempt {}/{})",
                            channelLabel,
                            response.getStatusCode(),
                            abbreviate(response.getBody()),
                            userId,
                            attempt,
                            maxRetries);
                }
            } catch (Exception e) {
                log.warn(
                        "{} push failed for user {} (attempt {}/{}): {}",
                        channelLabel,
                        userId,
                        attempt,
                        maxRetries,
                        e.getMessage());
            }

            if (attempt < maxRetries) {
                try {
                    Thread.sleep((long) Math.pow(2, attempt) * 1000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    return;
                }
            }
        }
        log.error("{} push failed after {} retries for user: {}", channelLabel, maxRetries, userId);
    }

    /** 日志用响应体截断：v3 错误体可能携带完整字段，整段打印会刷爆日志行 */
    private static String abbreviate(String s) {
        if (s == null) {
            return "null";
        }
        return s.length() > 300 ? s.substring(0, 300) + "..." : s;
    }

    private void sendViaFcm(
            String userId, String pushToken, String title, String body, Map<String, String> data) {
        try {
            String accessToken = getFcmAccessToken();
            if (accessToken == null) {
                log.warn("Failed to get FCM access token for user: {}", userId);
                return;
            }

            String url =
                    "https://fcm.googleapis.com/v1/projects/" + fcmProjectId + "/messages:send";

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Authorization", "Bearer " + accessToken);

            Map<String, Object> message = new HashMap<>();
            Map<String, Object> notification = new HashMap<>();
            notification.put("title", title);
            notification.put("body", body);
            message.put("token", pushToken);
            message.put("notification", notification);

            if (data != null && !data.isEmpty()) {
                message.put("data", data);
            }

            Map<String, Object> requestBody = Map.of("message", message);

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);
            ResponseEntity<String> response =
                    restTemplate.exchange(url, HttpMethod.POST, entity, String.class);

            if (response.getStatusCode().is2xxSuccessful()) {
                log.info("FCM push sent to user: {}, title: {}", userId, title);
            } else {
                log.warn("FCM push non-2xx: {} for user: {}", response.getStatusCode(), userId);
            }
        } catch (Exception e) {
            log.error("FCM push failed for user {}: {}", userId, e.getMessage());
        }
    }

    private synchronized String getFcmAccessToken() {
        Object cached = redisTemplate.opsForValue().get(FCM_ACCESS_TOKEN_KEY);
        if (cached != null) {
            return cached.toString();
        }

        try {
            if (fcmServiceAccountKey.isEmpty() || fcmProjectId.isEmpty()) {
                log.warn("FCM not configured (missing service account key or project ID)");
                return null;
            }

            GoogleCredentials credentials =
                    GoogleCredentials.fromStream(
                                    new ByteArrayInputStream(fcmServiceAccountKey.getBytes()))
                            .createScoped(
                                    List.of("https://www.googleapis.com/auth/firebase.messaging"));
            AccessToken accessToken = credentials.refreshAccessToken();
            String tokenValue = accessToken.getTokenValue();

            redisTemplate
                    .opsForValue()
                    .set(FCM_ACCESS_TOKEN_KEY, tokenValue, Duration.ofMinutes(50));
            return tokenValue;
        } catch (Exception e) {
            log.error("Failed to get FCM access token: {}", e.getMessage());
        }
        return null;
    }
}
