import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFFF6B35);
  static const Color primaryGlow = Color(0x80FF6B35);
  static const Color primaryBorder = Color(0x26FF6B35);
  static const Color primaryInput = Color(0x1AFF6B35);
  static const Color primaryRing = Color(0x66FF6B35);

  static const Color bgBase = Color(0xFF0A0A0F);
  static const Color bgCard = Color(0xFF13131A);
  static const Color bgSecondary = Color(0xFF1A1A24);
  static const Color bgMuted = Color(0xFF1F1F2E);
  static const Color bgAccent = Color(0xFF2A2A3A);

  static const Color textPrimary = Color(0xFFE8E8EA);
  static const Color textSecondary = Color(0xFF8A8A9A);
  // P0-10: 由 0x66E8E8EA 提升到 0xCCE8E8EA，达到 WCAG AA 4.5:1 对比度
  static const Color textMuted = Color(0xCCE8E8EA);

  static const Color cardBorder = Color(0x14FFFFFF);
  static const Color cardBorderHover = Color(0x66FF6B35);

  static const Color error = Color(0xFFFF3838);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);

  /// @deprecated 玻璃效果已弃用，统一使用深色平面设计
  static const Color glassBackground = Color(0x8013131A);

  static const Color headerBarBg = Color(0xFF0F0F18);

  /// TabBar 顶部高光分隔线（0.5px 白色 10% 透明）- 与 HarmonyOS 端对齐
  static const Color tabBarTopHighlight = Color(0x1AFFFFFF);
  static const Color divider = Color(0xFF2A2A3A);
}
