import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_typography.dart';

/// Semantic status types aligned with Stitch RoomStatusBadge & SaaS feedback:
/// - success: Available / Active / Paid / Completed
/// - warning: Maintenance / Expiring / Pending
/// - error: Occupied / Overdue / Expired / High priority
/// - reserved: Reserved rooms (#8B5CF6 / #EDE9FE)
/// - info: In-progress / Informational
/// - neutral: Inactive / Cancelled
enum BadgeType { success, warning, error, reserved, info, neutral }

class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeType type;
  final bool showDot;

  const StatusBadge({
    super.key,
    required this.label,
    required this.type,
    this.showDot = true,
  });

  factory StatusBadge.fromRoomStatus(String status) {
    return switch (status) {
      'AVAILABLE' => const StatusBadge(label: 'Còn trống', type: BadgeType.success),
      'OCCUPIED' => const StatusBadge(label: 'Đang thuê', type: BadgeType.error),
      'FULL' => const StatusBadge(label: 'Đã đủ người', type: BadgeType.reserved),
      'RESERVED' => const StatusBadge(label: 'Đã đặt trước', type: BadgeType.reserved),
      'MAINTENANCE' => const StatusBadge(label: 'Đang bảo trì', type: BadgeType.warning),
      _ => const StatusBadge(label: 'Ngừng hoạt động', type: BadgeType.neutral),
    };
  }

  factory StatusBadge.fromPropertyStatus(String status) {
    return switch (status) {
      'ACTIVE' => const StatusBadge(label: 'Đang hoạt động', type: BadgeType.success),
      'INACTIVE' => const StatusBadge(label: 'Tạm ngưng', type: BadgeType.warning),
      _ => const StatusBadge(label: 'Đã đóng', type: BadgeType.neutral),
    };
  }

  factory StatusBadge.fromContractStatus(String status) {
    return switch (status) {
      'DRAFT' => const StatusBadge(label: 'Bản nháp', type: BadgeType.info),
      'ACTIVE' => const StatusBadge(label: 'Đang hiệu lực', type: BadgeType.success),
      'EXTENDED' => const StatusBadge(label: 'Đã gia hạn', type: BadgeType.success),
      'EXPIRING' => const StatusBadge(label: 'Sắp hết hạn', type: BadgeType.warning),
      'EXPIRED' => const StatusBadge(label: 'Đã hết hạn', type: BadgeType.error),
      'TERMINATED' => const StatusBadge(label: 'Đã thanh lý', type: BadgeType.neutral),
      _ => const StatusBadge(label: 'Đã hủy', type: BadgeType.neutral),
    };
  }

  factory StatusBadge.fromInvoiceStatus(String status) {
    return switch (status) {
      'PAID' => const StatusBadge(label: 'Đã thanh toán', type: BadgeType.success),
      'UNPAID' => const StatusBadge(label: 'Chưa thanh toán', type: BadgeType.warning),
      'CANCELLED' => const StatusBadge(label: 'Đã hủy', type: BadgeType.neutral),
      _ => const StatusBadge(label: 'Quá hạn', type: BadgeType.error),
    };
  }

  factory StatusBadge.fromMaintenanceStatus(String status) {
    return switch (status) {
      'PENDING' => const StatusBadge(label: 'Chờ xử lý', type: BadgeType.warning),
      'IN_PROGRESS' => const StatusBadge(label: 'Đang xử lý', type: BadgeType.info),
      'COMPLETED' => const StatusBadge(label: 'Hoàn thành', type: BadgeType.success),
      _ => const StatusBadge(label: 'Đã hủy', type: BadgeType.neutral),
    };
  }

  factory StatusBadge.fromPriority(String priority) {
    return switch (priority) {
      'HIGH' || 'URGENT' => const StatusBadge(label: 'Cao', type: BadgeType.error),
      'MEDIUM' => const StatusBadge(label: 'Trung bình', type: BadgeType.warning),
      _ => const StatusBadge(label: 'Thấp', type: BadgeType.neutral),
    };
  }

  factory StatusBadge.fromTenantStatus(String status) {
    return switch (status) {
      'ACTIVE' => const StatusBadge(label: 'Đang thuê', type: BadgeType.success),
      'INACTIVE' => const StatusBadge(label: 'Chưa thuê / Tạm ngưng', type: BadgeType.warning),
      'MOVED_OUT' => const StatusBadge(label: 'Đã chuyển đi', type: BadgeType.neutral),
      _ => StatusBadge(label: status.isEmpty ? '—' : status, type: BadgeType.neutral),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, dot) = switch (type) {
      BadgeType.success => (
          AppColors.successLight,
          AppColors.successBorder,
          AppColors.successText,
          AppColors.success,
        ),
      BadgeType.warning => (
          AppColors.warningLight,
          AppColors.warningBorder,
          AppColors.warningText,
          AppColors.warning,
        ),
      BadgeType.error => (
          AppColors.errorLight,
          AppColors.errorBorder,
          AppColors.errorText,
          AppColors.error,
        ),
      BadgeType.reserved => (
          AppColors.reservedLight,
          AppColors.reservedBorder,
          AppColors.reservedText,
          AppColors.reserved,
        ),
      BadgeType.info => (
          AppColors.primaryLight,
          AppColors.primaryBorder,
          AppColors.primaryHover,
          AppColors.secondary,
        ),
      BadgeType.neutral => (
          AppColors.surfaceMuted,
          AppColors.border,
          AppColors.textSecondary,
          AppColors.textMuted,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.labelGap),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: AppTypography.labelSm.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stitch RoleBadge (8px rounded pill, 4px 8px padding, 12px SemiBold).
class RoleBadge extends StatelessWidget {
  final String role;

  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final lower = role.toLowerCase();
    final isAdmin = lower.contains('admin') || lower.contains('quản trị');
    final bg = isAdmin ? AppColors.roleAdminBg : AppColors.roleLandlordBg;
    final fg = isAdmin ? AppColors.roleAdminFg : AppColors.roleLandlordFg;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.badgeRadius),
      ),
      child: Text(
        role,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: AppTypography.labelSm.copyWith(color: fg),
      ),
    );
  }
}
