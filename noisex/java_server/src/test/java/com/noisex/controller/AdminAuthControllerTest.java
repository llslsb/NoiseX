package com.noisex.controller;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.model.dto.AdminLoginRequest;
import com.noisex.model.dto.AdminLoginResponse;
import com.noisex.model.dto.ApiResponse;
import com.noisex.service.AdminAuthService;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class AdminAuthControllerTest {

    @Mock private AdminAuthService adminAuthService;

    @Mock private HttpServletRequest httpServletRequest;

    @InjectMocks private AdminAuthController adminAuthController;

    @Test
    void login_shouldReturnAdminLoginResponse() {
        AdminLoginRequest request = new AdminLoginRequest();
        request.setUsername("admin");
        request.setPassword("password123");
        AdminLoginResponse loginResponse =
                new AdminLoginResponse("admin-jwt", 7200000L, "admin-id", "admin");
        when(httpServletRequest.getRemoteAddr()).thenReturn("127.0.0.1");
        when(adminAuthService.login(request, "127.0.0.1")).thenReturn(loginResponse);

        ResponseEntity<ApiResponse<AdminLoginResponse>> response =
                adminAuthController.login(request, httpServletRequest);

        assertEquals(200, response.getStatusCode().value());
        assertNotNull(response.getBody());
        assertEquals("admin-jwt", response.getBody().getData().getToken());
        verify(adminAuthService).login(request, "127.0.0.1");
    }

    @Test
    void login_shouldUseRemoteAddress() {
        AdminLoginRequest request = new AdminLoginRequest();
        request.setUsername("admin");
        request.setPassword("password123");
        AdminLoginResponse loginResponse =
                new AdminLoginResponse("admin-jwt", 7200000L, "admin-id", "admin");
        when(httpServletRequest.getRemoteAddr()).thenReturn("203.0.113.10");
        when(adminAuthService.login(request, "203.0.113.10")).thenReturn(loginResponse);

        ResponseEntity<ApiResponse<AdminLoginResponse>> response =
                adminAuthController.login(request, httpServletRequest);

        assertEquals(200, response.getStatusCode().value());
        verify(adminAuthService).login(request, "203.0.113.10");
    }
}
