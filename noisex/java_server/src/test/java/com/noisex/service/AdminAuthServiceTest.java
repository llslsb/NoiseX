package com.noisex.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.exception.BusinessException;
import com.noisex.exception.RateLimitException;
import com.noisex.model.dto.AdminLoginRequest;
import com.noisex.model.dto.AdminLoginResponse;
import com.noisex.model.entity.AdminAccountEntity;
import com.noisex.model.entity.UserProfileEntity;
import com.noisex.model.repository.AdminAccountRepository;
import com.noisex.model.repository.UserProfileRepository;
import com.noisex.security.JwtTokenProvider;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class AdminAuthServiceTest {

    @Mock private AdminAccountRepository adminAccountRepository;

    @Mock private UserProfileRepository userProfileRepository;

    @Mock private PasswordEncoder passwordEncoder;

    @Mock private JwtTokenProvider jwtTokenProvider;

    @Mock private StringRedisTemplate stringRedisTemplate;

    @Mock private ValueOperations<String, String> valueOperations;

    private AdminAuthService adminAuthService;

    @BeforeEach
    void setUp() {
        adminAuthService =
                new AdminAuthService(
                        adminAccountRepository,
                        userProfileRepository,
                        passwordEncoder,
                        jwtTokenProvider,
                        stringRedisTemplate);
        ReflectionTestUtils.setField(adminAuthService, "adminJwtExpiration", 7200000L);
        ReflectionTestUtils.setField(adminAuthService, "maxLoginAttempts", 5);
        ReflectionTestUtils.setField(adminAuthService, "loginWindowSeconds", 900L);
        lenient().when(stringRedisTemplate.opsForValue()).thenReturn(valueOperations);
    }

    @Test
    void login_withValidCredentials_shouldReturnAdminTokenAndUpdateLastLogin() {
        AdminLoginRequest request = request("Admin_User", "correct-password");
        AdminAccountEntity account = adminAccount();
        UserProfileEntity profile = adminProfile();
        when(valueOperations.get(anyString())).thenReturn(null);
        when(adminAccountRepository.findByUsername("admin_user")).thenReturn(Optional.of(account));
        when(passwordEncoder.matches("correct-password", "hash")).thenReturn(true);
        when(userProfileRepository.findById("admin-user-id")).thenReturn(Optional.of(profile));
        when(jwtTokenProvider.generateToken("admin-user-id", 7200000L)).thenReturn("admin-jwt");

        AdminLoginResponse response = adminAuthService.login(request, "127.0.0.1");

        assertEquals("admin-jwt", response.getToken());
        assertEquals(7200000L, response.getExpiresIn());
        assertEquals("admin-account-id", response.getAdminId());
        assertEquals("admin_user", response.getUsername());
        assertNotNull(account.getLastLoginAt());
        verify(stringRedisTemplate).delete(anyString());
        verify(adminAccountRepository).save(account);
    }

    @Test
    void login_withUnknownUsername_shouldThrowUnauthorizedAndRecordFailure() {
        AdminLoginRequest request = request("missing", "password123");
        when(valueOperations.get(anyString())).thenReturn(null);
        when(adminAccountRepository.findByUsername("missing")).thenReturn(Optional.empty());
        when(valueOperations.increment(anyString())).thenReturn(1L);

        BusinessException ex =
                assertThrows(
                        BusinessException.class,
                        () -> adminAuthService.login(request, "127.0.0.1"));

        assertEquals(40101, ex.getCode());
        verify(valueOperations).increment(anyString());
        verify(valueOperations).get(anyString());
    }

    @Test
    void login_withWrongPassword_shouldThrowUnauthorizedAndRecordFailure() {
        AdminLoginRequest request = request("admin", "wrong-password");
        when(valueOperations.get(anyString())).thenReturn(null);
        when(adminAccountRepository.findByUsername("admin"))
                .thenReturn(Optional.of(adminAccount()));
        when(passwordEncoder.matches("wrong-password", "hash")).thenReturn(false);
        when(valueOperations.increment(anyString())).thenReturn(1L);

        BusinessException ex =
                assertThrows(
                        BusinessException.class,
                        () -> adminAuthService.login(request, "127.0.0.1"));

        assertEquals(40101, ex.getCode());
        verify(valueOperations).increment(anyString());
        verify(jwtTokenProvider, never()).generateToken(anyString(), anyLong());
    }

    @Test
    void login_withNonAdminProfile_shouldThrowUnauthorized() {
        AdminLoginRequest request = request("admin", "correct-password");
        UserProfileEntity profile = adminProfile();
        profile.setRole("USER");
        when(valueOperations.get(anyString())).thenReturn(null);
        when(adminAccountRepository.findByUsername("admin"))
                .thenReturn(Optional.of(adminAccount()));
        when(passwordEncoder.matches("correct-password", "hash")).thenReturn(true);
        when(userProfileRepository.findById("admin-user-id")).thenReturn(Optional.of(profile));
        when(valueOperations.increment(anyString())).thenReturn(1L);

        BusinessException ex =
                assertThrows(
                        BusinessException.class,
                        () -> adminAuthService.login(request, "127.0.0.1"));

        assertEquals(40101, ex.getCode());
        verify(jwtTokenProvider, never()).generateToken(anyString(), anyLong());
    }

    @Test
    void login_whenRateLimited_shouldThrowRateLimitWithoutCheckingPassword() {
        AdminLoginRequest request = request("admin", "correct-password");
        when(valueOperations.get(anyString())).thenReturn("5");

        assertThrows(RateLimitException.class, () -> adminAuthService.login(request, "127.0.0.1"));

        verify(adminAccountRepository, never()).findByUsername(anyString());
        verify(passwordEncoder, never()).matches(anyString(), anyString());
    }

    @Test
    void login_withDisabledAccount_shouldThrowUnauthorized() {
        AdminLoginRequest request = request("admin", "correct-password");
        AdminAccountEntity disabledAccount =
                AdminAccountEntity.builder()
                        .id("admin-account-id")
                        .username("admin")
                        .userId("admin-user-id")
                        .passwordHash("hash")
                        .enabled(false)
                        .createdAt(1000L)
                        .updatedAt(1000L)
                        .build();
        when(valueOperations.get(anyString())).thenReturn(null);
        when(adminAccountRepository.findByUsername("admin"))
                .thenReturn(Optional.of(disabledAccount));
        when(valueOperations.increment(anyString())).thenReturn(1L);

        BusinessException ex =
                assertThrows(
                        BusinessException.class,
                        () -> adminAuthService.login(request, "127.0.0.1"));

        assertEquals(40101, ex.getCode());
        verify(passwordEncoder, never()).matches(anyString(), anyString());
    }

    @Test
    void login_withMissingUserProfile_shouldThrowUnauthorized() {
        AdminLoginRequest request = request("admin", "correct-password");
        when(valueOperations.get(anyString())).thenReturn(null);
        when(adminAccountRepository.findByUsername("admin"))
                .thenReturn(Optional.of(adminAccount()));
        when(passwordEncoder.matches("correct-password", "hash")).thenReturn(true);
        when(userProfileRepository.findById("admin-user-id")).thenReturn(Optional.empty());
        when(valueOperations.increment(anyString())).thenReturn(1L);

        BusinessException ex =
                assertThrows(
                        BusinessException.class,
                        () -> adminAuthService.login(request, "127.0.0.1"));

        assertEquals(40101, ex.getCode());
        verify(jwtTokenProvider, never()).generateToken(anyString(), anyLong());
    }

    @Test
    void login_withUppercaseUsername_shouldNormalizeToLowercase() {
        AdminLoginRequest request = request("ADMIN_USER", "correct-password");
        when(valueOperations.get(anyString())).thenReturn(null);
        when(adminAccountRepository.findByUsername("admin_user"))
                .thenReturn(Optional.of(adminAccount()));
        when(passwordEncoder.matches("correct-password", "hash")).thenReturn(true);
        when(userProfileRepository.findById("admin-user-id"))
                .thenReturn(Optional.of(adminProfile()));
        when(jwtTokenProvider.generateToken("admin-user-id", 7200000L)).thenReturn("admin-jwt");

        AdminLoginResponse response = adminAuthService.login(request, "127.0.0.1");

        assertEquals("admin-jwt", response.getToken());
        verify(adminAccountRepository).findByUsername("admin_user");
    }

    @Test
    void login_whenRateKeyHasNonNumericValue_shouldDeleteKeyAndAllowLogin() {
        AdminLoginRequest request = request("admin", "correct-password");
        when(valueOperations.get(anyString())).thenReturn("not-a-number");
        when(stringRedisTemplate.delete(anyString())).thenReturn(true);
        when(adminAccountRepository.findByUsername("admin"))
                .thenReturn(Optional.of(adminAccount()));
        when(passwordEncoder.matches("correct-password", "hash")).thenReturn(true);
        when(userProfileRepository.findById("admin-user-id"))
                .thenReturn(Optional.of(adminProfile()));
        when(jwtTokenProvider.generateToken("admin-user-id", 7200000L)).thenReturn("admin-jwt");

        AdminLoginResponse response = adminAuthService.login(request, "127.0.0.1");

        assertEquals("admin-jwt", response.getToken());
        verify(stringRedisTemplate, atLeast(1)).delete(anyString());
    }

    private AdminLoginRequest request(String username, String password) {
        AdminLoginRequest request = new AdminLoginRequest();
        request.setUsername(username);
        request.setPassword(password);
        return request;
    }

    private AdminAccountEntity adminAccount() {
        return AdminAccountEntity.builder()
                .id("admin-account-id")
                .username("admin")
                .userId("admin-user-id")
                .passwordHash("hash")
                .enabled(true)
                .createdAt(1000L)
                .updatedAt(1000L)
                .build();
    }

    private UserProfileEntity adminProfile() {
        return UserProfileEntity.builder()
                .userId("admin-user-id")
                .role("ADMIN")
                .updatedAt(1000L)
                .build();
    }
}
