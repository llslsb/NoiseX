package com.noisex.controller;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.model.dto.AuthRequest;
import com.noisex.model.dto.AuthResponse;
import com.noisex.service.AuthService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class AuthControllerTest {

    @Mock private AuthService authService;

    @InjectMocks private AuthController authController;

    @BeforeEach
    void setUp() {
        // SecurityUtils uses SecurityContextHolder — not needed for register
    }

    @Test
    void register_shouldReturnToken() {
        AuthResponse authResponse = new AuthResponse("jwt-token", 86400000L);
        when(authService.generateToken("test-uuid")).thenReturn(authResponse);

        AuthRequest request = new AuthRequest();
        request.setAnonymousUuid("test-uuid");

        ResponseEntity<?> response = authController.register(request);

        assertEquals(200, response.getStatusCode().value());
        verify(authService).generateToken("test-uuid");
    }

    @Test
    void refresh_shouldCallRefreshToken() {
        // Set security context for SecurityUtils
        org.springframework.security.authentication.UsernamePasswordAuthenticationToken auth =
                new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(
                        "user-123", null, java.util.List.of());
        org.springframework.security.core.context.SecurityContextHolder.getContext()
                .setAuthentication(auth);

        AuthResponse authResponse = new AuthResponse("new-token", 86400000L);
        when(authService.refreshToken("user-123")).thenReturn(authResponse);

        ResponseEntity<?> response = authController.refresh();

        assertEquals(200, response.getStatusCode().value());
        verify(authService).refreshToken("user-123");
    }

    @AfterEach
    void tearDown() {
        org.springframework.security.core.context.SecurityContextHolder.clearContext();
    }
}
