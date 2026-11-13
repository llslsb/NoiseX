package com.noisex.controller;

import com.noisex.model.dto.ApiResponse;
import com.noisex.model.dto.AuthRequest;
import com.noisex.model.dto.AuthResponse;
import com.noisex.service.AdminService;
import com.noisex.service.AuthService;
import com.noisex.util.SecurityUtils;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
@Tag(name = "认证", description = "匿名认证接口")
public class AuthController {

    private final AuthService authService;
    private final AdminService adminService;

    @PostMapping("/register")
    @Operation(summary = "匿名注册", description = "客户端本地生成UUID，服务端返回JWT")
    public ResponseEntity<ApiResponse<AuthResponse>> register(
            @RequestBody @Valid AuthRequest request) {
        AuthResponse response = authService.generateToken(request.getAnonymousUuid());
        return ResponseEntity.ok(ApiResponse.success(response));
    }

    @PostMapping("/refresh")
    @Operation(summary = "刷新Token")
    public ResponseEntity<ApiResponse<AuthResponse>> refresh() {
        String userId = SecurityUtils.getCurrentUserId();
        AuthResponse response = authService.refreshToken(userId);
        return ResponseEntity.ok(ApiResponse.success(response));
    }

    @PostMapping("/logout")
    @Operation(summary = "登出", description = "将当前JWT加入黑名单")
    public ResponseEntity<ApiResponse<Void>> logout(HttpServletRequest request) {
        String bearerToken = request.getHeader("Authorization");
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            String token = bearerToken.substring(7);
            adminService.blacklistToken(token);
        }
        return ResponseEntity.ok(ApiResponse.success());
    }
}
