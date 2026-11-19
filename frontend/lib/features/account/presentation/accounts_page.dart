import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_table.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../providers/auth_provider.dart';

/// ADMIN — Quản lý tài khoản toàn hệ thống (`/accounts`, Identity Service :8001).
/// Chuyển từ trang Cài đặt sang trang riêng. LANDLORD tạo tài khoản khách thuê ngay trong form
/// hồ sơ người thuê (/tenants), không dùng trang này.
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  bool _loadingUsers = false;
  List<Map<String, dynamic>> _users = const [];
  String? _usersError;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadUsers();
    });
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loadingUsers = true;
      _usersError = null;
    });
    try {
      final list = await context.read<AuthProvider>().fetchUsers();
      if (!mounted) return;
      setState(() {
        _users = list;
        _loadingUsers = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _usersError = e.toString();
        _loadingUsers = false;
      });
    }
  }

  void _openUserFormDialog(AuthProvider auth, [Map<String, dynamic>? existing]) {
    final isAdmin = auth.role == 'ADMIN';
    final formKey = GlobalKey<FormState>();
    final usernameCtrl = TextEditingController(text: '${existing?['username'] ?? ''}');
    final passwordCtrl = TextEditingController();
    final firstCtrl = TextEditingController(text: '${existing?['first_name'] ?? ''}');
    final lastCtrl = TextEditingController(text: '${existing?['last_name'] ?? ''}');
    final emailCtrl = TextEditingController(text: '${existing?['email'] ?? ''}');
    final phoneCtrl = TextEditingController(text: '${existing?['phone_number'] ?? ''}');
    String role = '${existing?['role'] ?? 'TENANT'}';
    bool isActive = existing?['is_active'] != false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(
            existing == null ? 'Tạo tài khoản mới' : 'Cập nhật tài khoản',
            style: AppTypography.sectionTitle,
          ),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (existing == null) ...[
                      AppTextField(
                        label: 'Tên đăng nhập',
                        controller: usernameCtrl,
                        requiredField: true,
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        label: 'Mật khẩu',
                        controller: passwordCtrl,
                        requiredField: true,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(child: AppTextField(label: 'Họ', controller: lastCtrl)),
                        const SizedBox(width: 12),
                        Expanded(child: AppTextField(label: 'Tên', controller: firstCtrl)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: AppTextField(label: 'Email', controller: emailCtrl)),
                        const SizedBox(width: 12),
                        Expanded(child: AppTextField(label: 'Số điện thoại', controller: phoneCtrl)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isAdmin) ...[
                      Row(
                        children: [
                          Expanded(
                            child: AppSelect<String>(
                              label: 'Vai trò (Role)',
                              width: null,
                              value: role,
                              options: [
                                const AppSelectOption(value: 'TENANT', label: 'TENANT — Khách thuê'),
                                const AppSelectOption(value: 'LANDLORD', label: 'LANDLORD — Chủ trọ'),
                                const AppSelectOption(value: 'ADMIN', label: 'ADMIN — Quản trị viên'),
                                // STAFF đã ngừng cấp mới (backend chặn); chỉ hiển thị cho tài khoản cũ.
                                if (existing?['role'] == 'STAFF')
                                  const AppSelectOption(value: 'STAFF', label: 'STAFF — (cũ, ngừng sử dụng)'),
                              ],
                              onChanged: (v) => setModalState(() => role = v ?? 'TENANT'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Kích hoạt', style: AppTypography.bodyBold),
                              value: isActive,
                              onChanged: (v) => setModalState(() => isActive = v ?? true),
                            ),
                          ),
                        ],
                      ),
                    ] else
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Chủ trọ chỉ được tạo/cập nhật tài khoản Khách thuê (TENANT).',
                          style: AppTypography.caption,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            AppButton(
              label: 'Hủy',
              variant: AppButtonVariant.outlined,
              onPressed: () => Navigator.pop(ctx),
            ),
            AppButton(
              label: existing == null ? 'Tạo tài khoản' : 'Lưu thay đổi',
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final payload = <String, dynamic>{
                  'first_name': firstCtrl.text.trim(),
                  'last_name': lastCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'phone_number': phoneCtrl.text.trim(),
                  if (existing == null) 'username': usernameCtrl.text.trim(),
                  if (existing == null) 'password': passwordCtrl.text,
                  if (isAdmin) 'role': role,
                  if (isAdmin) 'is_active': isActive,
                };
                final err = existing == null
                    ? await auth.createUser(payload)
                    : await auth.updateUser(existing['id'] as int, payload);
                if (!ctx.mounted || !mounted) return;
                if (err != null) {
                  showErrorToast(context, err);
                  return;
                }
                Navigator.pop(ctx);
                showSuccessToast(
                  context,
                  existing == null ? 'Đã tạo tài khoản thành công.' : 'Đã cập nhật tài khoản.',
                );
                _loadUsers();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteUser(AuthProvider auth, Map<String, dynamic> user) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Xóa tài khoản',
      message: 'Xóa tài khoản "${user['username']}"?',
    );
    if (!confirmed || !mounted) return;
    final err = await auth.deleteUser(user['id'] as int);
    if (!mounted) return;
    if (err != null) {
      showErrorToast(context, err);
      return;
    }
    showSuccessToast(context, 'Đã xóa tài khoản "${user['username']}".');
    _loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Quản lý tài khoản',
          subtitle: 'Tạo, cập nhật, khóa và phân quyền tài khoản ADMIN / LANDLORD / TENANT.',
        ),
          AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Danh sách tài khoản (Identity :8001)',
                            style: AppTypography.sectionTitle,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'ADMIN quản lý toàn bộ tài khoản và vai trò của hệ thống.',
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          AppButton(
                            label: 'Tải lại',
                            compact: true,
                            variant: AppButtonVariant.outlined,
                            isLoading: _loadingUsers,
                            onPressed: _loadUsers,
                          ),
                          AppButton(
                            label: '+ Tạo tài khoản',
                            compact: true,
                            onPressed: () => _openUserFormDialog(auth),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (_usersError != null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Không tải được danh sách tài khoản: $_usersError',
                      style: AppTypography.caption.copyWith(color: AppColors.error),
                    ),
                  )
                else if (_users.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _loadedOnce ? 'Chưa có tài khoản nào.' : 'Đang tải danh sách tài khoản...',
                      key: const Key('accounts_empty_or_loading'),
                      style: AppTypography.caption,
                    ),
                  )
                else
                  AppTable<Map<String, dynamic>>(
                    items: _users,
                    columns: [
                      AppTableColumn(
                        label: 'USERNAME',
                        width: 140,
                        cellBuilder: (u) => CodeBadge('${u['username'] ?? ''}'),
                      ),
                      AppTableColumn(
                        label: 'HỌ TÊN & EMAIL',
                        flex: 2,
                        cellBuilder: (u) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${u['full_name'] ?? u['username'] ?? ''}',
                              style: AppTypography.bodyBold,
                            ),
                            Text('${u['email'] ?? '—'}', style: AppTypography.caption),
                          ],
                        ),
                      ),
                      AppTableColumn(
                        label: 'VAI TRÒ',
                        width: 165,
                        cellBuilder: (u) => RoleBadge(role: '${u['role_display'] ?? u['role'] ?? ''}'),
                      ),
                      AppTableColumn(
                        label: 'TRẠNG THÁI',
                        width: 140,
                        cellBuilder: (u) => StatusBadge(
                          label: u['is_active'] == false ? 'Bị khóa' : 'Hoạt động',
                          type: u['is_active'] == false ? BadgeType.error : BadgeType.success,
                        ),
                      ),
                      AppTableColumn(
                        label: 'THAO TÁC',
                        width: 110,
                        alignment: Alignment.centerRight,
                        cellBuilder: (u) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Chỉnh sửa',
                              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                              onPressed: () => _openUserFormDialog(auth, u),
                            ),
                            if (auth.role == 'ADMIN')
                              IconButton(
                                tooltip: 'Xóa',
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                                onPressed: () => _confirmDeleteUser(auth, u),
                              ),
                          ],
                        ),
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
