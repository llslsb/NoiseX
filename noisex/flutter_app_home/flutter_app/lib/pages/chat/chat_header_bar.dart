import 'package:flutter/material.dart';
import '../../models/chat_room.dart';
import '../../models/constants.dart';
import '../../services/haptic_service.dart';
import '../../theme/colors.dart';
import '../../utils/utils.dart';
import '../../widgets/hourglass_timer.dart';

/// 聊天顶部信息栏组件（结构逐项对齐鸿蒙端 ChatPage.ets ChatHeaderBuilder）
///
/// 双行结构（鸿蒙端同款）：
/// - 行1：返回按钮（纯返回，不触发离开）+ signalCode + ⋮ 更多菜单
/// - 行2：沙漏倒计时 + 🤝进度徽章(未达成) / 🤝确认(条件) / 👤查看资料(已解锁) /
///   🔓解锁(条件) + ●已达成指示
///
/// 更多菜单（鸿蒙端同款顺序）：解锁资料(条件) / 保存连接 / 举报 / 拉黑 / 离开房间。
/// 拉黑/离开使用鸿蒙端硬编码红 #E84855（区别于 error token #FF3838）。
class ChatHeaderBar extends StatelessWidget {
  final ChatRoom room;
  final DateTime now;

  /// UI 评审 P0（§5-4）：深度交流进度做成头部常驻徽章——环形指示器
  /// 随消息滚动出视野后，"还差多少"的进度感不消失；点徽章滚回规则说明。
  final VoidCallback? onDeepBadgeTap;
  final VoidCallback onBack;
  final VoidCallback onToggleInfo;
  final VoidCallback onUnlock;
  final VoidCallback onSave;
  final VoidCallback onReport;
  final VoidCallback onBlock;
  final VoidCallback onConfirmDeep;
  final VoidCallback onLeave;
  final bool unlockInFlight;
  final bool saveInFlight;

  /// 鸿蒙端 ChatPage.ets 拉黑/离开菜单硬编码红（非 error token）
  static const Color _menuDangerRed = Color(0xFFE84855);

  const ChatHeaderBar({
    super.key,
    required this.room,
    required this.now,
    this.onDeepBadgeTap,
    required this.onBack,
    required this.onToggleInfo,
    required this.onUnlock,
    required this.onSave,
    required this.onReport,
    required this.onBlock,
    required this.onConfirmDeep,
    required this.onLeave,
    this.unlockInFlight = false,
    this.saveInFlight = false,
  });

  /// 鸿蒙端 canUnlockProfile 等价条件（createdAt 恒有效，仅校验窗口）
  bool get _canUnlock =>
      !room.unlocked &&
      room.bothDeepConfirmed &&
      room.unlockWindowRemaining > Duration.zero;

