package com.noisex.model.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class SendSonarRequest {
    @NotBlank(message = "content 不能为空")
    @Size(max = 140, message = "声呐内容最多 140 字符")
    private String content;

    @NotBlank(message = "geohash 不能为空")
    @Size(min = 6, max = 6, message = "geohash 精度必须为 6")
    @Pattern(
            regexp = "^[0-9b-hj-km-np-z]+$",
            message = "geohash 包含非法字符（仅允许 base32: 0-9, b-z 不含 i/l/o）")
    private String geohash;
}
