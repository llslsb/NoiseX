package com.noisex.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.noisex.model.repository.UserProfileRepository;
import com.noisex.util.RedisKeys;
import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;

/** 管理员封禁/Token 黑名单在 REST 过滤器层的拦截行为（AdminService.banned 链路的消费端） */
@ExtendWith(MockitoExtension.class)
class JwtAuthenticationFilterTest {

    @Mock private JwtTokenProvider jwtTokenProvider;

    @Mock private StringRedisTemplate stringRedisTemplate;

    @Mock private UserProfileRepository userProfileRepository;

    @Mock private FilterChain filterChain;

    private JwtAuthenticationFilter filter;

    @BeforeEach
    void setUp() {
        filter =
                new JwtAuthenticationFilter(
                        jwtTokenProvider,
                        new ObjectMapper(),
                        stringRedisTemplate,
                        userProfileRepository);
        SecurityContextHolder.clearContext();
    }

    private MockHttpServletRequest request(String token) {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("Authorization", "Bearer " + token);
        return request;
    }

    @Test
    void validToken_notBlacklistedNotBanned_shouldProceed() throws Exception {
        when(jwtTokenProvider.validateTokenAndGetUuid("jwt-ok")).thenReturn("user-ok");
        SetOperations<String, String> setOps = mock(SetOperations.class);
        when(stringRedisTemplate.opsForSet()).thenReturn(setOps);
        when(setOps.isMember(RedisKeys.JWT_BLACKLIST, "jwt-ok")).thenReturn(false);
        when(stringRedisTemplate.hasKey(RedisKeys.USER_BANNED_PREFIX + "user-ok"))
                .thenReturn(false);

        MockHttpServletRequest request = request("jwt-ok");
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilterInternal(request, response, filterChain);

        verify(filterChain).doFilter(request, response);
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNotNull();
        assertThat(response.getStatus()).isEqualTo(200);
    }

    @Test
    void bannedUser_shouldRejectWith401AndNotProceed() throws Exception {
        when(jwtTokenProvider.validateTokenAndGetUuid("jwt-banned")).thenReturn("user-banned");
        SetOperations<String, String> setOps = mock(SetOperations.class);
        when(stringRedisTemplate.opsForSet()).thenReturn(setOps);
        when(setOps.isMember(RedisKeys.JWT_BLACKLIST, "jwt-banned")).thenReturn(false);
        when(stringRedisTemplate.hasKey(RedisKeys.USER_BANNED_PREFIX + "user-banned"))
                .thenReturn(true);

        MockHttpServletRequest request = request("jwt-banned");
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilterInternal(request, response, filterChain);

        assertThat(response.getStatus()).isEqualTo(401);
        assertThat(response.getContentAsString()).contains("账号已被封禁");
        verify(filterChain, never()).doFilter(request, response);
        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
    }

    @Test
    void blacklistedToken_shouldRejectWith401AndNotProceed() throws Exception {
        when(jwtTokenProvider.validateTokenAndGetUuid("jwt-dead")).thenReturn("user-x");
        SetOperations<String, String> setOps = mock(SetOperations.class);
        when(stringRedisTemplate.opsForSet()).thenReturn(setOps);
        when(setOps.isMember(RedisKeys.JWT_BLACKLIST, "jwt-dead")).thenReturn(true);

        MockHttpServletRequest request = request("jwt-dead");
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilterInternal(request, response, filterChain);

        assertThat(response.getStatus()).isEqualTo(401);
        verifyNoInteractions(filterChain);
        verify(stringRedisTemplate, never()).hasKey(anyString());
    }
}
