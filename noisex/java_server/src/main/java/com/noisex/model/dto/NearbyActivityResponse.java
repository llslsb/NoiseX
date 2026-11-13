package com.noisex.model.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 附近活跃用户响应（用于雷达 blip 真实化）
 *
 * <p>返回模糊化的"附近活跃用户数"，仅暴露数量不暴露身份，避免用户被孤立定位。
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class NearbyActivityResponse {
    /** 模糊化后的附近活跃用户数（不含自己），已经过最小阈值/上限处理 */
    private int nearbyCount;

    /** 用于雷达动画展示的 blip 数（0..N，已 clamp 到 UI 友好范围） */
    private int blipCount;
}
