package com.noisex.model.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ReportAdminResponse {
    private String id;
    private String reporterId;
    private String roomId;
    private String reason;
    private String phoneNumber;
    private String status;
    private long createdAt;
    private Long reviewedAt;
}
