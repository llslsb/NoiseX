package com.noisex.model.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class AdminLoginRequest {
    @NotBlank(message = "用户名不能为空")
    @Size(min = 3, max = 64, message = "用户名长度必须在3-64字符之间")
    @Pattern(regexp = "^[a-zA-Z0-9._-]+$", message = "用户名只能包含字母、数字、点、下划线和横线")
    private String username;

    @NotBlank(message = "密码不能为空")
    @Size(min = 8, max = 128, message = "密码长度必须在8-128字符之间")
    private String password;
}
