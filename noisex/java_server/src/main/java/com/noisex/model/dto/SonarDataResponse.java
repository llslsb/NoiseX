package com.noisex.model.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class SonarDataResponse {
    private String id;
    private String content;
    private String distance;
    private long timestamp;
}
