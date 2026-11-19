import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../theme/app_typography.dart';

class AppSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppSurfaceCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class CodeBadge extends StatelessWidget {
  final String code;
  const CodeBadge(this.code, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(code, style: AppTypography.code),
    );
  }
}

class AppTableColumn<T> {
  final String label;
  final double? width;
  final int flex;
  final Alignment alignment;
  final Widget Function(T item) cellBuilder;

  const AppTableColumn({
    required this.label,
    required this.cellBuilder,
    this.width,
    this.flex = 1,
    this.alignment = Alignment.centerLeft,
  });
}

class AppTable<T> extends StatefulWidget {
  final List<AppTableColumn<T>> columns;
  final List<T> items;
  final void Function(T item)? onRowTap;
  final double minWidth;

  const AppTable({
    super.key,
    required this.columns,
    required this.items,
    this.onRowTap,
    this.minWidth = 920,
  });

  @override
  State<AppTable<T>> createState() => _AppTableState<T>();
}

/// Bảng rộng hơn màn hình (tablet / mobile / cửa sổ hẹp): cuộn ngang và LUÔN hiện thanh cuộn,
/// để người dùng thấy còn cột bên phải thay vì tưởng nội dung bị cắt.
class _AppTableState<T> extends State<AppTable<T>> {
  /// Bề rộng tối thiểu cho mỗi đơn vị `flex`. 80px giúp các bảng nhiều cột (vd. Người thuê: 7 cột)
  /// vừa màn hình desktop 1440px (vùng nội dung ~1116px) mà không phải cuộn ngang để thấy cột THAO TÁC.
  static const double _minFlexUnit = 80;

  final ScrollController _hScroll = ScrollController();

  List<AppTableColumn<T>> get columns => widget.columns;
  List<T> get items => widget.items;
  void Function(T item)? get onRowTap => widget.onRowTap;
  double get minWidth => widget.minWidth;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colsMinWidth = columns.fold<double>(
          40.0,
          (sum, col) => sum + (col.width ?? col.flex * _minFlexUnit),
        );
        final targetMinWidth =
            colsMinWidth > minWidth ? colsMinWidth : minWidth;
        final effectiveWidth = constraints.maxWidth < targetMinWidth
            ? targetMinWidth
            : constraints.maxWidth;

        final overflows = effectiveWidth > constraints.maxWidth;

        final table = SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.only(bottom: overflows ? 10 : 0),
          child: SizedBox(
            width: effectiveWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    border: Border(
                      bottom: BorderSide(color: AppColors.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      for (final col in columns)
                        _buildHeaderCell(col),
                    ],
                  ),
                ),
                for (int i = 0; i < items.length; i++)
                  _TableRowItem<T>(
                    item: items[i],
                    columns: columns,
                    isLast: i == items.length - 1,
                    onTap: onRowTap != null ? () => onRowTap!(items[i]) : null,
                  ),
              ],
            ),
          ),
        );
        if (!overflows) return table;
        return Scrollbar(
          key: const Key('app_table_hscrollbar'),
          controller: _hScroll,
          thumbVisibility: true,
          trackVisibility: true,
          child: table,
        );
      },
    );
  }

  Widget _buildHeaderCell(AppTableColumn<T> col) {
    final child = Align(
      alignment: col.alignment,
      child: Text(col.label, style: AppTypography.tableHeader),
    );
    if (col.width != null) {
      return SizedBox(width: col.width, child: child);
    }
    return Expanded(flex: col.flex, child: child);
  }
}

class _TableRowItem<T> extends StatefulWidget {
  final T item;
  final List<AppTableColumn<T>> columns;
  final bool isLast;
  final VoidCallback? onTap;

  const _TableRowItem({
    required this.item,
    required this.columns,
    required this.isLast,
    this.onTap,
  });

  @override
  State<_TableRowItem<T>> createState() => _TableRowItemState<T>();
}

class _TableRowItemState<T> extends State<_TableRowItem<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.background : AppColors.surface,
            border: widget.isLast
                ? null
                : const Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              for (final col in widget.columns)
                col.width != null
                    ? SizedBox(
                        width: col.width,
                        child: Align(
                          alignment: col.alignment,
                          child: col.cellBuilder(widget.item),
                        ),
                      )
                    : Expanded(
                        flex: col.flex,
                        child: Align(
                          alignment: col.alignment,
                          child: col.cellBuilder(widget.item),
                        ),
                      ),
            ],
          ),
        ),
      ),
    );
  }
}

