import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_table.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../shared/models/app_models.dart';
import '../../../shared/services/app_data_repository.dart';
import '../widgets/portal_widgets.dart';

/// TENANT — Hóa đơn của tôi (chỉ xem). Billing Service lọc theo hồ sơ người thuê của tài khoản.
class MyBillsPage extends StatelessWidget {
  const MyBillsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppDataRepository>();
    final unpaid = repo.invoices.where((i) => i.status == 'UNPAID' || i.status == 'OVERDUE').toList();
    final unpaidTotal = unpaid.fold<double>(0, (sum, i) => sum + i.totalAmount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Hóa đơn của tôi',
          subtitle: repo.invoices.isEmpty
              ? 'Hóa đơn tiền phòng, điện, nước của bạn.'
              : '${unpaid.length} hóa đơn cần thanh toán · Tổng ${AppFormatters.currency(unpaidTotal)}',
        ),
        const ReadOnlyNote('Trang chỉ xem. Thanh toán được chủ trọ xác nhận trên hệ thống.'),
        SectionListGate(
          state: repo.sectionState(DataSection.invoices),
          isSyncing: repo.isSyncing,
          lastSyncError: repo.lastSyncError,
          hasData: repo.invoices.isNotEmpty,
          what: 'hóa đơn của bạn',
          keyPrefix: 'my_bills',
          onRetry: repo.syncWithBackend,
          empty: const EmptyState(
            key: Key('my_bills_empty'),
            icon: Icons.receipt_long_outlined,
            title: 'Chưa có hóa đơn',
            subtitle: 'Bạn chưa có hóa đơn nào trên hệ thống.',
          ),
          noMatch: null,
          builder: (_) => AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: AppTable<InvoiceItem>(
              items: repo.invoices,
              columns: [
                AppTableColumn(label: 'MÃ HÓA ĐƠN', width: 140, cellBuilder: (i) => CodeBadge(i.code)),
                AppTableColumn(
                  label: 'KỲ THU',
                  width: 110,
                  cellBuilder: (i) => Text(i.billingMonth, style: AppTypography.body),
                ),
                AppTableColumn(
                  label: 'PHÒNG',
                  flex: 2,
                  cellBuilder: (i) => Text(
                    [i.roomName, i.propertyName].where((e) => e.isNotEmpty).join(' · '),
                    style: AppTypography.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AppTableColumn(
                  label: 'TỔNG TIỀN',
                  width: 150,
                  cellBuilder: (i) => Text(
                    AppFormatters.currency(i.totalAmount),
                    style: AppTypography.bodyBold.copyWith(color: AppColors.secondary),
                  ),
                ),
                AppTableColumn(
                  label: 'HẠN THANH TOÁN',
                  width: 140,
                  cellBuilder: (i) => Text(i.dueDate, style: AppTypography.body),
                ),
                AppTableColumn(
                  label: 'TRẠNG THÁI',
                  width: 150,
                  cellBuilder: (i) => StatusBadge.fromInvoiceStatus(i.status),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
