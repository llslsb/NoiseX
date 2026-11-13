import 'dart:async';
import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/colors.dart';
import '../models/chat_room.dart';
import '../widgets/pull_refresh.dart';
import '../widgets/room_card.dart';
import '../../widgets/hourglass_timer.dart';

/// 沙漏页：活跃房间倒计时列表。
///
/// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` 对齐：
/// - P0-9：刷新频率不再固定 10s，而是根据"列表中最短剩余"动态选 60s/10s/1s
/// - P0-9：任意房间剩余 ≤5 分钟时，每分钟触发一次重触觉 + 短音效
/// - P2-D：智能分组（即将过期 / 可解锁 / 进行中）三栏渲染，节奏感优于平铺
class HourglassPage extends StatefulWidget {
  final List<ChatRoom> rooms;
  final void Function(String) onEnterRoom;

  /// 下拉刷新（对齐鸿蒙端 PullRefresh.ets）：拉最新房间列表 + 逐房间
  /// 同步消息流（未读角标/最后消息预览以服务端为准）。
  final Future<void> Function() onRefresh;
  final double statusBarHeight;

  const HourglassPage({
    super.key,
    required this.rooms,
    required this.onEnterRoom,
    required this.onRefresh,
    this.statusBarHeight = 0,
  });

  @override
  State<HourglassPage> createState() => _HourglassPageState();
}

