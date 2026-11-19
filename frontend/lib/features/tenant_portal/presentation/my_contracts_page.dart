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

/// TENANT — Hợp đồng của tôi (chỉ xem). Contract Service lọc theo hồ sơ người thuê của tài khoản.
class MyContractsPage extends StatelessWidget {
  const MyContractsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppDataRepository>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Hợp đồng của tôi',
          subtitle: 'Các hợp đồng thuê phòng đứng tên bạn.',
        ),
        const ReadOnlyNote('Trang chỉ xem. Tạo, gia hạn hoặc chấm dứt hợp đồng do chủ trọ thực hiện.'),
        SectionListGate(
          state: repo.sectionState(DataSection.contracts),
          isSyncing: repo.isSyncing,
          lastSyncError: repo.lastSyncError,
          hasData: repo.contracts.isNotEmpty,
          what: 'hợp đồng của bạn',
          keyPrefix: 'my_contracts',
          onRetry: repo.syncWithBackend,
          empty: const EmptyState(
            key: Key('my_contracts_empty'),
            icon: Icons.description_outlined,
            title: 'Chưa có hợp đồng',
            subtitle: 'Bạn chưa có hợp đồng thuê phòng nào trên hệ thống.',
          ),
          noMatch: null,
          builder: (_) => AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: AppTable<ContractItem>(
              items: repo.contracts,
              columns: [
                AppTableColumn(label: 'SỐ HỢP ĐỒNG', width: 150, cellBuilder: (c) => CodeBadge(c.code)),
                AppTableColumn(
                  label: 'PHÒNG',
                  flex: 2,
                  cellBuilder: (c) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.roomName, style: AppTypography.bodyMedium),
                      Text(c.propertyName, style: AppTypography.caption, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                AppTableColumn(
                  label: 'THỜI HẠN',
                  width: 200,
                  cellBuilder: (c) => Text('${c.startDate} → ${c.endDate}', style: AppTypography.body),
                ),
                AppTableColumn(
                  label: 'GIÁ THUÊ',
                  width: 140,
                  cellBuilder: (c) => Text(
                    AppFormatters.currency(c.rentPrice),
                    style: AppTypography.bodyBold.copyWith(color: AppColors.secondary),
                  ),
                ),
                AppTableColumn(
                  label: 'TIỀN CỌC',
                  width: 140,
                  cellBuilder: (c) => Text(AppFormatters.currency(c.depositAmount), style: AppTypography.body),
                ),
                AppTableColumn(
                  label: 'TRẠNG THÁI',
                  width: 150,
                  cellBuilder: (c) => StatusBadge.fromContractStatus(c.status),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
