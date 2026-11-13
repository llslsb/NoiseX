package com.noisex.model.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import lombok.Data;

@Data
public class AuthRequest {
    @NotBlank(message = "anonymousUuid 不能为空")
    @Pattern(
            regexp = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            message = "anonymousUuid 格式不正确")
    private String anonymousUuid;
}
