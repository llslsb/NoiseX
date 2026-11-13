import 'package:flutter/material.dart';

/// 声呐 Logo（卫星天线）：双端打包同一高清资源渲染
///
/// 根因（2026-11-03 真机实锤）：Text('📡') 依赖平台 emoji 字体，Android 的
/// Noto Color Emoji 为 128px 位图字模（CBDT），fontSize 96 在 3x 密度下需
/// 288 物理像素，放大 2.25 倍 → 启动页 Logo 明显模糊；且两端 emoji 字体
/// 设计本就不一致（鸿蒙=华为字体、安卓=Noto）。打包 512px 高清资源 =
/// 两端逐像素一致 + 任意分辨率锐利。
class SonarLogo extends StatelessWidget {
  final double size;

  const SonarLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_sonar.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
