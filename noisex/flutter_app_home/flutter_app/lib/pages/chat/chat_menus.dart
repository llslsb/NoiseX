import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/message.dart';
import '../../services/haptic_service.dart';
import '../../theme/colors.dart';

/// 聊天相关的对话框和菜单工具类
///
/// 包含：
/// - 消息长按上下文菜单
/// - 离开房间确认对话框
/// - 保存片段对话框
///
/// 从 `chat_page.dart` 拆分出的独立工具类，约 200 行。
class ChatMenus {
  ChatMenus._();

  /// 显示消息长按上下文菜单（复制/引用/举报）
  static Future<void> showMessageContextMenu({
    required BuildContext context,
    required Message message,
    required VoidCallback onCopy,
    required VoidCallback onQuote,
    required VoidCallback onReport,
  }) async {
    HapticService.instance.medium();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      message.isMe ? Icons.person : Icons.chat_bubble_outline,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        message.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.primaryBorder),
              ListTile(
                leading: const Icon(Icons.copy, color: AppColors.textPrimary),
                title: const Text('复制', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onCopy();
                },
              ),
              ListTile(
                leading: const Icon(Icons.format_quote, color: AppColors.textPrimary),
                // 与鸿蒙端长按菜单一致：区分引用对方消息 / 引用我的消息
                title: Text(
                  message.isMe ? '引用我的消息' : '引用对方消息',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onQuote();
                },
              ),
              ListTile(
                leading: const Icon(Icons.report_outlined, color: AppColors.error),
                title: const Text('举报', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onReport();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 复制消息到剪贴板并显示提示
  static Future<void> copyMessageToClipboard({
    required BuildContext context,
    required Message message,
  }) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!context.mounted) return;
    HapticService.instance.selection();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// 显示离开房间确认对话框
  ///
  /// 离开会永久关闭房间（不可逆），双端统一保留确认
  /// （文案与鸿蒙端 ChatPage 离开确认弹窗一致）。
  static Future<bool> showLeaveRoomDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('离开房间', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          '离开后当前聊天室将关闭，此操作无法撤销。确定离开吗？',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('离开房间', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// 显示保存片段对话框
  static Future<String?> showSaveMomentDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Row(
            children: [
              const Icon(Icons.bookmark, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                '保存临终片段',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          content: TextField(
            controller: controller,
            maxLines: 3,
            maxLength: 500,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: '记录这段对话中最有意义的一句话...',
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.bgBase,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primaryBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primaryBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.bgBase,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result?.trim().isEmpty == true ? null : result;
  }

  /// 单行引用预览文本，最多 30 字，超出截断为省略号
  static String quotePreviewText(Message message) {
    const limit = 30;
    final oneLine = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= limit) return oneLine;
    return '${oneLine.substring(0, limit)}…';
  }
}
