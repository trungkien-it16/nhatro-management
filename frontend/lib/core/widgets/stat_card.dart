import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_typography.dart';

enum StatIconTone { primary, success, warning, error, neutral }

/// StatCard chuẩn SaaS:
/// - Background luôn là màu trắng (AppColors.surface)
/// - Border nhẹ (AppColors.border), radius 12px
/// - Chỉ icon nằm trong nền màu nhạt semantic
/// - Hover effect tinh tế
class StatCard extends StatefulWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final StatIconTone tone;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
    this.tone = StatIconTone.primary,
    this.onTap,
  });

  @override
  State<StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<StatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final (iconBg, iconFg) = switch (widget.tone) {
      StatIconTone.primary => (AppColors.primaryLight, AppColors.primary),
      StatIconTone.success => (AppColors.successLight, AppColors.success),
      StatIconTone.warning => (AppColors.warningLight, AppColors.warningText),
      StatIconTone.error => (AppColors.errorLight, AppColors.error),
      StatIconTone.neutral => (AppColors.surfaceMuted, AppColors.textSecondary),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: _hovered ? AppColors.primaryBorder : AppColors.border,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppColors.textPrimary.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTypography.captionMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.icon, size: 19, color: iconFg),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Giá trị dài (vd. tiền tệ) thu nhỏ vừa thẻ thay vì xuống dòng và tràn chiều cao cố định.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(widget.value, style: AppTypography.statValue, maxLines: 1),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
