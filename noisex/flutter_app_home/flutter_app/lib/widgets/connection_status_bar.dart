import 'dart:async';

import 'package:flutter/material.dart';
import '../services/ws_service.dart';
import '../theme/colors.dart';
import '../theme/animations.dart';

/// 顶部网络连接状态条。
///
/// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P0-6 对齐：
/// - `connected`：绿色短条，1.5s 后自动淡出（避免长期占屏）
/// - `reconnecting`：橙色脉冲条，常驻，文案"重连中..."
/// - `offline`：红色常驻条，文案"已离线"
///
/// 通常嵌入到 `MainPage` 主内容顶部。安装时被 [ws_service.dart] 的
/// connectionStateStream 驱动；新订阅会通过 [WsService.currentState] 同步当前态。
class ConnectionStatusBar extends StatefulWidget {
  const ConnectionStatusBar({super.key});

  @override
  State<ConnectionStatusBar> createState() => _ConnectionStatusBarState();
}

class _ConnectionStatusBarState extends State<ConnectionStatusBar>
    with SingleTickerProviderStateMixin {
  StreamSubscription<WsConnectionState>? _sub;
  late WsConnectionState _state;
  Timer? _hideTimer;
  bool _hidden = false;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _state = WsService().currentState;
    _hidden = _state == WsConnectionState.connected;

    _pulseController = AnimationController(
      vsync: this,
      duration: AppAnimations.expiringPulse,
    )..repeat(reverse: true);

    _sub = WsService().connectionStateStream.listen(_onState);
  }

  void _onState(WsConnectionState s) {
    if (!mounted) return;
    _hideTimer?.cancel();
    setState(() {
      _state = s;
      _hidden = false;
    });
    if (s == WsConnectionState.connected) {
      // 短暂展示"已连接"后淡出
      _hideTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _hidden = true);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  ({Color color, String text, bool pulse, IconData icon}) _visual() {
    switch (_state) {
      case WsConnectionState.connected:
        return (
          color: AppColors.success,
          text: '● 已连接',
          pulse: false,
          icon: Icons.wifi,
        );
      case WsConnectionState.reconnecting:
        return (
          color: AppColors.warning,
          text: '● 重连中...',
          pulse: true,
          icon: Icons.sync,
        );
      case WsConnectionState.offline:
        return (
          color: AppColors.error,
          text: '● 已离线，请检查网络',
          pulse: false,
          icon: Icons.wifi_off,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _visual();

    return AnimatedSize(
      duration: AppAnimations.normal,
      curve: AppAnimations.decelerateCurve,
      child: AnimatedOpacity(
        duration: AppAnimations.normal,
        opacity: _hidden ? 0.0 : 1.0,
        child: _hidden
            ? const SizedBox(width: double.infinity, height: 0)
            : Container(
                width: double.infinity,
                color: v.color.withOpacity(0.15),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) => Opacity(
                        opacity: v.pulse ? (0.4 + 0.6 * _pulseController.value) : 1.0,
                        child: Icon(v.icon, color: v.color, size: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        v.text,
                        style: TextStyle(
                          fontSize: 12,
                          color: v.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // 离线时显示重试按钮
                    _state == WsConnectionState.offline
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  WsService().reconnect();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppColors.error,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: const Text(
                                    '重试',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox(),
                  ],
                ),
              ),
      ),
    );
  }
}
