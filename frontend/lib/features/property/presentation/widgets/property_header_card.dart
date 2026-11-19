import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Stitch Property Header Card:
/// - Upper banner with Deep Blue (#1E3A8A) to Royal Blue (#2563EB) gradient
///   and 20% white-opacity summary pills.
/// - Lower body with recessed #F8FAFC inner stats strip (10px radius, 1px #E2E8F0 border).
class PropertyHeaderCard extends StatelessWidget {
  final int totalProperties;
  final int activeProperties;
  final int totalRooms;
  final int occupiedRooms;
  final int availableRooms;
  final int maintenanceRooms;

  /// false khi danh sách tòa nhà / phòng chưa tải được: hiển thị "—" thay vì 0 như số thật.
  final bool propertyStatsAvailable;
  final bool roomStatsAvailable;

  const PropertyHeaderCard({
    super.key,
    required this.totalProperties,
    required this.activeProperties,
    required this.totalRooms,
    required this.occupiedRooms,
    required this.availableRooms,
    required this.maintenanceRooms,
    this.propertyStatsAvailable = true,
    this.roomStatsAvailable = true,
  });

  @override
  Widget build(BuildContext context) {
    final occupancyRate =
        totalRooms > 0 ? ((occupiedRooms / totalRooms) * 100).round() : 0;
    String rooms(int v) => roomStatsAvailable ? '$v' : '—';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppSpacing.shadowLevel1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Upper gradient banner
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.secondary],
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.md,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Danh mục Tòa nhà & Cơ sở cho thuê',
                      style: AppTypography.titleLg.copyWith(
                        color: AppColors.surface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Theo dõi công suất khai thác, trạng thái vận hành và phân bổ phòng trên toàn hệ thống',
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.surface.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _BannerPill(
                      icon: Icons.apartment_rounded,
                      label: propertyStatsAvailable
                          ? '$activeProperties/$totalProperties tòa nhà hoạt động'
                          : '— tòa nhà hoạt động',
                    ),
                    _BannerPill(
                      icon: Icons.meeting_room_outlined,
                      label: '${rooms(totalRooms)} phòng quản lý',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lower recessed stats strip
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final items = [
                    _StripMetric(
                      label: 'Phòng còn trống',
                      value: '${rooms(availableRooms)} phòng',
                      valueColor: AppColors.successText,
                    ),
                    _StripMetric(
                      label: 'Đang khai thác',
                      value: '${rooms(occupiedRooms)} phòng',
                      valueColor: AppColors.secondary,
                    ),
                    _StripMetric(
                      label: 'Đang bảo trì',
                      value: '${rooms(maintenanceRooms)} phòng',
                      valueColor: AppColors.warningText,
                    ),
                    _StripMetric(
                      label: 'Tỷ lệ lấp đầy',
                      value: roomStatsAvailable ? '$occupancyRate%' : '—',
                      valueColor: AppColors.primary,
                    ),
                  ];

                  if (constraints.maxWidth < 600) {
                    return Wrap(
                      spacing: AppSpacing.xl,
                      runSpacing: AppSpacing.md,
                      children: [
                        for (final item in items)
                          SizedBox(
                            width: ((constraints.maxWidth - AppSpacing.xl) / 2)
                                .clamp(100.0, double.infinity),
                            child: item,
                          ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        Expanded(child: items[i]),
                        if (i < items.length - 1)
                          Container(
                            width: 1,
                            height: 32,
                            margin: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            color: AppColors.border,
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _BannerPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.labelGap,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.surface),
          const SizedBox(width: AppSpacing.labelGap),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSm.copyWith(color: AppColors.surface),
            ),
          ),
        ],
      ),
    );
  }
}

class _StripMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _StripMetric({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelSm),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: AppTypography.titleMd.copyWith(color: valueColor),
        ),
      ],
    );
  }
}
