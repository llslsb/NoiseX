package com.noisex.controller;

import com.noisex.model.dto.*;
import com.noisex.service.AdminService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
@Tag(name = "管理后台", description = "管理员审核与系统监控接口")
public class AdminController {

    private final AdminService adminService;

    @GetMapping("/reports")
    @Operation(summary = "获取举报列表")
    public ResponseEntity<ApiResponse<List<ReportAdminResponse>>> getReports(
            @RequestParam(defaultValue = "pending") String status) {
        List<ReportAdminResponse> reports = adminService.getReports(status);
        return ResponseEntity.ok(ApiResponse.success(reports));
    }

    @PostMapping("/reports/{reportId}/review")
    @Operation(summary = "审核举报", description = "将举报标记为 reviewed、dismissed 或 banned")
    public ResponseEntity<ApiResponse<Void>> reviewReport(
            @PathVariable String reportId, @RequestBody ReviewReportRequest request) {
        adminService.reviewReport(reportId, request.getAction());
        return ResponseEntity.ok(ApiResponse.success());
    }

    @GetMapping("/stats")
    @Operation(summary = "获取系统统计")
    public ResponseEntity<ApiResponse<SystemStatsResponse>> getSystemStats() {
        SystemStatsResponse stats = adminService.getSystemStats();
        return ResponseEntity.ok(ApiResponse.success(stats));
    }
}
