package com.noisex.controller;

import com.noisex.model.dto.*;
import com.noisex.service.ChatService;
import com.noisex.util.SecurityUtils;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/rooms")
@RequiredArgsConstructor
@Tag(name = "对话房间", description = "对话房间管理接口")
public class ChatController {

    private final ChatService chatService;
    private final com.noisex.service.BlockService blockService;
    private final com.noisex.websocket.NoiseXWebSocketHandler webSocketHandler;

    @GetMapping
    @Operation(summary = "获取活跃房间列表")
    public ResponseEntity<ApiResponse<List<RoomResponse>>> getRooms() {
        String userId = SecurityUtils.getCurrentUserId();
        List<RoomResponse> rooms = chatService.getRooms(userId);
        return ResponseEntity.ok(ApiResponse.success(rooms));
    }

    @GetMapping("/{roomId}")
    @Operation(summary = "获取房间详情")
    public ResponseEntity<ApiResponse<RoomResponse>> getRoom(@PathVariable String roomId) {
        String userId = SecurityUtils.getCurrentUserId();
        RoomResponse room = chatService.getRoom(roomId, userId);
        return ResponseEntity.ok(ApiResponse.success(room));
    }

    @GetMapping("/{roomId}/messages")
    @Operation(summary = "获取房间消息历史")
    public ResponseEntity<ApiResponse<MessagesResponse>> getMessages(
            @PathVariable String roomId,
            @RequestParam(defaultValue = "0") long offset,
            @RequestParam(defaultValue = "50") @jakarta.validation.constraints.Max(100) int limit) {
        String userId = SecurityUtils.getCurrentUserId();
        MessagesResponse messages = chatService.getMessages(roomId, userId, offset, limit);
        return ResponseEntity.ok(ApiResponse.success(messages));
    }

    @PostMapping("/{roomId}/unlock")
    @Operation(summary = "解锁资料")
    public ResponseEntity<ApiResponse<UnlockResponse>> unlockProfile(@PathVariable String roomId) {
        String userId = SecurityUtils.getCurrentUserId();
        UnlockResponse response = chatService.unlockProfile(roomId, userId);
        return ResponseEntity.ok(ApiResponse.success(response));
    }

    @PostMapping("/{roomId}/save")
    @Operation(summary = "保存连接")
    public ResponseEntity<ApiResponse<SaveConnectionResponse>> saveConnection(
            @PathVariable String roomId, @RequestBody @Valid SaveConnectionRequest request) {
        String userId = SecurityUtils.getCurrentUserId();
        if (!Boolean.TRUE.equals(request.getAgree())) {
            // 先校验当前用户属于该房间，避免拒绝路径被用于枚举 roomId
            chatService.getRoom(roomId, userId);
            // 通知发起方对方拒绝了保存连接
            String otherUserId = chatService.getOtherUserId(roomId, userId);
            if (otherUserId != null) {
                webSocketHandler.notifySaveRefused(otherUserId, roomId);
            }
            return ResponseEntity.ok(
                    ApiResponse.success(new SaveConnectionResponse("declined", "已拒绝保存连接")));
        }
        SaveConnectionResponse response = chatService.saveConnection(roomId, userId);
        return ResponseEntity.ok(ApiResponse.success(response));
    }

    @PostMapping("/{roomId}/leave")
    @Operation(summary = "离开房间")
    public ResponseEntity<ApiResponse<Void>> leaveRoom(@PathVariable String roomId) {
        String userId = SecurityUtils.getCurrentUserId();
        chatService.leaveRoom(roomId, userId);
        return ResponseEntity.ok(ApiResponse.success());
    }

    @PutMapping("/{roomId}/read")
    @Operation(summary = "标记消息已读")
    public ResponseEntity<ApiResponse<String>> markAsRead(
            @PathVariable String roomId, @RequestParam String messageId) {
        String userId = SecurityUtils.getCurrentUserId();
        String readId = chatService.markAsRead(roomId, userId, messageId);
        return ResponseEntity.ok(ApiResponse.success(readId));
    }

    @PostMapping("/{roomId}/block")
    @Operation(summary = "屏蔽对方用户")
    public ResponseEntity<ApiResponse<Void>> blockUser(@PathVariable String roomId) {
        String userId = SecurityUtils.getCurrentUserId();
        String otherUserId = chatService.getOtherUserId(roomId, userId);
        if (otherUserId == null) {
            throw new com.noisex.exception.NotFoundException("房间不存在或已关闭: " + roomId);
        }
        blockService.blockUser(userId, otherUserId);
        return ResponseEntity.ok(ApiResponse.success());
    }
}
