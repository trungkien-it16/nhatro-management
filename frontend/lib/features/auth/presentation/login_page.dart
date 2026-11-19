import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/auth_provider.dart';

/// Đăng nhập qua API Gateway -> Identity Service (JWT).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  List<Map<String, dynamic>> _devAccounts = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDevAccounts());
  }

  Future<void> _loadDevAccounts() async {
    if (!mounted) return;
    final accounts = await context.read<AuthProvider>().fetchTestAccounts();
    if (!mounted || accounts.isEmpty) return;
    setState(() => _devAccounts = accounts);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Router tự chuyển sang /dashboard khi AuthProvider báo đã đăng nhập.
    await context.read<AuthProvider>().login(_usernameCtrl.text, _passwordCtrl.text);
  }

  Future<void> _quickLogin(String username, String password) async {
    _usernameCtrl.text = username;
    _passwordCtrl.text = password;
    await context.read<AuthProvider>().login(username, password);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                border: Border.all(color: AppColors.border),
                boxShadow: AppSpacing.shadowLevel2,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.apartment_rounded, size: 40, color: AppColors.primary),
                    const SizedBox(height: AppSpacing.md),
                    const Text('NHÀ TRỌ MANAGER', textAlign: TextAlign.center, style: AppTypography.headlineMd),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Đăng nhập để quản lý nhà trọ của bạn',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    AppTextField(
                      label: 'Tên đăng nhập',
                      controller: _usernameCtrl,
                      requiredField: true,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Mật khẩu',
                      style: AppTypography.captionMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('login_password'),
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      style: AppTypography.body,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Vui lòng nhập Mật khẩu' : null,
                    ),
                    if (auth.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        auth.errorMessage!,
                        style: AppTypography.caption.copyWith(color: AppColors.error),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    AppButton(
                      label: 'Đăng nhập',
                      icon: Icons.login_rounded,
                      isLoading: auth.isLoading,
                      onPressed: auth.isLoading ? null : _submit,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Chưa có tài khoản?', style: AppTypography.caption),
                        TextButton(
                          key: const Key('login_go_register'),
                          onPressed: auth.isLoading ? null : () => context.go('/register'),
                          child: const Text('Đăng ký'),
                        ),
                      ],
                    ),
                    if (_devAccounts.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const Divider(height: 1),
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        'Đăng nhập nhanh (Môi trường Dev)',
                        textAlign: TextAlign.center,
                        style: AppTypography.labelSm,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final acc in _devAccounts)
                            AppButton(
                              label: '${acc['username']} (${acc['role']})',
                              compact: true,
                              variant: AppButtonVariant.outlined,
                              onPressed: auth.isLoading
                                  ? null
                                  : () => _quickLogin(
                                        '${acc['username'] ?? ''}',
                                        '${acc['password'] ?? ''}',
                                      ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'API Gateway: ${ApiConstants.gatewayUrl}',
                      textAlign: TextAlign.center,
                      style: AppTypography.captionSm,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
