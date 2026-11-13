import 'package:flutter/material.dart';
import 'colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static const TextStyle sonarTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    letterSpacing: 3.6,
  );

  static const TextStyle pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.6,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  static const TextStyle tabLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static const TextStyle badge = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: AppColors.bgBase,
  );

  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );
}
