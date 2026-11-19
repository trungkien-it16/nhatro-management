import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/role_access.dart';
import '../../../core/widgets/state_views.dart';
import '../../../providers/auth_provider.dart';

/// Hiển thị khi người dùng mở (vd. gõ thẳng URL) một trang vai trò của họ không được dùng.
class ForbiddenPage extends StatelessWidget {
  final String? attemptedPath;

  const ForbiddenPage({super.key, this.attemptedPath});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final target = (attemptedPath == null || attemptedPath!.isEmpty) ? 'trang này' : 'trang "$attemptedPath"';
    return EmptyState(
      key: const Key('forbidden_page'),
      icon: Icons.lock_outline_rounded,
      title: 'Không có quyền truy cập',
      subtitle: 'Tài khoản ${auth.roleDisplay} không được phép mở $target. '
          '${RoleAccess.audienceFor(attemptedPath ?? '')}',
      actionLabel: 'Về trang chính',
      onAction: () => context.go(RoleAccess.homeFor(auth.role)),
    );
  }
}
