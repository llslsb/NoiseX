package com.noisex.controller;

import com.noisex.model.dto.*;
import com.noisex.service.SonarService;
import com.noisex.util.SecurityUtils;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/sonar")
@RequiredArgsConstructor
@Tag(name = "声呐", description = "声呐发送与接收接口")
public class SonarController {

    private final SonarService sonarService;

    @PostMapping
    @Operation(summary = "发送声呐")
    public ResponseEntity<ApiResponse<SonarResponse>> sendSonar(
            @RequestBody @Valid SendSonarRequest request) {
        String userId = SecurityUtils.getCurrentUserId();
        String sonarId = sonarService.sendSonar(userId, request.getContent(), request.getGeohash());
        return ResponseEntity.ok(ApiResponse.success(new SonarResponse(sonarId, 0)));
    }

    @GetMapping("/received")
    @Operation(summary = "获取收到的声呐列表")
    public ResponseEntity<ApiResponse<List<SonarDataResponse>>> getReceivedSonars() {
        String userId = SecurityUtils.getCurrentUserId();
        List<SonarDataResponse> sonars = sonarService.getReceivedSonars(userId);
        return ResponseEntity.ok(ApiResponse.success(sonars));
    }

    @PostMapping("/{sonarId}/accept")
    @Operation(summary = "响应声呐")
    public ResponseEntity<ApiResponse<AcceptSonarResponse>> acceptSonar(
            @PathVariable String sonarId) {
        String userId = SecurityUtils.getCurrentUserId();
        AcceptSonarResponse response = sonarService.acceptSonar(userId, sonarId);
        return ResponseEntity.ok(ApiResponse.success(response));
    }

    @PostMapping("/{sonarId}/ignore")
    @Operation(summary = "忽略声呐")
    public ResponseEntity<ApiResponse<Void>> ignoreSonar(@PathVariable String sonarId) {
        String userId = SecurityUtils.getCurrentUserId();
        sonarService.ignoreSonar(userId, sonarId);
        return ResponseEntity.ok(ApiResponse.success());
    }

    @PostMapping("/listen")
    @Operation(summary = "注册为收听者", description = "开启收听模式，后端将用户加入收听者集合并尝试匹配已有声呐")
    public ResponseEntity<ApiResponse<Void>> startListening(
            @RequestParam
                    @Size(min = 6, max = 6, message = "geohash 精度必须为 6")
                    @Pattern(regexp = "^[0-9b-hj-km-np-z]+$", message = "geohash 包含非法字符")
                    String geohash) {
        String userId = SecurityUtils.getCurrentUserId();
        sonarService.registerListener(userId, geohash);
        return ResponseEntity.ok(ApiResponse.success());
    }

    @PostMapping("/unlisten")
    @Operation(summary = "注销收听者", description = "关闭收听模式，将用户从指定 geohash 的收听者集合中移除")
    public ResponseEntity<ApiResponse<Void>> stopListening(
            @RequestParam
                    @Size(min = 6, max = 6, message = "geohash 精度必须为 6")
                    @Pattern(regexp = "^[0-9b-hj-km-np-z]+$", message = "geohash 包含非法字符")
                    String geohash) {
        String userId = SecurityUtils.getCurrentUserId();
        sonarService.unregisterListener(userId, geohash);
        return ResponseEntity.ok(ApiResponse.success());
    }

    @GetMapping("/nearby-activity")
    @Operation(summary = "查询附近活跃用户数（用于雷达 blip 真实化）")
    public ResponseEntity<ApiResponse<NearbyActivityResponse>> getNearbyActivity(
            @RequestParam
                    @Size(min = 6, max = 6, message = "geohash 精度必须为 6")
                    @Pattern(regexp = "^[0-9b-hj-km-np-z]+$", message = "geohash 包含非法字符")
                    String geohash) {
        String userId = SecurityUtils.getCurrentUserId();
        NearbyActivityResponse response = sonarService.getNearbyActivity(userId, geohash);
        return ResponseEntity.ok(ApiResponse.success(response));
    }
}
