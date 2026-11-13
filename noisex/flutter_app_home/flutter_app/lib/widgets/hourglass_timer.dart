import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../utils/utils.dart';

/// 沙漏倒计时组件（逐项对齐鸿蒙端 HourglassTimer.ets）
///
/// 结构：⏳/⚠️(16px) + 倒计时文本(14px，临期变红) + 120×8 线性进度条(主色/临期红)。
/// 自刷新周期 10s（鸿蒙端 setInterval 10000 同款）；传入 [now] 时为纯展示组件
/// （由父组件统一驱动刷新，适用于列表随父组件节流刷新的场景）。
/// 旧版为纯文本 12px 无进度条，与鸿蒙端不一致（UI 对齐修正）。
///
/// [flexBar]：置于 Expanded（聊天头部行2）等可能被挤压的场景时开启——
/// 进度条在可用宽度 < 120 时自动收缩，避免固定宽溢出（鸿蒙端窄屏同样压缩）。
class HourglassTimer extends StatefulWidget {
  final DateTime expiresAt;
  final DateTime? now;
  final bool flexBar;

  const HourglassTimer({
    super.key,
    required this.expiresAt,
    this.now,
    this.flexBar = false,
  });

  @override
  State<HourglassTimer> createState() => _HourglassTimerState();
}

class _HourglassTimerState extends State<HourglassTimer> {
  Timer? _timer;
  DateTime _selfNow = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.now == null) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(HourglassTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.now == null && oldWidget.now != null) {
      _startTimer();
    } else if (widget.now != null && oldWidget.now == null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    // 鸿蒙端 10s 自刷新
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(() => _selfNow = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? _selfNow;
    final isExpired = now.isAfter(widget.expiresAt);
    // UI 评审 P0：倒计时三档色（>24h 灰 / <24h 橙 / <6h 红），⚠️ 仅红色警戒档
    final isCritical = Utils.isCriticalExpiring(widget.expiresAt, now);
    final tierColor =
        isExpired ? AppColors.error : Utils.expiryTierColor(widget.expiresAt, now);
    final timeText =
        isExpired ? '已过期' : Utils.formatTimeRemainingCN(widget.expiresAt, now);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isCritical && !isExpired ? '⚠️' : '⏳',
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(width: 8),
        Text(
          timeText,
          style: TextStyle(
            fontSize: 14,
            color: tierColor,
          ),
        ),
        const SizedBox(width: 8),
        if (widget.flexBar)
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120, maxHeight: 8),
                child: LinearProgressIndicator(
                  value: Utils.getExpiryProgress(widget.expiresAt, now: now),
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(tierColor),
                  minHeight: 8,
                ),
              ),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 120,
              height: 8,
              child: LinearProgressIndicator(
                value: Utils.getExpiryProgress(widget.expiresAt, now: now),
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(tierColor),
                minHeight: 8,
              ),
            ),
          ),
      ],
    );
  }
}
