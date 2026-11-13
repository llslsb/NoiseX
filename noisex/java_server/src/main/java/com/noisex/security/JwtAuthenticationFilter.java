package com.noisex.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.noisex.exception.ErrorCode;
import com.noisex.model.dto.ApiResponse;
import com.noisex.model.repository.UserProfileRepository;
import com.noisex.util.RedisKeys;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

@Slf4j
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenProvider jwtTokenProvider;
    private final ObjectMapper objectMapper;
    private final StringRedisTemplate stringRedisTemplate;
    private final UserProfileRepository userProfileRepository;

    @Override
    protected void doFilterInternal(
            HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String token = extractToken(request);

        if (StringUtils.hasText(token)) {
            try {
                String userId = jwtTokenProvider.validateTokenAndGetUuid(token);

                Boolean isBlacklisted =
                        stringRedisTemplate.opsForSet().isMember(RedisKeys.JWT_BLACKLIST, token);
                if (Boolean.TRUE.equals(isBlacklisted)) {
                    sendUnauthorizedResponse(
                            response, ErrorCode.TOKEN_EXPIRED.getCode(), "Token 已失效");
                    return;
                }

                // 管理员封禁标记：同一匿名身份即使重新注册拿到新 token，封禁期内（7 天 TTL）也全部拒绝
                Boolean isBanned =
                        stringRedisTemplate.hasKey(RedisKeys.USER_BANNED_PREFIX + userId);
                if (Boolean.TRUE.equals(isBanned)) {
                    sendUnauthorizedResponse(response, ErrorCode.TOKEN_EXPIRED.getCode(), "账号已被封禁");
                    return;
                }

                List<GrantedAuthority> authorities = new ArrayList<>();
                authorities.add(new SimpleGrantedAuthority("ROLE_USER"));
                userProfileRepository
                        .findById(userId)
                        .ifPresent(
                                profile -> {
                                    if ("ADMIN".equals(profile.getRole())) {
                                        authorities.add(new SimpleGrantedAuthority("ROLE_ADMIN"));
                                    }
                                });

                UsernamePasswordAuthenticationToken authentication =
                        new UsernamePasswordAuthenticationToken(userId, null, authorities);
                authentication.setDetails(
                        new WebAuthenticationDetailsSource().buildDetails(request));
                SecurityContextHolder.getContext().setAuthentication(authentication);
            } catch (Exception e) {
                // 关键修复：验证失败（过期、签名错误、格式错误等）必须直接返回 401。
                // 旧实现仅 log.debug 后继续 filterChain，SecurityContext 为空，Spring 的
                // AnonymousAuthenticationFilter 会把 principal 填成 "anonymousUser"，而
                // SecurityConfig 的 .authenticated() 居然放行匿名 principal，导致过期 token
                // 仍能调用 /api/sonar/listen 等接口，listener 以 anonymousUser 注册，
                // 后续 sendToUser("anonymousUser") 找不到 WS session 静默失败 → 声呐收不到。
                log.warn("JWT validation failed, rejecting request: {}", e.getMessage());
                sendUnauthorizedResponse(
                        response, ErrorCode.TOKEN_EXPIRED.getCode(), "Token 无效或已过期");
                return;
            }
        }

        filterChain.doFilter(request, response);
    }

    private void sendUnauthorizedResponse(HttpServletResponse response, int code, String message)
            throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        ApiResponse<Void> apiResponse = ApiResponse.error(code, message);
        response.getWriter().write(objectMapper.writeValueAsString(apiResponse));
    }

    private String extractToken(HttpServletRequest request) {
        String bearerToken = request.getHeader("Authorization");
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }
        return null;
    }
}
