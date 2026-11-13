import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// 三跳点 typing 指示器。
///
/// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P0-5 对齐。
/// 仅前端 UI；后端 `typing_start` / `typing_stop` 协议留给 P1。
///
/// 使用示例：
/// ```dart
/// if (peerIsTyping)
///   TypingIndicator(peerSignalCode: room.signalCode)
/// ```
class TypingIndicator extends StatefulWidget {
  /// 对方信号码（用于显示"RX-XXXX 正在输入..."）。
  final String peerSignalCode;

  const TypingIndicator({
    super.key,
    required this.peerSignalCode,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      ),
    );
    _animations = _controllers.map((c) {
      return Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
    }).toList();

    // 错相位重复
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: 200 * i), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.peerSignalCode} 正在输入',
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.peerSignalCode} 正在输入',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            for (int i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              AnimatedBuilder(
                animation: _animations[i],
                builder: (_, __) => Opacity(
                  opacity: _animations[i].value,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
