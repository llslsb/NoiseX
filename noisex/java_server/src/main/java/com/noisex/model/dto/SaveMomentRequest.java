package com.noisex.model.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class SaveMomentRequest {
    @NotBlank(message = "roomId 不能为空")
    @Pattern(regexp = "^room-.+$", message = "roomId 格式无效，必须以 room- 开头")
    private String roomId;

    @NotBlank(message = "content 不能为空")
    @Size(max = 500, message = "片段内容最多 500 字符")
    private String content;
}
