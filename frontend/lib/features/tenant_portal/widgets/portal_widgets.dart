import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Một dòng "nhãn: giá trị" chỉ đọc (trang của khách thuê).
class InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 170, child: Text(label, style: AppTypography.caption)),
          Expanded(
            child: Text(value.trim().isEmpty ? '—' : value, style: AppTypography.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Ghi chú: trang chỉ xem, dữ liệu do chủ trọ quản lý.
class ReadOnlyNote extends StatelessWidget {
  final String message;

  const ReadOnlyNote(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: AppTypography.caption.copyWith(color: AppColors.primary))),
        ],
      ),
    );
  }
}
