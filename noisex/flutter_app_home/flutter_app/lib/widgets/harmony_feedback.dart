import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// 鸿蒙系统风格反馈组件（2026-11-03 用户点名替换 Material 默认样式）。
///
/// - [showHarmonyToast]：对标 ArkTS `promptAction.showToast`——深色半透明圆角
///   气泡、底部居中、白字、自动消失、无图标无按钮。替换亮绿色 Material
///   SnackBar 横幅（实锤截图 out_test/T16_tp_savereq）。
///   UI 评审 P1（§9-2）：toast 全局队列化——多个提示顺序展示不再同位置
///   叠加；同文案 4s 内去重（save_confirmed 回声类问题在前端兜底）。
/// - [showHarmonyConfirmDialog]：对标 ArkTS `getPromptAction().showDialog`——
///   深色圆角面板、标题居中、正文灰、底部"取消灰/确认橙"文字按钮
///   （实锤对照截图 out_test/T17_x7_savereq）。
/// - [showHarmonyHoldConfirmDialog]：UI 评审 P0（§7-2）——重置身份这类
///   最不可逆操作的确认升级为"按住 3 秒"，替代一层普通点击确认。

/// 统一入场动效（UI 评审 §13-5：弹窗动效 200ms scale+fade，写进规范）。
class HarmonyPanelMotion extends StatelessWidget {
  final Widget child;

  const HarmonyPanelMotion({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (ctx, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
      ),
      child: child,
    );
  }
}

class _ToastRequest {
  final BuildContext context;
  final String message;
  final Duration duration;

  _ToastRequest(this.context, this.message, this.duration);
}

/// toast 全局队列（UI 评审 P1 §9-2）：同一时刻只展示一条，顺序消费；
/// 同文案 4 秒内视为回声去重；队列上限 3 条，超出丢弃最新。
class _ToastQueue {
  static final List<_ToastRequest> _pending = [];
  static bool _showing = false;
  static String? _lastMessage;
  static DateTime _lastShownAt = DateTime.fromMillisecondsSinceEpoch(0);

  static void enqueue(BuildContext context, String message, Duration duration) {
    // 同文案回声去重：4s 内重复到达的同文案只提示一次
    final now = DateTime.now();
    if (message == _lastMessage &&
        !_showing &&
        now.difference(_lastShownAt) < const Duration(seconds: 4)) {
      return;
    }
    if (message == _lastMessage && _showing) return;
    if (_pending.length >= 3) return;
    _pending.add(_ToastRequest(context, message, duration));
    _pump();
  }

  static void _pump() {
    if (_showing || _pending.isEmpty) return;
    final req = _pending.removeAt(0);
    final overlay = Overlay.of(req.context, rootOverlay: true);
    if (overlay == null) {
      _pumpNext();
      return;
    }
    _showing = true;
    _lastMessage = req.message;
    _lastShownAt = DateTime.now();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        right: 0,
        bottom: MediaQuery.of(req.context).size.height * 0.12,
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            type: MaterialType.transparency,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 150),
              builder: (ctx, opacity, child) => Opacity(
                opacity: opacity,
                child: child,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(req.context).size.width * 0.8,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xE6131319),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  req.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Timer(req.duration, () {
      if (entry.mounted) entry.remove();
      _pumpNext();
    });
  }

  static void _pumpNext() {
    _showing = false;
    Timer(const Duration(milliseconds: 150), _pump);
  }
}

/// 深色 toast，底部居中 12% 高度处，[duration] 后自动消失。
/// 实现用 OverlayEntry 自管理（2026-11-03 实测：showGeneralDialog+Timer pop
/// 在 OHOS fork 上 route 不被移除，toast 卡死常驻——T37 截图实锤）。
/// UI 评审 P1：全局队列化 + 同文案去重，见 [_ToastQueue]。
Future<void> showHarmonyToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 1600),
}) async {
  _ToastQueue.enqueue(context, message, duration);
}

/// 鸿蒙系统风格确认弹窗。返回 true=确认，false=取消。
///
/// [danger]=true 时确认按钮用 error 红色（拉黑等不可逆操作），
/// 默认橙色 primary（保存/深度交流等正向确认），取消恒为灰。
Future<bool> showHarmonyConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确认',
  String cancelText = '取消',
  bool danger = false,
  // D3（2026-11-03 真机实测）：点弹窗外空白默认关闭并按"取消"回调，
  // 对保存连接请求这类必须明确表态的确认框，误触空白=误发拒绝。
  // 此类调用方应传 false（barrier 不可点，只能走明确按钮）。
  bool barrierDismissible = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x99000000),
    barrierDismissible: barrierDismissible,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48),
      child: HarmonyPanelMotion(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: const Color(0xF013131A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(64, 40),
                        ),
                        child: Text(
                          cancelText,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(64, 40),
                        ),
                        child: Text(
                          confirmText,
                          style: TextStyle(
                            color: danger ? AppColors.error : AppColors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}

/// 按住确认弹窗（UI 评审 P0 §7-2）：重置身份这类最不可逆操作，
/// 确认方式从"点一下"升级为"按住 [holdSeconds] 秒"——误触不可能完成，
/// 中途松手即取消。面板文案结构与 [showHarmonyConfirmDialog] 一致，
/// 底部是带进度填充的按住按钮。返回 true=按满确认。
Future<bool> showHarmonyHoldConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String holdText = '按住 3 秒确认重置',
  int holdSeconds = 3,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48),
      child: HarmonyPanelMotion(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                color: const Color(0xF013131A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _HoldToConfirmButton(
                    holdText: holdText,
                    holdSeconds: holdSeconds,
                    onCompleted: () => Navigator.pop(ctx, true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}

/// 按住 3 秒确认按钮：按住期间进度条填充，按满触发 [onCompleted]，
/// 松手/移出即重置。鸿蒙端 ProfilePage.ets 同款交互逐项对齐。
class _HoldToConfirmButton extends StatefulWidget {
  final String holdText;
  final int holdSeconds;
  final VoidCallback onCompleted;

  const _HoldToConfirmButton({
    required this.holdText,
    required this.holdSeconds,
    required this.onCompleted,
  });

  @override
  State<_HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<_HoldToConfirmButton> {
  Timer? _timer;
  double _progress = 0;

  void _start() {
    _timer?.cancel();
    // 真实时钟锚定（2026-11-03 用户反馈"3 秒按成 5-6 秒"）：旧版
    // t.tick * 50 累加假定定时器精确 50ms 一跳，UI 线程被重排拖慢时
    // 回调晚点、累加变慢；Stopwatch 墙钟不受影响，两端口径一致。
    final sw = Stopwatch()..start();
    const tick = Duration(milliseconds: 50);
    final total = widget.holdSeconds * 1000;
    _timer = Timer.periodic(tick, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final progress = sw.elapsedMilliseconds / total;
      if (progress >= 1) {
        t.cancel();
        setState(() => _progress = 1);
        widget.onCompleted();
        return;
      }
      setState(() => _progress = progress);
    });
  }

  void _cancel() {
    _timer?.cancel();
    if (mounted) setState(() => _progress = 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _cancel(),
      onTapCancel: _cancel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.12),
                border: Border.all(color: AppColors.error, width: 1),
              ),
              child: Text(
                _progress > 0 ? '继续按住…' : widget.holdText,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _progress.clamp(0.0, 1.0),
                  child: Container(color: AppColors.error.withOpacity(0.35)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
