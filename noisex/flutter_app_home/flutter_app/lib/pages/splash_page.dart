import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/radar_animation.dart';
import '../widgets/sonar_logo.dart';

/// 启动页（逐项对齐鸿蒙端 SplashPage.ets）
///
/// 时序：进度 30ms/步 × 2% 走满 3s，停留 500ms 后回调 onComplete（与鸿蒙端一致，
/// 旧版 1.5s 即回调导致双端节奏不一致）。
/// 视觉对齐修正：📡 emoji logo（旧版误用 Material 图标）、NOISEX letterSpacing 0.3
/// （旧版误用 64×0.3=19.2，鸿蒙端 letterSpacing 为 fp 绝对值不乘字号）、标语分隔符 '·'、
/// 底部标语 12px textSecondary（旧版 11px textMuted）。
class SplashPage extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashPage({super.key, required this.onComplete});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  int _progress = 0;
  Timer? _progressTimer;
  Timer? _completeTimer;

  @override
  void initState() {
    super.initState();
    // 鸿蒙端 setInterval(30ms) 每 tick +2，走满 100% 后停留 500ms 再通知父组件
    _progressTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progress += 2;
        if (_progress >= 100) {
          _progress = 100;
          timer.cancel();
          _completeTimer = Timer(const Duration(milliseconds: 500), () {
            if (mounted) widget.onComplete();
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _completeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Material 透明祖先：消除 debug 模式无 Material 祖先的黄色双下划线告警
    //（主页面分支由 Scaffold 提供，同为 Android/OHOS 双端实锤）
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: AppColors.bgBase,
        child: Stack(
        children: [
          // 雷达动画背景（鸿蒙端 100%×100% Stack + opacity 0.1）
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: const RadarAnimation(isActive: true),
            ),
          ),
          // 主内容（鸿蒙端 alignContent Center）
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo（鸿蒙端同位 96；emoji 字体在安卓为 128px 位图字模放大发糊，
                // 改双端打包高清资源，见 SonarLogo 注释）
                const SonarLogo(size: 96),
                const SizedBox(height: 16),
                const Text(
                  'NOISEX',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '遇见未知，不必算法',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 48),
                // 进度条
                SizedBox(
                  width: 256,
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: _progress / 100,
                        backgroundColor: AppColors.bgMuted,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.primary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '初始化声呐系统... $_progress%',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // 底部标语
                Column(
                  children: [
                    Text(
                      '无算法 · 无推荐 · 无排序',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary.withOpacity(0.6)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '纯粹的随机与地理邻近',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary.withOpacity(0.6)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
