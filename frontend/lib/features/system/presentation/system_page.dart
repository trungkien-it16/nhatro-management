import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/role_access.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/soa_services.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_table.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../models/system_health_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../shared/services/app_data_repository.dart';
import '../../dashboard/widgets/service_endpoints_dialog.dart';
import '../../dashboard/widgets/soa_architecture_card.dart';

/// ADMIN — Quản trị hệ thống (`/system`): trạng thái Gateway + 5 service, sơ đồ SOA và
/// catalog endpoint (Gateway chỉ trả catalog cho ADMIN). Chuyển từ trang Cài đặt sang.
class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppDataRepository>();
    final auth = context.watch<AuthProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Quản trị hệ thống',
          subtitle: 'Trạng thái API Gateway, 5 Microservices và danh mục endpoint thực tế.',
          actions: [
            AppButton(
              label: 'Kiểm tra kết nối SOA',
              icon: Icons.sync_rounded,
              isLoading: _syncing,
              variant: AppButtonVariant.outlined,
              onPressed: () async {
                setState(() => _syncing = true);
                await repo.refreshSystemHealth();
                if (context.mounted) {
                  setState(() => _syncing = false);
                  final h = repo.systemHealth;
                  if (h != null && h.gatewayStatus == ServiceStatus.up) {
                    showSuccessToast(
                      context,
                      'API Gateway: ${h.upCount}/${h.services.length} service đang hoạt động',
                    );
                  } else {
                    showErrorToast(context, 'Không kết nối được API Gateway (${ApiConstants.gatewayLabel})');
                  }
                }
              },
            ),
          ],
        ),
        SoaArchitectureCard(
          health: repo.systemHealth,
          isLoading: repo.isSyncing || _syncing,
          onRefresh: repo.refreshSystemHealth,
          onServiceTap: (key, name, port, status) => ServiceEndpointsDialog.show(
            context,
            serviceKey: key,
            name: name,
            port: port,
            healthStatus: status,
            load: repo.fetchServiceEndpoints,
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        // SOA Services Status Table
        AppSurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Danh sách Microservices (Kiến trúc SOA)',
                      style: AppTypography.sectionTitle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mỗi service có Port & Database riêng; Frontend chỉ gọi qua API Gateway ${ApiConstants.gatewayLabel}',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              AppTable<SoaServiceConfig>(
                items: SoaServices.all,
                columns: [
                  AppTableColumn(
                    label: 'TÊN SERVICE',
                    flex: 2,
                    cellBuilder: (s) => Row(
                      children: [
                        Icon(s.icon, size: 18, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(s.name, style: AppTypography.bodySemiBold),
                        ),
                      ],
                    ),
                  ),
                  AppTableColumn(
                    label: 'PORT',
                    width: 110,
                    cellBuilder: (s) => CodeBadge(':${s.port}'),
                  ),
                  AppTableColumn(
                    label: 'ENDPOINT (QUA GATEWAY)',
                    flex: 2,
                    cellBuilder: (s) => Text(s.gatewayEndpoint, style: AppTypography.code),
                  ),
                  AppTableColumn(
                    label: 'DATABASE',
                    width: 180,
                    cellBuilder: (s) => Text(s.database, style: AppTypography.captionMedium),
                  ),
                  AppTableColumn(
                    label: 'TRẠNG THÁI',
                    width: 150,
                    cellBuilder: (s) {
                      final status = repo.systemHealth?.service(s.id)?.status;
                      return switch (status) {
                        ServiceStatus.up => const StatusBadge(label: 'UP', type: BadgeType.success),
                        ServiceStatus.down => const StatusBadge(label: 'DOWN', type: BadgeType.error),
                        ServiceStatus.unknown => const StatusBadge(label: 'UNKNOWN', type: BadgeType.info),
                        null => const StatusBadge(label: 'Chưa kiểm tra', type: BadgeType.info),
                      };
                    },
                  ),
                  AppTableColumn(
                    label: 'ĐIỀU HƯỚNG',
                    width: 120,
                    alignment: Alignment.centerRight,
                    // Chỉ cho mở trang mà vai trò hiện tại được phép (RoleAccess).
                    cellBuilder: (s) => RoleAccess.canAccess(auth.role, s.route)
                        ? AppButton(
                            label: 'Mở trang',
                            compact: true,
                            variant: AppButtonVariant.outlined,
                            onPressed: () => context.go(s.route),
                          )
                        : const Text('—', style: AppTypography.caption),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
