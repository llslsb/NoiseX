package com.noisex.security;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class JwtTokenProviderTest {

    private JwtTokenProvider jwtTokenProvider;

    @BeforeEach
    void setUp() {
        jwtTokenProvider = new JwtTokenProvider();
        // 使用足够长的 Base64 密钥（256-bit for HS256）
        ReflectionTestUtils.setField(
                jwtTokenProvider,
                "jwtSecret",
                "dGVzdC1zZWNyZXQta2V5LWZvci1ub2lzZXgtanVuaXQtdGVzdHMtb25seQ==");
        ReflectionTestUtils.setField(jwtTokenProvider, "jwtExpiration", 86400000L);
    }

    @Test
    void generateToken_shouldReturnValidJwt() {
        String token = jwtTokenProvider.generateToken("test-uuid");
        assertNotNull(token);
        assertFalse(token.isEmpty());
        assertTrue(token.split("\\.").length == 3, "JWT should have 3 parts");
    }

    @Test
    void validateTokenAndGetUuid_shouldReturnOriginalUuid() {
        String uuid = "550e8400-e29b-41d4-a716-446655440000";
        String token = jwtTokenProvider.generateToken(uuid);
        String result = jwtTokenProvider.validateTokenAndGetUuid(token);
        assertEquals(uuid, result);
    }

    @Test
    void validateTokenAndGetUuid_withInvalidToken_shouldThrow() {
        assertThrows(
                Exception.class,
                () -> {
                    jwtTokenProvider.validateTokenAndGetUuid("invalid.token.here");
                });
    }

    @Test
    void getExpiration_shouldReturnConfiguredValue() {
        assertEquals(86400000L, jwtTokenProvider.getExpiration());
    }
}
