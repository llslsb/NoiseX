import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// 错误消息映射工具
///
/// 将服务端错误码转换为用户友好的提示文本
class ErrorMessages {
  /// 根据错误码返回友好的错误消息
  static String friendly(int code, String defaultMessage) {
    switch (code) {
      case 40301:
        return '发送太频繁，请稍后再试';
      case 40101:
      case 40102:
        return '登录已过期，请重启应用';
      case 40901:
        return '声呐已过期，请重新发送';
      case 40902:
        return '聊天室已关闭';
      case 40401:
        return '未找到对应内容';
      case 40001:
        if (defaultMessage.contains('重复')) return '请勿发送重复内容的声呐';
        return '请求参数有误';
      case 50001:
        return '服务器开小差了，请稍后再试';
      default:
        return defaultMessage.isNotEmpty ? defaultMessage : '操作失败，请重试';
    }
  }

  /// 显示错误 SnackBar
  static void showErrorSnackBar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  /// 显示成功 SnackBar
  static void showSuccessSnackBar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.primary),
    );
  }
}
