import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../theme/app_typography.dart';
import '../../shared/services/api_client.dart';
import '../../shared/services/app_data_repository.dart';
import 'app_button.dart';
import 'app_table.dart';

class LoadingState extends StatelessWidget {
  final String message;
  const LoadingState({super.key, this.message = 'Đang tải dữ liệu...'});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(message, style: AppTypography.captionMedium),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Text(title, style: AppTypography.cardTitle),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTypography.caption,
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            AppButton(
              label: actionLabel!,
              icon: Icons.add_rounded,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.error_outline_rounded, color: AppColors.error),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Không thể tải dữ liệu', style: AppTypography.cardTitle),
                const SizedBox(height: 2),
                Text(message, style: AppTypography.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Thử lại',
            icon: Icons.refresh_rounded,
            variant: AppButtonVariant.outlined,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

void showSuccessToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      width: 420,
      backgroundColor: AppColors.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.surface),
            ),
          ),
        ],
      ),
    ),
  );
}

void showErrorToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      width: 440,
      backgroundColor: AppColors.errorText,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.surface, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.surface),
            ),
          ),
        ],
      ),
    ),
  );
}


/// Cảnh báo khi lần tải mới nhất của một nhóm dữ liệu lỗi nhưng vẫn còn dữ liệu thật
/// của lần tải trước đang hiển thị. Có nút "Thử lại" gọi lại cơ chế đồng bộ.
class StaleDataBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const StaleDataBanner({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warningText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: AppTypography.bodyMd.copyWith(color: AppColors.warningText)),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}

/// Hiển thị đúng trạng thái của một danh sách lấy từ một nhóm dữ liệu (DataSection) của repository.
/// Thứ tự: có dữ liệu (kể cả dữ liệu cũ, kèm cảnh báo nếu lần tải mới lỗi) -> không có quyền (403)
/// -> lỗi -> đang tải (chỉ khi thực sự có lượt tải đang chạy) -> chưa tải -> rỗng thật.
/// Không bao giờ coi lỗi / 403 / chưa tải là "danh sách rỗng".
class SectionListGate extends StatelessWidget {
  final SectionState state;
  final bool isSyncing;
  final String? lastSyncError;

  /// Repository đang có dữ liệu của nhóm này (có thể là dữ liệu của lần tải thành công trước).
  final bool hasData;

  /// Tên nhóm dữ liệu trong câu thông báo, VD "danh sách hợp đồng".
  final String what;

  /// Tiền tố key cho các trạng thái: `<keyPrefix>_forbidden`, `_error`, `_loading`, `_not_loaded`, `_stale`.
  final String keyPrefix;
  final VoidCallback onRetry;

  /// Hiển thị khi backend thật sự trả về danh sách rỗng.
  final Widget empty;

  /// Hiển thị khi có dữ liệu nhưng không có mục nào khớp bộ lọc; null nghĩa là có kết quả.
  final Widget? noMatch;

  /// Danh sách (chỉ dựng khi có dữ liệu và có kết quả).
  final WidgetBuilder builder;

  const SectionListGate({
    super.key,
    required this.state,
    required this.isSyncing,
    required this.lastSyncError,
    required this.hasData,
    required this.what,
    required this.keyPrefix,
    required this.onRetry,
    required this.empty,
    required this.noMatch,
    required this.builder,
  });

  String get _message => state.message ?? 'lỗi không xác định';

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (!(hasData && state.isError)) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaleDataBanner(
          key: Key('${keyPrefix}_stale'),
          message: 'Không cập nhật được $what: $_message. Đang hiển thị dữ liệu của lần tải trước.',
          onRetry: onRetry,
        ),
        body,
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (hasData) return noMatch ?? builder(context);
    if (state.isForbidden) {
      return EmptyState(
        key: Key('${keyPrefix}_forbidden'),
        icon: Icons.lock_outline_rounded,
        title: 'Không có quyền xem $what',
        subtitle: 'Tài khoản của bạn không được cấp quyền truy cập dữ liệu này.',
      );
    }
    if (state.isError) {
      return ErrorState(
        key: Key('${keyPrefix}_error'),
        message: 'Không tải được $what: $_message',
        onRetry: onRetry,
      );
    }
    if (state.isLoading || (isSyncing && !state.isLoaded)) {
      return LoadingState(key: Key('${keyPrefix}_loading'), message: 'Đang tải $what...');
    }
    if (!state.isLoaded) {
      // Chưa tải và không có lượt tải nào đang chạy: không giả vờ "đang tải", không nói "rỗng".
      return ErrorState(
        key: Key('${keyPrefix}_not_loaded'),
        message: lastSyncError ?? 'Chưa tải được $what.',
        onRetry: onRetry,
      );
    }
    return empty;
  }
}

/// Tải một danh sách theo yêu cầu (VD lịch sử trong hộp thoại) và hiển thị đủ trạng thái:
/// đang tải, lỗi (kèm Thử lại), không có quyền (403), rỗng thật, có dữ liệu.
/// Hộp thoại mở ngay, không chờ request xong.
class HistoryLoader<T> extends StatefulWidget {
  final Future<List<T>> Function() load;

  /// Tên dữ liệu trong câu thông báo, VD "lịch sử thuê phòng".
  final String what;
  final String emptyText;
  final Widget Function(BuildContext context, List<T> items) builder;

  const HistoryLoader({
    super.key,
    required this.load,
    required this.what,
    required this.emptyText,
    required this.builder,
  });

  @override
  State<HistoryLoader<T>> createState() => _HistoryLoaderState<T>();
}

class _HistoryLoaderState<T> extends State<HistoryLoader<T>> {
  late Future<List<T>> _future = _start();

  /// Gọi tải. Lỗi có thể đến trước khi FutureBuilder dựng lại để lắng nghe: đánh dấu đã có người nghe
  /// để không thành lỗi "chưa xử lý"; FutureBuilder vẫn nhận lỗi và hiển thị nó.
  Future<List<T>> _start() {
    final f = widget.load();
    f.ignore();
    return f;
  }

  void _retry() {
    final next = _start();
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Row(
            key: const Key('history_loading'),
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text('Đang tải ${widget.what}...', style: AppTypography.caption),
            ],
          );
        }
        final error = snap.error;
        if (error != null) {
          if (error is ApiException && error.statusCode == 403) {
            return Text(
              'Tài khoản của bạn không có quyền xem ${widget.what}.',
              key: const Key('history_forbidden'),
              style: AppTypography.caption,
            );
          }
          return Row(
            key: const Key('history_error'),
            children: [
              Expanded(
                child: Text(
                  'Không tải được ${widget.what}: $error',
                  style: AppTypography.caption.copyWith(color: AppColors.error),
                ),
              ),
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Thử lại'),
              ),
            ],
          );
        }
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return Text(widget.emptyText, key: const Key('history_empty'), style: AppTypography.caption);
        }
        return widget.builder(context, items);
      },
    );
  }
}
