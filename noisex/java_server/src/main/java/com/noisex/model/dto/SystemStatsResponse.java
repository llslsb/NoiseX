package com.noisex.model.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class SystemStatsResponse {
    private long onlineUsers;
    private long pendingReports;
    private long activeRooms;
    private double sonarSentTotal;
    private double sonarAcceptedTotal;
    private double roomCreatedTotal;
    private double messageSentTotal;
}
