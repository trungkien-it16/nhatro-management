import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_table.dart';
import '../../../../shared/models/app_models.dart';

class MonthlyRevenueChart extends StatelessWidget {
  final List<MonthlyRevenuePoint> points;

  const MonthlyRevenueChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final maxVal = points.isEmpty
        ? 100.0
        : points
            .map((e) => e.amountInMillions)
            .reduce((a, b) => a > b ? a : b)
            .clamp(10.0, 9999.0);

    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Doanh thu theo tháng', style: AppTypography.sectionTitle),
                    SizedBox(height: 4),
                    Text(
                      'Đơn vị: Triệu VNĐ (6 tháng gần nhất)',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '+5.7% so với tháng trước',
                  style: AppTypography.captionMedium.copyWith(
                    color: AppColors.successText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < points.length; i++)
                  Expanded(
                    child: _BarColumn(
                      point: points[i],
                      ratio: (points[i].amountInMillions / (maxVal * 1.15)).clamp(0.1, 1.0),
                      isLatest: i == points.length - 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarColumn extends StatelessWidget {
  final MonthlyRevenuePoint point;
  final double ratio;
  final bool isLatest;

  const _BarColumn({
    required this.point,
    required this.ratio,
    required this.isLatest,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '${point.amountInMillions.toStringAsFixed(1)}tr',
            style: AppTypography.caption.copyWith(
              fontSize: 11,
              fontWeight: isLatest ? FontWeight.w700 : FontWeight.w500,
              color: isLatest ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: ratio,
                widthFactor: 0.62,
                child: Container(
                  decoration: BoxDecoration(
                    color: isLatest
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.22),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            point.monthLabel,
            style: AppTypography.captionMedium.copyWith(
              color: isLatest ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: isLatest ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
