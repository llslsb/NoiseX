import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/animations.dart';
import '../theme/colors.dart';
import '../models/sonar.dart';
import '../utils/utils.dart';

/// 声呐卡片。
/// UI 评审 P1（§3）：主路径二选一——保留滑动为主路径，卡片上只留
/// "响应"一个主 CTA；忽略纯靠左滑（页头文案教手势）。
/// 时间戳相对化自动刷新 + 随陈旧度衰减色（≤5min 高亮 / ≤30min 灰 / 更旧更暗）。
class SonarCard extends StatefulWidget {
  final Sonar sonar;
  final VoidCallback onAccept;

  const SonarCard({
    super.key,
    required this.sonar,
    required this.onAccept,
  });

  @override
  State<SonarCard> createState() => _SonarCardState();
}

class _SonarCardState extends State<SonarCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isHovered = false;
  Timer? _refreshTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.fadeInUp,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.fadeInUpCurve),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.fadeInUpCurve),
    );
    _controller.forward();
    // UI 评审 P1（§3-3）："1 分钟前"每 30s 自动刷新
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 时间戳陈旧度衰减色（亮度递减：白 → 80% 白 → 中灰）：
  /// ≤5min 高亮 / ≤30min 次亮 / 更旧最暗。
  /// 声呐价值随时间衰减，颜色应诚实反映（鸿蒙端 SonarCard.ets 同口径）。
  Color _timestampColor() {
    final age = _now.difference(widget.sonar.timestamp);
    if (age.inMinutes < 5) return AppColors.textPrimary;
    if (age.inMinutes < 30) return AppColors.textMuted;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Transform.translate(
            offset: Offset(0, _isHovered ? -2 : 0),
            child: AnimatedContainer(
              duration: AppAnimations.normal,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isHovered ? AppColors.cardBorderHover : AppColors.primaryBorder,
                  width: 1,
                ),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 0,
                        ),
                      ]
                    : [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        widget.sonar.distance,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.access_time, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        Utils.formatTime(widget.sonar.timestamp),
                        style: TextStyle(fontSize: 12, color: _timestampColor()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '"${widget.sonar.content}"',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // UI 评审 P1：唯一主 CTA——"响应"；忽略走卡片左滑
                  ElevatedButton(
                    onPressed: widget.onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.bgBase,
                      minimumSize: const Size(double.infinity, 36),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    // 对齐鸿蒙端：monospace 字体
                    child: const Text('响应',
                        style: TextStyle(
                            fontSize: 14, fontFamily: 'monospace')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