class _HourglassPageState extends State<HourglassPage> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  /// 上次触发"即将过期"提醒的整分钟时间戳，避免同一分钟反复触发
  int _lastWarnMinuteEpoch = 0;

  /// UI 评审 P2（§4-4）：底部教育文案只在前 3 次进入本页时显示，
  /// 之后是噪音（本地计数，不涉服务端；鸿蒙端 HourglassPage.ets 同口径）
  static const String _eduShownCountKey = 'edu_hourglass_shown_count';
  bool _showEduCopy = false;

  @override
  void initState() {
    super.initState();
    _maybeShowEduCopy();
    _scheduleNextTick();
  }

  Future<void> _maybeShowEduCopy() async {
    final shown = StorageService().getInt(_eduShownCountKey);
    if (shown >= 3) return;
    if (!mounted) return;
    setState(() => _showEduCopy = true);
    await StorageService().setInt(_eduShownCountKey, shown + 1);
  }

  @override
  void didUpdateWidget(covariant HourglassPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // rooms 变化（增/删/到期）后，需要立刻重算节奏
    if (widget.rooms.length != oldWidget.rooms.length) {
      _scheduleNextTick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 根据"最短剩余时间"决定下一次刷新间隔：
  /// - >10 分钟 → 60 秒
  /// - 1~10 分钟 → 10 秒
  /// - <1 分钟 → 1 秒（让倒计时秒级跳动）
  Duration _computeInterval() {
    if (widget.rooms.isEmpty) return const Duration(seconds: 60);
    Duration shortest = const Duration(days: 999);
    for (final r in widget.rooms) {
      final left = r.expiresAt.difference(_now);
      if (left < shortest) shortest = left;
    }
    if (shortest.inMinutes > 10) return const Duration(seconds: 60);
    if (shortest.inMinutes >= 1) return const Duration(seconds: 10);
    return const Duration(seconds: 1);
  }

  void _scheduleNextTick() {
    _timer?.cancel();
    final interval = _computeInterval();
    _timer = Timer.periodic(interval, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _now = DateTime.now());
      _maybeWarnExpiring();
      // 间隔可能因最短剩余变化而需调整
      final desired = _computeInterval();
      if (desired != interval) {
        _scheduleNextTick();
      }
    });
  }

  /// 任意房间剩余 ≤5 分钟时，按整分钟节奏发出一次重触觉 + 警告短音。
  void _maybeWarnExpiring() {
    final critical = widget.rooms.any((r) {
      final left = r.expiresAt.difference(_now);
      return left.inSeconds > 0 && left.inMinutes < 5;
    });
    if (!critical) return;
    final minuteEpoch = _now.millisecondsSinceEpoch ~/ 60000;
    if (minuteEpoch == _lastWarnMinuteEpoch) return;
    _lastWarnMinuteEpoch = minuteEpoch;
    HapticService.instance.heavy();
    SoundService.instance.playExpiringWarn();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgBase,
      child: Padding(
        padding: EdgeInsets.only(top: widget.statusBarHeight),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.headerBarBg,
                border: Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 对齐鸿蒙端：⏳ emoji + 最早到期房间倒计时（无房间时隐藏）
                  Row(
                    children: [
                      const Text('⏳', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 4),
                      const Text(
                        ' 沙漏',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      if (widget.rooms.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        HourglassTimer(
                          expiresAt: widget.rooms
                              .map((r) => r.expiresAt)
                              .reduce((a, b) => a.isBefore(b) ? a : b),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '> ${widget.rooms.length} 个活跃连接',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.rooms.isEmpty
                  ? SizedBox(
                      height: 256,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 对齐鸿蒙端：⏳ emoji 64px + 0.2 透明度
                            Opacity(
                              opacity: 0.2,
                              child: Text('⏳', style: TextStyle(fontSize: 64)),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '暂无活跃对话',
                              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            // 对齐鸿蒙端：12px textSecondary + 0.6 透明度
                            Opacity(
                              opacity: 0.6,
                              child: Text(
                                '响应一个声呐信号开始对话',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : PullRefresh(
                      onRefresh: widget.onRefresh,
                      child: _buildGroupedList(),
                    ),
            ),
            if (widget.rooms.isNotEmpty && _showEduCopy)
              Container(
                // 对齐鸿蒙端：padding 12
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: AppColors.headerBarBg,
                  border: Border(top: BorderSide(color: AppColors.divider)),
                ),
                child: const Center(
                  child: Text(
                    '所有对话将在72小时后自动风干，除非双方保存连接',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========== P2-D 智能分组 ==========

  /// 三个分组桶：
  /// - 即将过期（剩余 < 6h，且 > 0）
  /// - 可解锁（解锁窗口仍开放且深度交流已达成、或双方已确认深度交流但尚未解锁）
  /// - 进行中（其他活跃房间，包括已解锁、已保存连接）
  ///
  /// 一个房间只会落到优先级最高的桶里：即将过期 > 可解锁 > 进行中。
  ({List<ChatRoom> expiring, List<ChatRoom> unlockable, List<ChatRoom> ongoing})
      _classifyRooms() {
    final expiring = <ChatRoom>[];
    final unlockable = <ChatRoom>[];
    final ongoing = <ChatRoom>[];
    for (final r in widget.rooms) {
      final left = r.expiresAt.difference(_now);
      if (left.inSeconds > 0 && left.inHours < 6) {
        expiring.add(r);
        continue;
      }
      final canUnlockNow = r.bothDeepConfirmed && !r.unlocked;
      final inUnlockWindow =
          !r.unlocked && r.deepConnectionAchieved && r.isUnlockWindowOpen;
      if (canUnlockNow || inUnlockWindow) {
        unlockable.add(r);
        continue;
      }
      ongoing.add(r);
    }
    int byUrgency(ChatRoom a, ChatRoom b) =>
        a.expiresAt.compareTo(b.expiresAt);
    expiring.sort(byUrgency);
    unlockable.sort(byUrgency);
    ongoing.sort(byUrgency);
    return (expiring: expiring, unlockable: unlockable, ongoing: ongoing);
  }

  Widget _buildGroupedList() {
    final groups = _classifyRooms();
    final children = <Widget>[];

    void addGroup({
      required String title,
      required Color accent,
      required List<ChatRoom> rooms,
    }) {
      if (rooms.isEmpty) return;
      children.add(_buildSectionHeader(
        title: title,
        accent: accent,
        count: rooms.length,
      ));
      for (final r in rooms) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RoomCard(
            room: r,
            now: _now,
            onEnter: () => widget.onEnterRoom(r.id),
          ),
        ));
      }
      children.add(const SizedBox(height: 12));
    }

    // 对齐鸿蒙端：分组标题自带 emoji（⏰/🔓/💬），无独立图标
    addGroup(
      title: '⏰ 即将过期',
      accent: AppColors.error,
      rooms: groups.expiring,
    );
    addGroup(
      title: '🔓 可解锁',
      accent: const Color(0xFFFF7800), // 与鸿蒙端 SectionHeader 一致的橙色
      rooms: groups.unlockable,
    );
    addGroup(
      title: '💬 进行中',
      accent: AppColors.textSecondary,
      rooms: groups.ongoing,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required Color accent,
    required int count,
  }) {
    return Padding(
      // 对齐鸿蒙端：上下 padding 8
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(width: 8),
          // 对齐鸿蒙端：计数徽章 padding 6/2、radius 8、accent 12% 底
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: 1,
            width: 40,
            color: accent.withOpacity(0.2),
          ),
        ],
      ),
    );
  }
}
