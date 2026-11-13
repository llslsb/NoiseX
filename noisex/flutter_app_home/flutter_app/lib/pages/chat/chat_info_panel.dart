import 'package:flutter/material.dart';
import '../../models/chat_room.dart';
import '../../theme/colors.dart';

/// 聊天信息面板组件
///
/// 内容与鸿蒙端 ChatPage.ChatInfoBuilder 逐字对齐：
/// - 原始声呐
/// - 消息数（你 N · 对方 M）
/// - 深度交流状态
/// - 已解锁资料（签名/城市/联系）
class ChatInfoPanel extends StatelessWidget {
  final ChatRoom room;

  const ChatInfoPanel({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(
          bottom: BorderSide(color: AppColors.primaryBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRow('原始声呐:', '"${room.sonarContent}"'),
          const SizedBox(height: 8),
          // UI 评审 P1（§6-2）：房号是系统词汇，不当人称——改"对方"
          _buildRow(
            '消息数:',
            '你 ${_myCount()} 条 · 对方 ${_otherCount()} 条',
          ),
          const SizedBox(height: 8),
          _buildRow(
            '深度交流:',
            _deepConnectionStatusText(),
            valueColor: room.deepConnectionAchieved
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
          if (room.unlocked) ...[
            const SizedBox(height: 8),
            // 鸿蒙端此块为独立 Column（默认水平居中）+ 内层 padding top 8；
            // 需要 double.infinity 才能在面板全宽上居中（shrink-wrap 只会块内自居中）
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    const Text(
                      '● 已解锁资料:',
                      style: TextStyle(fontSize: 12, color: AppColors.primary),
                    ),
                    const SizedBox(height: 4),
                    // UI 评审 P0（§6-1）：解锁仪式不能被三个"未填写"杀死——
                    // 空值改拟人化空态（鸿蒙端 ChatPage.ets 同文案逐字对齐）
                    Text(
                      _profileValue('签名', room.otherProfile?.signature),
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _profileValue('城市', room.otherProfile?.city),
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _profileValue('联系', room.otherProfile?.contact),
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, color: valueColor ?? AppColors.textPrimary),
          ),
        ),
      ],
    );
  }

  int _myCount() => room.messages.where((m) => m.isMe).length;

  int _otherCount() => room.messages.where((m) => !m.isMe).length;

  /// 与鸿蒙端 ChatRoom.getDeepConnectionStatusText 逐字对齐
  String _deepConnectionStatusText() {
    if (room.unlocked) return '✓ 资料已解锁';
    if (room.bothDeepConfirmed) return '✓ 双方已确认';
    if (room.deepConnectionConfirmed) return '✓ 已确认，等待对方';
    if (room.deepConnectionAchieved) return '✓ 已达成，待确认';
    return '需双方各5条消息';
  }

  /// 与鸿蒙端 ChatRoom.getProfileDisplayValue 对齐（UI 评审 P0 §6-1）：
  /// 空值显示拟人化空态"TA 还没有留下X"——解锁换来的不该是三个"未填写"
  String _profileValue(String label, String? value) =>
      (value == null || value.isEmpty) ? 'TA 还没有留下$label' : value;
}
