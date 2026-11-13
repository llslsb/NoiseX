package com.noisex.controller;

import com.noisex.model.dto.ApiResponse;
import com.noisex.service.PushService;
import com.noisex.util.SecurityUtils;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/push")
@RequiredArgsConstructor
@Tag(name = "推送", description = "推送通知管理接口")
public class PushController {

    private final PushService pushService;

    @PostMapping("/register")
    @Operation(summary = "注册推送Token")
    public ResponseEntity<ApiResponse<Void>> registerToken(
            @RequestParam String pushToken, @RequestParam(defaultValue = "hms") String channel) {
        String userId = SecurityUtils.getCurrentUserId();
        pushService.registerToken(userId, pushToken, channel);
        return ResponseEntity.ok(ApiResponse.success());
    }

    @DeleteMapping("/token")
    @Operation(summary = "注销推送Token")
    public ResponseEntity<ApiResponse<Void>> unregisterToken() {
        String userId = SecurityUtils.getCurrentUserId();
        pushService.unregisterToken(userId);
        return ResponseEntity.ok(ApiResponse.success());
    }
}
