package com.noisex.controller;

import com.noisex.model.dto.ApiResponse;
import com.noisex.model.dto.SaveMomentRequest;
import com.noisex.model.dto.SavedMomentResponse;
import com.noisex.service.SavedMomentService;
import com.noisex.util.SecurityUtils;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/moments")
@RequiredArgsConstructor
@Tag(name = "临终片段", description = "临终保存片段功能")
public class SavedMomentController {

    private final SavedMomentService savedMomentService;

    @PostMapping
    @Operation(summary = "保存临终片段", description = "在房间即将过期时保存最后一条片段")
    public ResponseEntity<ApiResponse<Map<String, String>>> saveMoment(
            @RequestBody @Valid SaveMomentRequest request) {
        String userId = SecurityUtils.getCurrentUserId();
        SavedMomentResponse response = savedMomentService.saveMoment(userId, request);
        return ResponseEntity.ok(
                ApiResponse.success(
                        Map.of(
                                "id", response.getId(),
                                "roomId", response.getRoomId())));
    }

    @GetMapping
    @Operation(summary = "获取保存的片段列表", description = "获取当前用户保存的所有片段")
    public ResponseEntity<ApiResponse<List<SavedMomentResponse>>> getUserMoments() {
        String userId = SecurityUtils.getCurrentUserId();
        List<SavedMomentResponse> moments = savedMomentService.getUserMoments(userId);
        return ResponseEntity.ok(ApiResponse.success(moments));
    }
}
