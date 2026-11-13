import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// 玻璃效果容器 - 已弃用
///
/// 为了统一视觉风格并提升低端设备性能，玻璃效果已全局弃用。
/// 请使用纯色背景的 [Container] 替代。
@Deprecated('Use plain Container instead. Glass effect is deprecated for performance and visual consistency.')
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blurSigma;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final double? width;
  final double? height;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.padding,
    this.margin,
    this.blurSigma = 12,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: backgroundColor ?? AppColors.glassBackground,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? AppColors.cardBorder,
                width: borderWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
