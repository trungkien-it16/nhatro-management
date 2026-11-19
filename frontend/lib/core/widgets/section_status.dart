import 'package:flutter/material.dart';
import '../../shared/services/app_data_repository.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_typography.dart';

/// Trạng thái một danh sách (Dashboard, trang của khách thuê) theo [SectionState] của repository:
/// đang tải / rỗng thật / lỗi (kèm thử lại) / không có quyền. Khi danh sách có dữ liệu cũ mà
/// lần tải mới lỗi thì báo dữ liệu có thể chưa cập nhật. Có dữ liệu bình thường -> không hiển thị gì.
class SectionStatus extends StatelessWidget {
  final SectionState state;
  final bool isEmpty;
  final bool syncing;
  final String what;
  final String emptyText;
  final EdgeInsets padding;
  final VoidCallback? onRetry;

  const SectionStatus({
    super.key,
    required this.state,
    required this.isEmpty,
    required this.syncing,
    required this.what,
    required this.emptyText,
    required this.padding,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final String text;
    var isError = false;
    var loading = false;
    if (!isEmpty) {
      if (!state.isError) return const SizedBox.shrink();
      text = 'Không cập nhật được $what: ${state.message ?? 'lỗi không xác định'}. '
          'Đang hiển thị dữ liệu của lần tải trước.';
      isError = true;
    } else if (state.isForbidden) {
      text = 'Tài khoản của bạn không có quyền xem $what.';
    } else if (state.isError) {
      text = 'Không tải được $what: ${state.message ?? 'lỗi không xác định'}';
      isError = true;
    } else if (state.isLoaded) {
      text = emptyText;
    } else if (state.isLoading || syncing) {
      text = 'Đang tải $what...';
      loading = true;
    } else {
      text = 'Chưa tải được $what.';
    }
    final style = AppTypography.caption.copyWith(color: isError ? AppColors.errorText : null);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (loading) ...[
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (isError) ...[
            const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(child: Text(text, style: style)),
          if (isError && onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Thử lại'),
            ),
        ],
      ),
    );
  }
}
