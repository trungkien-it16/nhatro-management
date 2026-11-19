import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_table.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../shared/services/app_data_repository.dart';

class NotificationPage extends StatelessWidget {
  const NotificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppDataRepository>();
    final items = repo.notifications;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Thông báo',
          subtitle: 'Cập nhật tức thời về hóa đơn đến hạn, hợp đồng sắp hết hạn và yêu cầu bảo trì.',
          actions: [
            AppButton(
              label: 'Đánh dấu tất cả đã đọc',
              icon: Icons.done_all_rounded,
              variant: AppButtonVariant.outlined,
              onPressed: repo.unreadNotificationCount == 0
                  ? null
                  : () async {
                      final err = await repo.markAllNotificationsRead();
                      if (!context.mounted) return;
                      if (err != null) {
                        showErrorToast(context, err);
                        return;
                      }
                      showSuccessToast(context, 'Đã đánh dấu tất cả thông báo là đã đọc');
                    },
            ),
          ],
        ),
        // Chỉ nói "chưa có thông báo" khi Notification Service thật sự trả về danh sách rỗng.
        SectionListGate(
          state: repo.sectionState(DataSection.notifications),
          isSyncing: repo.isSyncing,
          lastSyncError: repo.lastSyncError,
          hasData: items.isNotEmpty,
          what: 'danh sách thông báo',
          keyPrefix: 'notification_list',
          onRetry: repo.syncWithBackend,
          empty: const EmptyState(
            key: Key('notification_list_empty'),
            icon: Icons.notifications_none_rounded,
            title: 'Chưa có thông báo mới',
            subtitle: 'Tất cả hoạt động hệ thống sẽ được hiển thị tại đây.',
          ),
          noMatch: null,
          builder: (_) => AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = items[index];
                return InkWell(
                  onTap: () async {
                    final err = await repo.markNotificationRead(n.id);
                    if (!context.mounted) return;
                    if (err != null) showErrorToast(context, err);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    color: n.isRead ? AppColors.surface : AppColors.primaryLight.withValues(alpha: 0.45),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: n.isRead ? AppColors.surfaceMuted : AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            switch (n.category) {
                              'BILLING' => Icons.receipt_long_outlined,
                              'CONTRACT' => Icons.description_outlined,
                              'MAINTENANCE' => Icons.build_outlined,
                              _ => Icons.notifications_none_rounded,
                            },
                            size: 20,
                            color: n.isRead ? AppColors.textSecondary : AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      n.title,
                                      style: n.isRead
                                          ? AppTypography.bodyMedium
                                          : AppTypography.bodySemiBold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  StatusBadge(
                                    label: n.isRead ? 'Đã đọc' : 'Mới',
                                    type: n.isRead ? BadgeType.neutral : BadgeType.info,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(n.message, style: AppTypography.body),
                              const SizedBox(height: 6),
                              Text(n.createdAt, style: AppTypography.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

