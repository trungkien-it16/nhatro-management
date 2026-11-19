import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/auth_provider.dart';
import '../../../shared/services/api_client.dart';

/// "Nguyễn Văn An" -> first_name "Nguyễn Văn", last_name "An" (theo quy ước dữ liệu hiện có;
/// backend ghép lại full_name = "first_name last_name").
(String, String) splitFullName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return ('', '');
  if (parts.length == 1) return (parts.first, '');
  return (parts.sublist(0, parts.length - 1).join(' '), parts.last);
}

/// Đăng ký tài khoản qua API Gateway -> Identity Service (POST /auth/register/).
///
/// Chỉ gửi các trường backend hỗ trợ (RegisterSerializer): username, password, email,
/// first_name, last_name, phone_number, role. Chỉ cho chọn LANDLORD / TENANT; backend
/// cũng từ chối ADMIN/STAFF. Đăng ký xong KHÔNG tự đăng nhập: người dùng quay lại màn đăng nhập.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static const _minPasswordLength = 6; // AUTH_PASSWORD_VALIDATORS của Identity Service
  static final _usernamePattern = RegExp(r'^[\p{L}\p{N}_.@+\-]+$', unicode: true);
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phonePattern = RegExp(r'^[0-9+\-.\s()]+$');

  /// Tên trường backend -> trường trên form (họ tên được tách thành first_name/last_name).
  static const _fieldOf = {
    'username': 'username',
    'email': 'email',
    'phone_number': 'phone',
    'password': 'password',
    'first_name': 'fullName',
    'last_name': 'fullName',
    'role': 'role',
  };

  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String? _role;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  bool _roleMissing = false;
  String? _generalError;
  Map<String, String> _serverErrors = const {};
  Map<String, dynamic>? _created;

  @override
  void dispose() {
    for (final c in [_fullNameCtrl, _usernameCtrl, _emailCtrl, _phoneCtrl, _passwordCtrl, _confirmCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return; // chặn bấm liên tục
    setState(() {
      _serverErrors = const {};
      _generalError = null;
      _roleMissing = _role == null;
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || _role == null) return;

    final (firstName, lastName) = splitFullName(_fullNameCtrl.text);
    final payload = <String, dynamic>{
      'username': _usernameCtrl.text.trim(),
      'password': _passwordCtrl.text,
      'first_name': firstName,
      'last_name': lastName,
      'role': _role,
      if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
      if (_phoneCtrl.text.trim().isNotEmpty) 'phone_number': _phoneCtrl.text.trim(),
    };

    setState(() => _submitting = true);
    try {
      final created = await context.read<AuthProvider>().register(payload);
      if (!mounted) return;
      setState(() => _created = created);
    } on ApiException catch (e) {
      if (!mounted) return;
      _applyServerErrors(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _applyServerErrors(ApiException e) {
    final fieldErrors = <String, String>{};
    final general = <String>[];
    final body = e.body;
    if (e.statusCode == 400 && body is Map) {
      for (final entry in body.entries) {
        final value = entry.value;
        final msg = value is List && value.isNotEmpty ? '${value.first}' : (value is String ? value : null);
        if (msg == null) continue;
        final field = _fieldOf['${entry.key}'];
        if (field != null) {
          fieldErrors.putIfAbsent(field, () => msg);
        } else {
          general.add(msg);
        }
      }
    }
    setState(() {
      _serverErrors = fieldErrors;
      _generalError = general.isNotEmpty
          ? general.join('\n')
          : (fieldErrors.isEmpty ? e.message : 'Đăng ký chưa thành công, vui lòng kiểm tra các trường bị lỗi.');
    });
  }

  void _clearServerError(String field) {
    if (!_serverErrors.containsKey(field)) return;
    setState(() => _serverErrors = Map.of(_serverErrors)..remove(field));
  }

  // ---------------------------------------------------------------- validators
  String? _validateFullName(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Vui lòng nhập Họ và tên';
    final (first, last) = splitFullName(s);
    if (first.length > 150 || last.length > 150) return 'Họ và tên quá dài';
    return null;
  }

  String? _validateUsername(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Vui lòng nhập Tên đăng nhập';
    if (s.length > 150) return 'Tên đăng nhập tối đa 150 ký tự';
    if (!_usernamePattern.hasMatch(s)) {
      return 'Tên đăng nhập chỉ gồm chữ, số và các ký tự @ . + - _ (không có khoảng trắng)';
    }
    return null;
  }

  String? _validateEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return null; // không bắt buộc
    if (!_emailPattern.hasMatch(s)) return 'Email không hợp lệ';
    return null;
  }

  String? _validatePhone(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return null; // không bắt buộc
    if (s.length > 20) return 'Số điện thoại tối đa 20 ký tự';
    if (!_phonePattern.hasMatch(s)) return 'Số điện thoại không hợp lệ';
    return null;
  }

  String? _validatePassword(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Vui lòng nhập Mật khẩu';
    if (s.length < _minPasswordLength) return 'Mật khẩu phải có ít nhất $_minPasswordLength ký tự';
    return null;
  }

  String? _validateConfirm(String? v) {
    if ((v ?? '').isEmpty) return 'Vui lòng nhập lại Mật khẩu';
    if (v != _passwordCtrl.text) return 'Mật khẩu nhập lại không khớp';
    return null;
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                border: Border.all(color: AppColors.border),
                boxShadow: AppSpacing.shadowLevel2,
              ),
              child: _created != null ? _buildSuccess() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    final username = '${_created?['username'] ?? _usernameCtrl.text.trim()}';
    final role = '${_created?['role'] ?? _role}';
    final roleText = role == 'TENANT' ? 'Khách thuê' : 'Chủ nhà trọ';
    return Column(
      key: const Key('register_success'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded, size: 48, color: AppColors.success),
        const SizedBox(height: AppSpacing.md),
        const Text('Đăng ký thành công', textAlign: TextAlign.center, style: AppTypography.headlineMd),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Tài khoản "$username" ($roleText) đã được tạo. Hãy đăng nhập bằng tên đăng nhập và mật khẩu vừa đăng ký.',
          textAlign: TextAlign.center,
          style: AppTypography.body,
        ),
        const SizedBox(height: AppSpacing.xxl),
        AppButton(
          label: 'Đến trang đăng nhập',
          icon: Icons.login_rounded,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.apartment_rounded, size: 40, color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          const Text('Tạo tài khoản', textAlign: TextAlign.center, style: AppTypography.headlineMd),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Đăng ký tài khoản Chủ nhà trọ hoặc Khách thuê',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.xxl),
          _label('Bạn là', required: true),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            key: const Key('register_role'),
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 'LANDLORD',
                icon: Icon(Icons.home_work_outlined, size: 18),
                label: Text('Chủ nhà trọ', key: Key('register_role_landlord')),
              ),
              ButtonSegment(
                value: 'TENANT',
                icon: Icon(Icons.person_outline_rounded, size: 18),
                label: Text('Khách thuê', key: Key('register_role_tenant')),
              ),
            ],
            selected: _role == null ? <String>{} : {_role!},
            onSelectionChanged: _submitting
                ? null
                : (s) => setState(() {
                      _role = s.isEmpty ? null : s.first;
                      _roleMissing = false;
                      _serverErrors = Map.of(_serverErrors)..remove('role');
                    }),
          ),
          if (_roleMissing || _serverErrors['role'] != null) ...[
            const SizedBox(height: 6),
            Text(
              _serverErrors['role'] ?? 'Vui lòng chọn vai trò',
              key: const Key('register_role_error'),
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _field(
            key: 'fullName',
            label: 'Họ và tên',
            controller: _fullNameCtrl,
            required: true,
            validator: _validateFullName,
            hint: 'VD: Nguyễn Văn An',
            autofill: AutofillHints.name,
          ),
          _field(
            key: 'username',
            label: 'Tên đăng nhập',
            controller: _usernameCtrl,
            required: true,
            validator: _validateUsername,
            autofill: AutofillHints.newUsername,
          ),
          _field(
            key: 'email',
            label: 'Email',
            controller: _emailCtrl,
            validator: _validateEmail,
            keyboard: TextInputType.emailAddress,
            autofill: AutofillHints.email,
          ),
          _field(
            key: 'phone',
            label: 'Số điện thoại',
            controller: _phoneCtrl,
            validator: _validatePhone,
            keyboard: TextInputType.phone,
            autofill: AutofillHints.telephoneNumber,
          ),
          _field(
            key: 'password',
            label: 'Mật khẩu',
            controller: _passwordCtrl,
            required: true,
            validator: _validatePassword,
            obscure: _obscurePassword,
            onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
            hint: 'Ít nhất $_minPasswordLength ký tự',
            autofill: AutofillHints.newPassword,
          ),
          _field(
            key: 'confirm',
            label: 'Nhập lại mật khẩu',
            controller: _confirmCtrl,
            required: true,
            validator: _validateConfirm,
            obscure: _obscureConfirm,
            onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
            onSubmitted: _submit,
          ),
          if (_generalError != null) ...[
            Container(
              key: const Key('register_error'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.errorBorder),
              ),
              child: Text(_generalError!, style: AppTypography.caption.copyWith(color: AppColors.errorText)),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const Key('register_submit'),
            label: 'Đăng ký',
            icon: Icons.person_add_alt_1_rounded,
            isLoading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Đã có tài khoản?', style: AppTypography.caption),
              TextButton(
                key: const Key('register_go_login'),
                onPressed: _submitting ? null : () => context.go('/login'),
                child: const Text('Đăng nhập'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'API Gateway: ${ApiConstants.gatewayUrl}',
            textAlign: TextAlign.center,
            style: AppTypography.captionSm,
          ),
        ],
      ),
    );
  }

  Widget _label(String text, {bool required = false}) {
    return Row(
      children: [
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.captionMedium.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
        if (required) Text(' *', style: AppTypography.captionMedium.copyWith(color: AppColors.error)),
      ],
    );
  }

  /// Ô nhập cùng kiểu với AppTextField, thêm: lỗi từ backend, ẩn/hiện mật khẩu, Key cho test.
  Widget _field({
    required String key,
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    bool required = false,
    bool? obscure,
    VoidCallback? onToggleObscure,
    VoidCallback? onSubmitted,
    TextInputType? keyboard,
    String? hint,
    String? autofill,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(label, required: required),
          const SizedBox(height: 6),
          TextFormField(
            key: Key('register_$key'),
            controller: controller,
            enabled: !_submitting,
            obscureText: obscure ?? false,
            keyboardType: keyboard,
            style: AppTypography.body,
            autofillHints: autofill == null ? null : [autofill],
            textInputAction: onSubmitted != null ? TextInputAction.done : TextInputAction.next,
            onChanged: (_) => _clearServerError(key),
            onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
            forceErrorText: _serverErrors[key],
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              suffixIcon: obscure == null
                  ? null
                  : IconButton(
                      key: Key('register_${key}_toggle'),
                      tooltip: obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                      icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: onToggleObscure,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
