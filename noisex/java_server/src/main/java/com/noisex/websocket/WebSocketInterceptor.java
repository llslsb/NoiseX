package com.noisex.websocket;

import com.noisex.security.JwtTokenProvider;
import com.noisex.util.RedisKeys;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.ServerHttpRequest;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.server.HandshakeInterceptor;
import org.springframework.web.util.UriComponentsBuilder;

@Slf4j
@Component
@RequiredArgsConstructor
public class WebSocketInterceptor implements HandshakeInterceptor {

    private final JwtTokenProvider jwtTokenProvider;
    private final StringRedisTemplate stringRedisTemplate;

    @Override
    public boolean beforeHandshake(
            ServerHttpRequest request,
            ServerHttpResponse response,
            WebSocketHandler wsHandler,
            Map<String, Object> attributes) {
        // 2026-11-03 修复（勿回退）：beforeHandshake 返回 false 时若不设置状态码，
        // Tomcat 会以 HTTP 200 空响应收尾——客户端把拒绝误读为"升级头被代理剥掉"，
        // 无从判断是 token 问题（真实案例：换服务器后旧 token 被拒，排查半小时）。
        // 所有拒绝分支统一回 401，与 REST 侧 JwtAuthenticationFilter 的未认证语义对齐。
        String query = request.getURI().getQuery();
        if (query == null) {
            log.warn("WebSocket handshake rejected: no query string");
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            return false;
        }

        Map<String, String> params =
                UriComponentsBuilder.fromUri(request.getURI())
                        .build()
                        .getQueryParams()
                        .toSingleValueMap();

        String token = params.get("token");
        if (token == null || token.isBlank()) {
            log.warn("WebSocket handshake rejected: no token");
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            return false;
        }

        try {
            String userId = jwtTokenProvider.validateTokenAndGetUuid(token);

            // 与 REST 侧 JwtAuthenticationFilter 对齐：token 拉黑或用户被封禁一律拒绝重连，
            // 保证管理员封禁后客户端"断线重连"这条恢复路径也被封死
            Boolean isBlacklisted =
                    stringRedisTemplate.opsForSet().isMember(RedisKeys.JWT_BLACKLIST, token);
            Boolean isBanned = stringRedisTemplate.hasKey(RedisKeys.USER_BANNED_PREFIX + userId);
            if (Boolean.TRUE.equals(isBlacklisted) || Boolean.TRUE.equals(isBanned)) {
                log.warn("WebSocket handshake rejected: blacklisted or banned, userId={}", userId);
                response.setStatusCode(HttpStatus.UNAUTHORIZED);
                return false;
            }

            attributes.put("userId", userId);
            return true;
        } catch (Exception e) {
            log.warn("WebSocket handshake rejected: invalid token - {}", e.getMessage());
            response.setStatusCode(HttpStatus.UNAUTHORIZED);
            return false;
        }
    }

    @Override
    public void afterHandshake(
            ServerHttpRequest request,
            ServerHttpResponse response,
            WebSocketHandler wsHandler,
            Exception exception) {
        // no-op
    }
}
