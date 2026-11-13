package com.noisex.model.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class UnlockResponse {
    private boolean unlocked;
    private ProfileResponse profile;
}
