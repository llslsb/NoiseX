package com.noisex.controller;

import com.noisex.model.dto.ApiResponse;
import com.noisex.model.dto.ReportRequest;
import com.noisex.service.ReportService;
import com.noisex.util.SecurityUtils;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/report")
@RequiredArgsConstructor
@Tag(name = "举报", description = "举报违规房间")
public class ReportController {

    private final ReportService reportService;

    @PostMapping
    @Operation(summary = "举报房间", description = "举报违规对话房间，可提供手机号用于法律追溯")
    public ResponseEntity<ApiResponse<Map<String, String>>> createReport(
            @RequestBody @Valid ReportRequest request) {
        String userId = SecurityUtils.getCurrentUserId();
        String reportId = reportService.createReport(userId, request);
        return ResponseEntity.ok(ApiResponse.success(Map.of("reportId", reportId)));
    }
}
