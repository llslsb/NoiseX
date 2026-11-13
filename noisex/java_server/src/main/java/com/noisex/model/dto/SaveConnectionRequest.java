package com.noisex.model.dto;

import jakarta.validation.constraints.NotNull;
import lombok.Data;

@Data
public class SaveConnectionRequest {
    @NotNull(message = "agree 不能为空")
    private Boolean agree;
}
