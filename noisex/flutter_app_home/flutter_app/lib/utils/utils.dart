import 'package:flutter/material.dart';
import '../theme/colors.dart';

class Utils {
  Utils._();

  static String formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  /// 剩余时间文案（对齐鸿蒙端 Utils.formatTimeRemainingCN：X小时Y分钟 / Y分钟 / 已过期。
  /// 旧版"X天Y小时/X小时"格式与鸿蒙端不一致，UI 对齐修正）
  static String formatTimeRemainingCN(DateTime expiresAt, [DateTime? now]) {
    final remaining = expiresAt.difference(now ?? DateTime.now());
    if (remaining.inMilliseconds <= 0) return '已过期';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    if (hours > 0) return '$hours小时$minutes分钟';
    return '$minutes分钟';
  }

  static double getExpiryProgress(DateTime expiresAt, {int totalHours = 72, DateTime? now}) {
    final remaining = expiresAt.difference(now ?? DateTime.now()).inSeconds;
    final total = totalHours * 3600;
    if (remaining <= 0) return 0;
    if (remaining >= total) return 1;
    return remaining / total;
  }

  static bool isExpiringSoon(DateTime expiresAt, {int thresholdHours = 12, DateTime? now}) {
    final remaining = expiresAt.difference(now ?? DateTime.now());
    return remaining.inHours < thresholdHours && !remaining.isNegative;
  }

  /// 倒计时状态三档色（UI 评审 P0：>24h 灰 / <24h 橙 / <6h 红）。
  /// 双端同口径：ArkTS Utils.ets expiryTierColor 逐项对齐，改一处必改两端。
  static Color expiryTierColor(DateTime expiresAt, [DateTime? now]) {
    if (isCriticalExpiring(expiresAt, now)) return AppColors.error;
    final remaining = expiresAt.difference(now ?? DateTime.now());
    if (remaining.inHours < 24 && !remaining.isNegative) return AppColors.primary;
    return AppColors.textSecondary;
  }

  /// 红色警戒档（<6h）：⚠️ 标记与进度条脉冲动画的唯一门槛。
  static bool isCriticalExpiring(DateTime expiresAt, [DateTime? now]) {
    final remaining = expiresAt.difference(now ?? DateTime.now());
    return remaining.inHours < 6 && !remaining.isNegative;
  }

  static String truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  static String formatDistance(String? distance) {
    if (distance == null || distance.isEmpty) return '';
    return distance;
  }

  static Color getSignalColor(String signalCode) {
    switch (signalCode) {
      case 'red':
        return AppColors.error;
      case 'green':
        return AppColors.success;
      case 'yellow':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  static String getSignalLabel(String signalCode) {
    switch (signalCode) {
      case 'red':
        return '红色信号';
      case 'green':
        return '绿色信号';
      case 'yellow':
        return '黄色信号';
      default:
        return '信号';
    }
  }
}
