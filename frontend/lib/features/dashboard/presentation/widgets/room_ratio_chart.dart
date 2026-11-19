import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_table.dart';

class RoomRatioChart extends StatelessWidget {
  final int occupied;
  final int available;
  final int maintenance;

  /// Phòng ở trạng thái khác (đặt trước / ngưng khai thác) — để tổng khớp `total_rooms` của API.
  final int other;

  const RoomRatioChart({
    super.key,
    required this.occupied,
    required this.available,
    required this.maintenance,
    this.other = 0,
  });

  @override
  Widget build(BuildContext context) {
    final sum = occupied + available + maintenance + other;
    final total = sum.clamp(1, 99999);
    final occPct = (occupied / total * 100).round();
    final availPct = (available / total * 100).round();
    final maintPct = (maintenance / total * 100).round();
    final otherPct = (other / total * 100).round();

    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tỷ lệ trạng thái phòng',
            style: AppTypography.sectionTitle,
          ),
          const SizedBox(height: 4),
          const Text(
            'Phân bổ công suất khai thác phòng hiện tại',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 24),
          // Hẹp (điện thoại / cột nhỏ): donut ở trên, chú giải ở dưới; rộng: đặt cạnh nhau.
          LayoutBuilder(
            builder: (context, constraints) {
              final donut = SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(140, 140),
                      painter: _DonutChartPainter(
                        occupied: occupied.toDouble(),
                        available: available.toDouble(),
                        maintenance: maintenance.toDouble(),
                        other: other.toDouble(),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$sum',
                          key: const Key('room_ratio_total'),
                          style: AppTypography.statValue,
                        ),
                        const Text('Tổng phòng', style: AppTypography.caption),
                      ],
                    ),
                  ],
                ),
              );
              final legend = Column(
                children: [
                  _LegendRow(
                    color: AppColors.primary,
                    label: 'Phòng đang thuê',
                    count: occupied,
                    percent: occPct,
                  ),
                  const SizedBox(height: 14),
                  _LegendRow(
                    color: AppColors.success,
                    label: 'Phòng trống',
                    count: available,
                    percent: availPct,
                  ),
                  const SizedBox(height: 14),
                  _LegendRow(
                    color: AppColors.warning,
                    label: 'Phòng bảo trì',
                    count: maintenance,
                    percent: maintPct,
                  ),
                  if (other > 0) ...[
                    const SizedBox(height: 14),
                    _LegendRow(
                      color: AppColors.textMuted,
                      label: 'Đặt trước / ngưng khai thác',
                      count: other,
                      percent: otherPct,
                    ),
                  ],
                ],
              );
              if (constraints.maxWidth < 380) {
                return Column(
                  children: [donut, const SizedBox(height: 20), legend],
                );
              }
              return Row(
                children: [
                  donut,
                  const SizedBox(width: 24),
                  Expanded(child: legend),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final int percent;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.count,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count phòng ($percent%)',
              style: AppTypography.captionMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent / 100.0,
            minHeight: 6,
            backgroundColor: AppColors.surfaceMuted,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final double occupied;
  final double available;
  final double maintenance;
  final double other;

  _DonutChartPainter({
    required this.occupied,
    required this.available,
    required this.maintenance,
    required this.other,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = occupied + available + maintenance + other;
    final strokeWidth = 18.0;
    final rect =
        Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);

    final bgPaint = Paint()
      ..color = AppColors.surfaceMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawArc(rect, 0, math.pi * 2, false, bgPaint);
    if (total <= 0) return;

    double startAngle = -math.pi / 2;
    final segments = [
      (occupied, AppColors.primary),
      (available, AppColors.success),
      (maintenance, AppColors.warning),
      (other, AppColors.textMuted),
    ];

    for (final seg in segments) {
      if (seg.$1 <= 0) continue;
      final sweep = (seg.$1 / total) * math.pi * 2;
      final paint = Paint()
        ..color = seg.$2
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.occupied != occupied ||
        oldDelegate.available != available ||
        oldDelegate.maintenance != maintenance ||
        oldDelegate.other != other;
  }
}
