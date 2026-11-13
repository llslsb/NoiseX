package com.noisex.model.dto;

import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class ProfileRequest {
    @Size(max = 200, message = "签名最多 200 字符")
    private String signature;

    @Size(max = 50, message = "城市最多 50 字符")
    private String city;

    @Size(max = 200, message = "联系方式最多 200 字符")
    private String contact;
}
