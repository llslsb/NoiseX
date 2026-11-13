package com.noisex.controller;

import com.noisex.model.dto.ApiResponse;
import com.noisex.model.dto.ServerTimeResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
@Tag(name = "系统", description = "系统公共接口")
public class SystemController {

    @GetMapping("/time")
    @Operation(summary = "获取服务端当前时间戳")
    public ResponseEntity<ApiResponse<ServerTimeResponse>> getServerTime() {
        return ResponseEntity.ok(
                ApiResponse.success(new ServerTimeResponse(System.currentTimeMillis())));
    }
}
