import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/role_access.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_table.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/section_status.dart';
import '../../../core/widgets/simple_list_row.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../providers/auth_provider.dart';
import '../../../shared/services/app_data_repository.dart';
import '../widgets/portal_widgets.dart';

/// Dashboard cá nhân của TENANT: phòng đang thuê, hợp đồng, hóa đơn, thông báo — chỉ dữ liệu của mình
/// (backend lọc theo liên kết hồ sơ người thuê). Không có số liệu cứng; chưa tải được -> "—".
class TenantDashboard extends StatelessWidget {
  const TenantDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppDataRepository>();
    final auth = context.watch<AuthProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final cols = AppResponsive.statGridCrossAxisCount(width);
    final canRetry = repo.isBackendConnected;
    Future<void> retry() => repo.syncWithBackend();

    String count(DataSection section, int value) {
      final st = repo.sectionState(section);
      if (st.hasData || st.isLoaded) return '$value';
      return st.isLoading || repo.isSyncing ? '…' : '—';
    }

    final activeContracts = repo.contracts
        .where((c) => const {'ACTIVE', 'EXTENDED', 'EXPIRING'}.contains(c.status))
        .length;
    final unpaid = repo.invoices.where((i) => i.status == 'UNPAID' || i.status == 'OVERDUE').toList();
    final unpaidTotal = unpaid.fold<double>(0, (sum, i) => sum + i.totalAmount);
    final room = repo.rooms.firstOrNull;
    final property = room == null ? null : repo.properties.where((p) => p.id == room.propertyId).firstOrNull;

    final stats = [
      StatCard(
        title: 'Phòng đang thuê',
        value: count(DataSection.rooms, repo.rooms.length),
        subtitle: room == null ? 'Chưa có phòng đang thuê' : '${room.name} · ${room.propertyName}',
        icon: Icons.door_front_door_outlined,
        onTap: () => context.go(RoleAccess.myRoom),
      ),
      StatCard(
        title: 'Hợp đồng hiệu lực',
        value: count(DataSection.contracts, activeContracts),
        subtitle: 'Tổng ${repo.contracts.length} hợp đồng',
        icon: Icons.description_outlined,
        onTap: () => context.go(RoleAccess.myContracts),
      ),
      StatCard(
        title: 'Hóa đơn cần thanh toán',
        value: count(DataSection.invoices, unpaid.length),
        subtitle: unpaid.isEmpty ? 'Không có khoản cần thanh toán' : 'Tổng ${AppFormatters.currency(unpaidTotal)}',
        icon: Icons.receipt_long_outlined,
        tone: unpaid.isEmpty ? StatIconTone.neutral : StatIconTone.warning,
        onTap: () => context.go(RoleAccess.myBills),
      ),
      StatCard(
        title: 'Thông báo chưa đọc',
        value: count(DataSection.notifications, repo.unreadNotificationCount),
        subtitle: 'Tổng ${repo.notifications.length} thông báo',
        icon: Icons.notifications_none_rounded,
        tone: StatIconTone.neutral,
        onTap: () => context.go(RoleAccess.notifications),
      ),
    ];

    return Column(
      key: const Key('tenant_dashboard'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Xin chào, ${auth.displayName}',
          subtitle: 'Tổng quan phòng đang thuê, hợp đồng, hóa đơn và thông báo của bạn.',
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: AppSpacing.lg,
            mainAxisSpacing: AppSpacing.lg,
            mainAxisExtent: 140,
          ),
          itemBuilder: (_, i) => stats[i],
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Phòng đang thuê
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle(
                title: 'Phòng đang thuê',
                actionLabel: 'Chi tiết',
                onAction: () => context.go(RoleAccess.myRoom),
              ),
              SectionStatus(
                key: const Key('tenant_dashboard_room_status'),
                state: repo.sectionState(DataSection.rooms),
                isEmpty: repo.rooms.isEmpty,
                syncing: repo.isSyncing,
                what: 'phòng đang thuê',
                emptyText: 'Bạn chưa có phòng đang thuê.',
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                onRetry: canRetry ? retry : null,
              ),
              if (room != null) ...[
                InfoRow('Phòng', '${room.name} (${room.code})'),
                InfoRow('Nhà trọ', property?.name ?? room.propertyName),
                InfoRow('Địa chỉ', property?.displayAddress ?? ''),
                InfoRow('Giá thuê / tháng', AppFormatters.currency(room.rentPrice)),
                const InfoRow('Liên hệ chủ trọ', 'Hệ thống chưa cung cấp thông tin liên hệ chủ trọ cho khách thuê.'),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Hợp đồng
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle(
                title: 'Hợp đồng của tôi',
                actionLabel: 'Xem tất cả',
                onAction: () => context.go(RoleAccess.myContracts),
              ),
              SectionStatus(
                key: const Key('tenant_dashboard_contract_status'),
                state: repo.sectionState(DataSection.contracts),
                isEmpty: repo.contracts.isEmpty,
                syncing: repo.isSyncing,
                what: 'hợp đồng',
                emptyText: 'Bạn chưa có hợp đồng nào.',
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                onRetry: canRetry ? retry : null,
              ),
              for (final c in repo.contracts.take(3))
                SimpleListRow(
                  title: '${c.code} · ${c.roomName}',
                  subtitle: '${c.startDate} → ${c.endDate}',
                  trailing: StatusBadge.fromContractStatus(c.status),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Hóa đơn gần đây
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle(
                title: 'Hóa đơn gần đây',
                actionLabel: 'Xem tất cả',
                onAction: () => context.go(RoleAccess.myBills),
              ),
              SectionStatus(
                key: const Key('tenant_dashboard_invoice_status'),
                state: repo.sectionState(DataSection.invoices),
                isEmpty: repo.invoices.isEmpty,
                syncing: repo.isSyncing,
                what: 'hóa đơn',
                emptyText: 'Bạn chưa có hóa đơn nào.',
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                onRetry: canRetry ? retry : null,
              ),
              for (final i in repo.invoices.take(5))
                SimpleListRow(
                  title: '${i.code} · Kỳ ${i.billingMonth}',
                  subtitle: '${AppFormatters.currency(i.totalAmount)} · Hạn ${i.dueDate.isEmpty ? '—' : i.dueDate}',
                  trailing: StatusBadge.fromInvoiceStatus(i.status),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Thông báo mới
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle(
                title: 'Thông báo mới',
                actionLabel: 'Xem tất cả',
                onAction: () => context.go(RoleAccess.notifications),
              ),
              SectionStatus(
                key: const Key('tenant_dashboard_notification_status'),
                state: repo.sectionState(DataSection.notifications),
                isEmpty: repo.notifications.isEmpty,
                syncing: repo.isSyncing,
                what: 'thông báo',
                emptyText: 'Chưa có thông báo nào.',
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                onRetry: canRetry ? retry : null,
              ),
              for (final n in repo.notifications.take(5))
                SimpleListRow(
                  leading: Icon(
                    n.isRead ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
                    size: 20,
                  ),
                  title: n.title,
                  subtitle: n.message,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  const _CardTitle({required this.title, required this.actionLabel, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppTypography.sectionTitle)),
        AppButton(label: actionLabel, compact: true, variant: AppButtonVariant.outlined, onPressed: onAction),
      ],
    );
  }
}