  @override
  Widget build(BuildContext context) {
    // UI 评审 P0（§5-1）：头部底色随倒计时三档（<6h 红警示 / 其余常规）
    final critical = Utils.isCriticalExpiring(room.expiresAt, now);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        border: Border(
          bottom: BorderSide(
            color: critical ? AppColors.error.withOpacity(0.3) : AppColors.primaryBorder,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildTitleRow(context),
          _buildStatusRow(),
        ],
      ),
    );
  }

  /// 行1：返回 + signalCode + 更多菜单（鸿蒙端 Text('←')/Text('⋮') 同款字形）
  Widget _buildTitleRow(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Text('←', style: TextStyle(fontSize: 20, color: AppColors.textPrimary)),
              ),
            ),
          ),
          Expanded(
            child: Text(
              room.signalCode,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Builder 提供 ⋮ 按钮自身的锚点 context：showMenu 需以按钮盒计算弹出位置
          Builder(
            builder: (btnContext) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showMenu(btnContext),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Text(
                    '⋮',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 行2：倒计时(layoutWeight 1) + 深度进度徽章(未达成) + 条件按钮 + 已达成指示
  Widget _buildStatusRow() {
    final canDeepConfirm =
        room.deepConnectionAchieved && !room.deepConnectionConfirmed;
    final deepWindowOpen = room.unlockWindowRemaining > Duration.zero;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            // flexBar：头部行空间被按钮/状态文案挤压时进度条收缩，防固定 120px 溢出
            child: HourglassTimer(
              expiresAt: room.expiresAt,
              now: now,
              flexBar: true,
            ),
          ),
          // UI 评审 P0（§5-4）：未达成时常驻进度徽章"🤝 12/20"，
          // 点按滚回列表顶部的环形规则说明（信息不随滚动丢失）
          if (!room.deepConnectionAchieved && room.totalMessageCount > 0) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDeepBadgeTap,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryInput,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primaryBorder, width: 1),
                ),
                child: Text(
                  '🤝 ${room.totalMessageCount}/${Constants.deepConnectionThreshold}',
                  style: const TextStyle(fontSize: 12, color: AppColors.primary),
                ),
              ),
            ),
          ],
          if (canDeepConfirm) ...[
            const SizedBox(width: 8),
            _pillButton(
              label: '🤝 确认',
              onTap: deepWindowOpen ? onConfirmDeep : null,
            ),
          ],
          if (room.unlocked) ...[
            const SizedBox(width: 8),
            _pillButton(label: '👤 查看资料', onTap: onToggleInfo),
          ] else if (_canUnlock) ...[
            const SizedBox(width: 8),
            _pillButton(
              label: unlockInFlight ? '解锁中…' : '🔓 解锁',
              onTap: unlockInFlight ? null : onUnlock,
            ),
          ],
          if (room.deepConnectionAchieved) ...[
            const SizedBox(width: 8),
            const Text(
              '● 深度交流已达成',
              style: TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }

  /// 鸿蒙端胶囊按钮：12px / 主色底 / bg_base 字 / 圆角 16 / 高 28
  Widget _pillButton({required String label, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.bgBase),
          ),
        ),
      ),
    );
  }

  /// 更多菜单（鸿蒙端顺序与 emoji 前缀逐项对齐）
  ///
  /// Flutter 3.41 起 showMenu 强制要求 position（旧版缺省居中已断言移除），
  /// 以 ⋮ 按钮盒为锚：菜单右缘对齐按钮、顶部贴按钮下缘，超宽自动向左回缩。
  void _showMenu(BuildContext context) {
    HapticService.instance.selection();
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: context,
      position: position,
      color: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        if (_canUnlock)
          const PopupMenuItem(
            value: 'unlock',
            child: Row(children: [
              Text('🔓', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text('解锁资料', style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
            ]),
          ),
        // UI 评审 §9-1：菜单项间加分隔线（对齐 ArkTS 端菜单分隔样式）
        if (_canUnlock) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'save',
          enabled: room.unlocked &&
              room.canSaveConnection &&
              !saveInFlight,
          child: Row(children: [
            Text(
              room.bothSaveConfirmed ? '✓' : (room.mySaveConfirmed ? '⏳' : '❤️'),
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 8),
            Text(
              _getSaveButtonText(),
              style: TextStyle(
                fontSize: 15,
                color: room.mySaveConfirmed ? AppColors.textSecondary : AppColors.textPrimary,
              ),
            ),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'report',
          child: Row(children: [
            Text('🚩', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('举报', style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'block',
          child: Row(children: [
            Text('🚫', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('拉黑', style: TextStyle(fontSize: 15, color: ChatHeaderBar._menuDangerRed)),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'leave',
          child: Row(children: [
            Text('🚪', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('离开房间', style: TextStyle(fontSize: 15, color: ChatHeaderBar._menuDangerRed)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'unlock':
          if (!unlockInFlight) onUnlock();
          break;
        case 'save':
          if (!saveInFlight) onSave();
          break;
        case 'report':
          onReport();
          break;
        case 'block':
          onBlock();
          break;
        case 'leave':
          onLeave();
          break;
      }
    });
  }

  /// 保存按钮文字（与鸿蒙端 ChatRoom.getSaveConnectionStatusText 逐字对齐）
  String _getSaveButtonText() {
    if (saveInFlight) return '请求保存…';
    if (room.bothSaveConfirmed) return '连接已保存';
    if (room.mySaveConfirmed) return '等待对方确认';
    return '保存连接';
  }
}
