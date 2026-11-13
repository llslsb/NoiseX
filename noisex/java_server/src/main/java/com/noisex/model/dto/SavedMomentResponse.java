package com.noisex.model.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class SavedMomentResponse {
    private String id;
    private String roomId;
    private String content;
    private long createdAt;
}
