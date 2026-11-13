package com.noisex.util;

import com.noisex.exception.BusinessException;
import com.noisex.exception.ErrorCode;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

public final class SecurityUtils {

    /**
     * Spring Security 在无认证请求时填充的匿名 principal 名称。
     *
     * <p>正常情况下 {@link com.noisex.security.JwtAuthenticationFilter} 会在 JWT 验证失败时直接返回 401， 匿名
     * principal 不应到达业务层。但作为纵深防御，仍在此拦截：任何业务接口拿到 anonymousUser 都说明上游认证链路有漏网，必须拒绝，否则会出现"过期 token 降级为
     * anonymousUser 仍能注册 listener / 接受声呐"的严重问题。
     */
    private static final String ANONYMOUS_USER = "anonymousUser";

    private SecurityUtils() {}

    public static String getCurrentUserId() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || auth.getName() == null) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED);
        }
        String userId = auth.getName();
        // 纵深防御：拦截匿名 principal（JwtAuthFilter 漏网时兜底）
        if (ANONYMOUS_USER.equals(userId)) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED);
        }
        return userId;
    }
}
