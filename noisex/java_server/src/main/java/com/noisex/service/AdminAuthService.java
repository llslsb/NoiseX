package com.noisex.service;

import com.noisex.exception.BusinessException;
import com.noisex.exception.ErrorCode;
import com.noisex.exception.RateLimitException;
import com.noisex.model.dto.AdminLoginRequest;
import com.noisex.model.dto.AdminLoginResponse;
import com.noisex.model.entity.AdminAccountEntity;
import com.noisex.model.entity.UserProfileEntity;
import com.noisex.model.repository.AdminAccountRepository;
import com.noisex.model.repository.UserProfileRepository;
import com.noisex.security.JwtTokenProvider;
import com.noisex.util.RedisKeys;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.HexFormat;
import java.util.Locale;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class AdminAuthService {

    private final AdminAccountRepository adminAccountRepository;
    private final UserProfileRepository userProfileRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider jwtTokenProvider;
    private final StringRedisTemplate stringRedisTemplate;

    @Value("${noisex.admin.jwt-expiration:7200000}")
    private long adminJwtExpiration;

    @Value("${noisex.admin.login.max-attempts:5}")
    private int maxLoginAttempts;

    @Value("${noisex.admin.login.window-seconds:900}")
    private long loginWindowSeconds;

    private static final String ADMIN_LOGIN_RATE_PREFIX = RedisKeys.ADMIN_LOGIN_RATE_PREFIX;
    private static final String INVALID_CREDENTIALS = "用户名或密码错误";

    public AdminLoginResponse login(AdminLoginRequest request, String clientIp) {
        String username = normalizeUsername(request.getUsername());
        String rateKey = buildRateKey(clientIp, username);
        ensureNotRateLimited(rateKey);

        AdminAccountEntity adminAccount =
                adminAccountRepository.findByUsername(username).orElse(null);
        if (adminAccount == null
                || !adminAccount.isEnabled()
                || !passwordEncoder.matches(request.getPassword(), adminAccount.getPasswordHash())
                || !isLinkedAdminProfile(adminAccount.getUserId())) {
            log.warn("Admin login failed: username={}, ip={}", username, sanitizeIp(clientIp));
            recordFailedAttempt(rateKey);
            throw new BusinessException(ErrorCode.UNAUTHORIZED, INVALID_CREDENTIALS);
        }

        stringRedisTemplate.delete(rateKey);
        String token = jwtTokenProvider.generateToken(adminAccount.getUserId(), adminJwtExpiration);
        long now = System.currentTimeMillis();
        adminAccount.setLastLoginAt(now);
        adminAccount.setUpdatedAt(now);
        adminAccountRepository.save(adminAccount);

        log.info("Admin login success: username={}", username);
        return new AdminLoginResponse(token, adminJwtExpiration, adminAccount.getId(), username);
    }

    private String normalizeUsername(String username) {
        return username.trim().toLowerCase(Locale.ROOT);
    }

    private boolean isLinkedAdminProfile(String userId) {
        return userProfileRepository
                .findById(userId)
                .map(UserProfileEntity::getRole)
                .filter("ADMIN"::equals)
                .isPresent();
    }

    private void ensureNotRateLimited(String rateKey) {
        String value = stringRedisTemplate.opsForValue().get(rateKey);
        if (value == null) {
            return;
        }
        try {
            if (Integer.parseInt(value) >= maxLoginAttempts) {
                throw new RateLimitException("登录尝试过多，请稍后再试");
            }
        } catch (NumberFormatException e) {
            stringRedisTemplate.delete(rateKey);
        }
    }

    private void recordFailedAttempt(String rateKey) {
        Long attempts = stringRedisTemplate.opsForValue().increment(rateKey);
        if (attempts != null && attempts == 1L) {
            stringRedisTemplate.expire(rateKey, Duration.ofSeconds(loginWindowSeconds));
        }
    }

    private String buildRateKey(String clientIp, String username) {
        return ADMIN_LOGIN_RATE_PREFIX + sanitizeIp(clientIp) + ":" + sha256(username);
    }

    private String sanitizeIp(String clientIp) {
        if (clientIp == null || clientIp.isBlank()) {
            return "unknown";
        }
        return clientIp.replace(':', '_').replace('.', '_');
    }

    private String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }
}
