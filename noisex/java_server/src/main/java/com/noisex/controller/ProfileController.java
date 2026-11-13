package com.noisex.controller;

import com.noisex.model.dto.ApiResponse;
import com.noisex.model.dto.ProfileRequest;
import com.noisex.model.dto.ProfileResponse;
import com.noisex.service.AdminService;
import com.noisex.service.AuthService;
import com.noisex.service.ProfileService;
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
@RequestMapping("/api/profile")
@RequiredArgsConstructor
@Tag(name = "用户资料", description = "用户资料卡接口")
public class ProfileController {

    private final ProfileService profileService;
    private final AuthService authService;
    private final AdminService adminService;

    @GetMapping
    @Operation(summary = "获取自己的资料卡")
    public ResponseEntity<ApiResponse<ProfileResponse>> getProfile() {
        String userId = SecurityUtils.getCurrentUserId();
        ProfileResponse profile = profileService.getProfile(userId);
        return ResponseEntity.ok(ApiResponse.success(profile));
    }

    @PutMapping
    @Operation(summary = "更新自己的资料卡")
    public ResponseEntity<ApiResponse<ProfileResponse>> updateProfile(
            @RequestBody @Valid ProfileRequest request) {
        String userId = SecurityUtils.getCurrentUserId();
        ProfileResponse profile = profileService.updateProfile(userId, request);
        return ResponseEntity.ok(ApiResponse.success(profile));
    }

    @DeleteMapping("/reset")
    @Operation(summary = "重置匿名身份", description = "清除当前用户所有数据并使当前 JWT 失效")
    public ResponseEntity<ApiResponse<Void>> resetIdentity(HttpServletRequest request) {
        String userId = SecurityUtils.getCurrentUserId();
        authService.resetIdentity(userId);

        // Blacklist current JWT to prevent reuse
        String bearerToken = request.getHeader("Authorization");
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            String token = bearerToken.substring(7);
            adminService.blacklistToken(token);
        }

        return ResponseEntity.ok(ApiResponse.success());
    }
}
