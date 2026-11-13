package com.noisex.controller;

import com.noisex.model.dto.ApiResponse;
import com.noisex.service.BlockService;
import com.noisex.util.SecurityUtils;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * 拉黑管理接口.
 *
 * <p>提供拉黑列表查询和解除拉黑功能。
 *
 * <p>拉黑操作通过 ChatController 的 POST /api/rooms/{roomId}/block 接口进行。
 */
@RestController
@RequestMapping("/api/blocks")
@RequiredArgsConstructor
@Tag(name = "拉黑管理", description = "拉黑列表查询和解除拉黑接口")
public class BlockController {

    private final BlockService blockService;

    @GetMapping
    @Operation(summary = "获取拉黑列表", description = "返回当前用户已拉黑的所有用户 ID 集合")
    public ResponseEntity<ApiResponse<Set<String>>> getBlockedList() {
        String userId = SecurityUtils.getCurrentUserId();
        Set<String> blockedIds = blockService.getBlockedList(userId);
        return ResponseEntity.ok(ApiResponse.success(blockedIds));
    }

    @DeleteMapping("/{blockedUserId}")
    @Operation(summary = "解除拉黑", description = "解除对指定用户的拉黑，解除后对方仍可能通过声呐匹配到你")
    public ResponseEntity<ApiResponse<Void>> unblockUser(@PathVariable String blockedUserId) {
        String userId = SecurityUtils.getCurrentUserId();
        blockService.unblockUser(userId, blockedUserId);
        return ResponseEntity.ok(ApiResponse.success());
    }
}
