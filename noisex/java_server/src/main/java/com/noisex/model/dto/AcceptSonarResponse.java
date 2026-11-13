package com.noisex.model.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class AcceptSonarResponse {
    private String roomId;
    private String signalCode;
    private String sonarContent;
    private long expiresAt;
}
