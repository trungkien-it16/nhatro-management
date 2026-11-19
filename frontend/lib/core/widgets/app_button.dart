import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant { primary, outlined, ghost, danger }

class AppButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final bool compact;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.compact = false,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.isLoading;

    final Color bg = switch (widget.variant) {
      AppButtonVariant.primary =>
        _hovered && !disabled ? AppColors.primaryHover : AppColors.primary,
      AppButtonVariant.danger => AppColors.error,
      AppButtonVariant.outlined =>
        _hovered && !disabled ? AppColors.surfaceMuted : AppColors.surface,
      AppButtonVariant.ghost =>
        _hovered && !disabled ? AppColors.surfaceMuted : Colors.transparent,
    };

    final Color fg = switch (widget.variant) {
      AppButtonVariant.primary || AppButtonVariant.danger => AppColors.surface,
      AppButtonVariant.outlined || AppButtonVariant.ghost => AppColors.textPrimary,
    };

    final Border? border = switch (widget.variant) {
      AppButtonVariant.outlined => Border.all(color: AppColors.borderStrong),
      _ => null,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: disabled ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 12 : 16,
            vertical: widget.compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: disabled ? bg.withValues(alpha: 0.55) : bg,
            borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                ),
                const SizedBox(width: 8),
              ] else if (widget.icon != null) ...[
                Icon(widget.icon, size: 17, color: fg),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTypography.bodyMedium.copyWith(
                    color: fg,
                    fontSize: widget.compact ? 12.5 : 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

