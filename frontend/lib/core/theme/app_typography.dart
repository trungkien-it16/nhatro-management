import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Stitch Nhatro Management Typography (Roboto Flex scale).
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Roboto Flex';
  static const List<String> fontFallback = ['Roboto', 'sans-serif'];

  // Stitch Scale Tokens
  static const TextStyle displayLg = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
    height: 38 / 30,
  );

  static const TextStyle displayLgMobile = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
    height: 32 / 24,
  );

  static const TextStyle headlineLg = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 28 / 22,
  );

  static const TextStyle headlineMd = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 19,
    fontWeight: FontWeight.w700,
    color: AppColors.textHeadingStrong,
    height: 26 / 19,
  );

  static const TextStyle titleLg = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 24 / 18,
  );

  static const TextStyle titleMd = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 22 / 16,
  );

  static const TextStyle titleSm = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 20 / 15,
  );

  static const TextStyle bodyLg = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textBody,
    height: 22 / 15,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textBody,
    height: 20 / 14,
  );

  static const TextStyle bodyBold = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textLabel,
    height: 20 / 14,
  );

  static const TextStyle labelMd = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textLabel,
    height: 18 / 13,
  );

  static const TextStyle labelSm = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    height: 16 / 12,
  );

  static const TextStyle captionSm = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 14 / 11,
  );

  // Semantic Aliases (retained for existing widgets/screens)
  static const TextStyle pageTitle = headlineLg;

  static const TextStyle pageSubtitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 20 / 14,
  );

  static const TextStyle sectionTitle = titleMd;

  static const TextStyle cardTitle = bodyBold;

  static const TextStyle statValue = displayLgMobile;

  static const TextStyle body = bodyMd;

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  static const TextStyle bodySemiBold = bodyBold;

  static const TextStyle tableHeader = labelSm;

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 16 / 12,
  );

  static const TextStyle captionMedium = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 16 / 12,
  );

  static const TextStyle code = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
}

