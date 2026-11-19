import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_table.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../providers/auth_provider.dart';
import '../../../shared/services/app_data_repository.dart';
import '../widgets/portal_widgets.dart';

/// TENANT — Hồ sơ của tôi (chỉ xem): tài khoản đăng nhập (Identity) + hồ sơ người thuê (Tenant Service,
/// chỉ hồ sơ gắn với user_id của chính tài khoản này).
class MyProfilePage extends StatelessWidget {
  const MyProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppDataRepository>();
    final auth = context.watch<AuthProvider>();
    final user = auth.user ?? const <String, dynamic>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Hồ sơ của tôi',
          subtitle: 'Thông tin tài khoản và hồ sơ người thuê do chủ trọ quản lý.',
        ),
        const ReadOnlyNote(
          'Hồ sơ người thuê chỉ xem; liên hệ chủ trọ nếu cần sửa. '
          'Thông tin tài khoản và mật khẩu cập nhật ở mục Cài đặt.',
        ),
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tài khoản đăng nhập', style: AppTypography.sectionTitle),
              const SizedBox(height: AppSpacing.md),
              InfoRow('Tên đăng nhập', '${user['username'] ?? ''}'),
              InfoRow('Họ tên', auth.displayName),
              InfoRow('Email', '${user['email'] ?? ''}'),
              InfoRow('Số điện thoại', '${user['phone_number'] ?? ''}'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        SectionListGate(
          state: repo.sectionState(DataSection.tenants),
          isSyncing: repo.isSyncing,
          lastSyncError: repo.lastSyncError,
          hasData: repo.tenants.isNotEmpty,
          what: 'hồ sơ người thuê',
          keyPrefix: 'my_profile',
          onRetry: repo.syncWithBackend,
          empty: const EmptyState(
            key: Key('my_profile_empty'),
            icon: Icons.badge_outlined,
            title: 'Chưa có hồ sơ người thuê',
            subtitle: 'Tài khoản của bạn chưa được chủ trọ liên kết với hồ sơ người thuê nào.',
          ),
          noMatch: null,
          builder: (_) => Column(
            children: [
              for (final t in repo.tenants) ...[
                AppSurfaceCard(
                  key: Key('my_profile_card_${t.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Hồ sơ người thuê', style: AppTypography.sectionTitle),
                          StatusBadge.fromTenantStatus(t.status),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      InfoRow('Họ và tên', t.fullName),
                      InfoRow('Số điện thoại', t.phone),
                      InfoRow('Email', t.email),
                      InfoRow('CCCD / CMND', t.idCard),
                      InfoRow('Phòng', [t.currentRoom, t.propertyName].where((e) => e.isNotEmpty).join(' · ')),
                      InfoRow('Nghề nghiệp', t.occupation),
                      InfoRow('Địa chỉ thường trú', t.permanentAddress),
                      InfoRow('Liên hệ khẩn cấp',
                          [t.emergencyContactName, t.emergencyContactPhone].where((e) => e.isNotEmpty).join(' · ')),
                      InfoRow('Tạm trú', t.temporaryResidenceRegistered ? 'Đã đăng ký' : 'Chưa đăng ký'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
