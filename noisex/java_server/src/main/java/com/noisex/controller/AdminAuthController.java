package com.noisex.controller;

import com.noisex.model.dto.AdminLoginRequest;
import com.noisex.model.dto.AdminLoginResponse;
import com.noisex.model.dto.ApiResponse;
import com.noisex.service.AdminAuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth/admin")
@RequiredArgsConstructor
@Tag(name = "管理员认证", description = "管理后台账号密码登录")
public class AdminAuthController {

    private final AdminAuthService adminAuthService;

    @PostMapping("/login")
    @Operation(summary = "管理员登录", description = "使用管理员账号密码登录管理后台")
    public ResponseEntity<ApiResponse<AdminLoginResponse>> login(
            @RequestBody @Valid AdminLoginRequest request, HttpServletRequest httpRequest) {
        AdminLoginResponse response = adminAuthService.login(request, getClientIp(httpRequest));
        return ResponseEntity.ok(ApiResponse.success(response));
    }

    private String getClientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        String realIp = request.getHeader("X-Real-IP");
        if (realIp != null && !realIp.isBlank()) {
            return realIp.trim();
        }
        return request.getRemoteAddr();
    }
}
