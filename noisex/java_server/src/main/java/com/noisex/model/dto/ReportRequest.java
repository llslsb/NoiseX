package com.noisex.model.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class ReportRequest {
    @NotBlank(message = "roomId 不能为空")
    @Pattern(regexp = "^room-.+$", message = "roomId 格式无效，必须以 room- 开头")
    private String roomId;

    @NotBlank(message = "reason 不能为空")
    @Size(max = 500, message = "举报原因最多 500 字符")
    private String reason;

    @Size(max = 20, message = "手机号格式不正确")
    private String phoneNumber;
}
