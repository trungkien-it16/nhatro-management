import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/config/sprint_features.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_table.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/pagination_widget.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../shared/models/app_models.dart';
import '../../../shared/services/app_data_repository.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  final _searchCtrl = TextEditingController();
  String _monthFilter = 'ALL';
  String _statusFilter = 'ALL';
  int _page = 1;
  static const int _pageSize = 6;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openInvoiceForm([InvoiceItem? existing]) {
    final repo = context.read<AppDataRepository>();
    final formKey = GlobalKey<FormState>();
    final codeCtrl = TextEditingController(
      text: existing?.code ?? 'HDN-202611-0${repo.invoices.length + 1}',
    );
    final monthCtrl = TextEditingController(text: '${existing?.month ?? 11}');
    final yearCtrl = TextEditingController(text: '${existing?.year ?? 2026}');
    final roomFeeCtrl = TextEditingController(
      text: '${(existing?.roomFee ?? 3500000).toInt()}',
    );
    final elecOldCtrl = TextEditingController(text: '${existing?.electricityOld ?? 100}');
    final elecNewCtrl = TextEditingController(text: '${existing?.electricityNew ?? 150}');
    final elecPriceCtrl = TextEditingController(
      text: '${(existing?.electricityUnitPrice ?? 3500).toInt()}',
    );
    final waterOldCtrl = TextEditingController(text: '${existing?.waterOld ?? 20}');
    final waterNewCtrl = TextEditingController(text: '${existing?.waterNew ?? 28}');
    final waterPriceCtrl = TextEditingController(
      text: '${(existing?.waterUnitPrice ?? 18000).toInt()}',
    );
    final otherFeeCtrl = TextEditingController(
      text: '${(existing?.otherServiceCost ?? 100000).toInt()}',
    );
    final dueCtrl = TextEditingController(text: existing?.dueDate ?? '2026-11-25');
    int? selectedRoomId = existing?.roomId ?? (repo.rooms.isNotEmpty ? repo.rooms.first.id : null);
    int? selectedTenantId =
        existing?.tenantId ?? (repo.tenants.isNotEmpty ? repo.tenants.first.id : null);

    double calcTotal() {
      final rf = double.tryParse(roomFeeCtrl.text.trim()) ?? 0;
      final eOld = int.tryParse(elecOldCtrl.text.trim()) ?? 0;
      final eNew = int.tryParse(elecNewCtrl.text.trim()) ?? 0;
      final eP = double.tryParse(elecPriceCtrl.text.trim()) ?? 0;
      final wOld = int.tryParse(waterOldCtrl.text.trim()) ?? 0;
      final wNew = int.tryParse(waterNewCtrl.text.trim()) ?? 0;
      final wP = double.tryParse(waterPriceCtrl.text.trim()) ?? 0;
      final other = double.tryParse(otherFeeCtrl.text.trim()) ?? 0;
      final eCost = (eNew > eOld ? (eNew - eOld) : 0) * eP;
      final wCost = (wNew > wOld ? (wNew - wOld) : 0) * wP;
      return rf + eCost + wCost + other;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(
            existing == null ? 'Lập hóa đơn mới' : 'Cập nhật hóa đơn',
            style: AppTypography.sectionTitle,
          ),
          content: SizedBox(
            width: 600,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Mã hóa đơn (tự sinh nếu trống)',
                            controller: codeCtrl,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Tháng (1–12)',
                            controller: monthCtrl,
                            requiredField: true,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Năm',
                            controller: yearCtrl,
                            requiredField: true,
                            isNumber: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppSelect<int?>(
                            label: 'Phòng *',
                            width: null,
                            value: repo.rooms.any((r) => r.id == selectedRoomId)
                                ? selectedRoomId
                                : null,
                            options: [
                              const AppSelectOption<int?>(value: null, label: 'Chọn phòng...'),
                              for (final r in repo.rooms)
                                AppSelectOption<int?>(
                                  value: r.id,
                                  label: '${r.name} — ${r.propertyName}',
                                ),
                            ],
                            onChanged: (v) {
                              final matched = v != null
                                  ? repo.rooms.where((r) => r.id == v).firstOrNull
                                  : null;
                              setModalState(() {
                                selectedRoomId = v;
                                if (matched != null && existing == null) {
                                  roomFeeCtrl.text = '${matched.rentPrice.toInt()}';
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppSelect<int?>(
                            label: 'Người thuê *',
                            width: null,
                            value: repo.tenants.any((t) => t.id == selectedTenantId)
                                ? selectedTenantId
                                : null,
                            options: [
                              const AppSelectOption<int?>(value: null, label: 'Chọn người thuê...'),
                              for (final t in repo.tenants)
                                AppSelectOption<int?>(value: t.id, label: t.fullName),
                            ],
                            onChanged: (v) => setModalState(() => selectedTenantId = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Tiền phòng (VNĐ)',
                            controller: roomFeeCtrl,
                            requiredField: true,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Phí dịch vụ khác (VNĐ)',
                            controller: otherFeeCtrl,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Hạn thanh toán (YYYY-MM-DD)',
                            controller: dueCtrl,
                            requiredField: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Điện số cũ (kWh)',
                            controller: elecOldCtrl,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Điện số mới (kWh)',
                            controller: elecNewCtrl,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Đơn giá điện',
                            controller: elecPriceCtrl,
                            isNumber: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Nước số cũ (m³)',
                            controller: waterOldCtrl,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Nước số mới (m³)',
                            controller: waterNewCtrl,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Đơn giá nước',
                            controller: waterPriceCtrl,
                            isNumber: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(AppSpacing.badgeRadius),
                        border: Border.all(color: AppColors.primaryBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () => setModalState(() {}),
                            icon: const Icon(Icons.calculate_outlined, size: 16),
                            label: const Text('Tính lại tạm tính'),
                          ),
                          Text(
                            'Tổng dự kiến: ${AppFormatters.currency(calcTotal())}',
                            style: AppTypography.titleMd.copyWith(color: AppColors.primary),
                          ),
                        ],
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
              label: existing == null ? 'Lập hóa đơn' : 'Lưu thay đổi',
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final eOld = int.tryParse(elecOldCtrl.text.trim()) ?? 0;
                final eNew = int.tryParse(elecNewCtrl.text.trim()) ?? 0;
                final wOld = int.tryParse(waterOldCtrl.text.trim()) ?? 0;
                final wNew = int.tryParse(waterNewCtrl.text.trim()) ?? 0;
                if (eNew < eOld || wNew < wOld) {
                  showErrorToast(context, 'Chỉ số điện/nước mới không được nhỏ hơn chỉ số cũ.');
                  return;
                }

                final room = selectedRoomId != null
                    ? repo.rooms.where((r) => r.id == selectedRoomId).firstOrNull
                    : null;
                final tenant = selectedTenantId != null
                    ? repo.tenants.where((t) => t.id == selectedTenantId).firstOrNull
                    : null;
                final month = (int.tryParse(monthCtrl.text.trim()) ?? 11).clamp(1, 12);
                final year = int.tryParse(yearCtrl.text.trim()) ?? 2026;
                final rf = double.tryParse(roomFeeCtrl.text.trim()) ?? 0;
                final ePrice = double.tryParse(elecPriceCtrl.text.trim()) ?? 3500;
                final wPrice = double.tryParse(waterPriceCtrl.text.trim()) ?? 18000;
                final other = double.tryParse(otherFeeCtrl.text.trim()) ?? 0;
                final eCost = (eNew - eOld) * ePrice;
                final wCost = (wNew - wOld) * wPrice;
                final total = rf + eCost + wCost + other;

                final item = InvoiceItem(
                  id: existing?.id ?? DateTime.now().millisecondsSinceEpoch,
                  roomId: selectedRoomId,
                  tenantId: selectedTenantId,
                  contractId: existing?.contractId,
                  code: codeCtrl.text.trim(),
                  tenantName: tenant?.fullName ?? existing?.tenantName ?? '—',
                  roomName: room?.name ?? existing?.roomName ?? '—',
                  propertyName: room?.propertyName ?? existing?.propertyName ?? '',
                  month: month,
                  year: year,
                  billingMonth: '$month/$year',
                  roomFee: rf,
                  electricityOld: eOld,
                  electricityNew: eNew,
                  electricityUnitPrice: ePrice,
                  electricityCost: eCost,
                  waterOld: wOld,
                  waterNew: wNew,
                  waterUnitPrice: wPrice,
                  waterCost: wCost,
                  otherServiceCost: other,
                  totalAmount: total,
                  dueDate: dueCtrl.text.trim(),
                  status: existing?.status ?? 'UNPAID',
                );

                final err = existing == null
                    ? await repo.addInvoice(item)
                    : await repo.updateInvoice(item);
                if (!ctx.mounted || !mounted) return;
                if (err != null) {
                  showErrorToast(context, err);
                  return;
                }
                Navigator.pop(ctx);
                showSuccessToast(
                  context,
                  existing == null
                      ? 'Đã lập hóa đơn "${codeCtrl.text.trim()}"'
                      : 'Đã cập nhật hóa đơn "${codeCtrl.text.trim()}"',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markPaid(InvoiceItem item) async {
    final err = await context.read<AppDataRepository>().payInvoice(item.id);
    if (!mounted) return;
    if (err != null) {
      showErrorToast(context, err);
      return;
    }
    showSuccessToast(context, 'Đã xác nhận thanh toán cho hóa đơn ${item.code}');
  }

  Future<void> _cancelInvoice(InvoiceItem item) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Hủy hóa đơn',
      message: 'Bạn có chắc chắn muốn hủy hóa đơn "${item.code}"?',
    );
    if (!confirmed || !mounted) return;
    final err = await context.read<AppDataRepository>().cancelInvoice(item.id);
    if (!mounted) return;
    if (err != null) {
      showErrorToast(context, err);
      return;
    }
    showSuccessToast(context, 'Đã hủy hóa đơn ${item.code}');
  }

  Future<void> _confirmDelete(InvoiceItem item) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Xóa hóa đơn',
      message: 'Bạn có chắc chắn muốn xóa hóa đơn "${item.code}" của khách ${item.tenantName}?',
    );
    if (!confirmed || !mounted) return;
    final err = await context.read<AppDataRepository>().deleteInvoice(item.id);
    if (!mounted) return;
    if (err != null) {
      showErrorToast(context, err);
      return;
    }
    showSuccessToast(context, 'Đã xóa hóa đơn "${item.code}"');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppDataRepository>();
    final query = _searchCtrl.text.trim().toLowerCase();

    final filtered = repo.invoices.where((i) {
      final matchesMonth = _monthFilter == 'ALL' || i.billingMonth == _monthFilter;
      final matchesStatus = _statusFilter == 'ALL' || i.status == _statusFilter;
      final matchesQuery = query.isEmpty ||
          i.code.toLowerCase().contains(query) ||
          i.tenantName.toLowerCase().contains(query) ||
          i.roomName.toLowerCase().contains(query);
      return matchesMonth && matchesStatus && matchesQuery;
    }).toList();

    // Sau khi xóa / lọc, số trang có thể giảm: không để trang hiện tại vượt quá trang cuối.
    final pageCount = filtered.isEmpty ? 1 : (filtered.length + _pageSize - 1) ~/ _pageSize;
    final page = _page.clamp(1, pageCount);
    final start = ((page - 1) * _pageSize).clamp(0, filtered.length);
    final end = (page * _pageSize).clamp(0, filtered.length);
    final paged = filtered.sublist(start, end);
    final hasFilter = query.isNotEmpty || _monthFilter != 'ALL' || _statusFilter != 'ALL';

    // Bộ lọc tháng lấy từ kỳ thu THẬT của các hóa đơn đã tải (mới nhất trước), không cố định.
    final months = <String, (int, int)>{
      for (final i in repo.invoices)
        if (i.billingMonth.isNotEmpty) i.billingMonth: (i.year, i.month),
    };
    final monthKeys = months.keys.toList()
      ..sort((a, b) {
        final (ya, ma) = months[a]!;
        final (yb, mb) = months[b]!;
        return ya != yb ? yb.compareTo(ya) : mb.compareTo(ma);
      });
    // Tháng đang chọn không còn trong dữ liệu (vd. sau khi tải lại) -> vẫn giữ để không lỗi lựa chọn.
    if (_monthFilter != 'ALL' && !months.containsKey(_monthFilter)) monthKeys.insert(0, _monthFilter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Hóa đơn',
          subtitle: 'Quản lý hóa đơn tiền thuê phòng, điện, nước và theo dõi công nợ hàng tháng.',
          actions: [
            // Lập hóa đơn đang tạm khóa ở backend (Sprint hiện tại) -> ẩn nút, giữ source.
            if (SprintFeatures.invoiceWrite)
              AppButton(
                label: '+ Lập hóa đơn',
                onPressed: () => _openInvoiceForm(),
              ),
          ],
        ),

        AppSurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppSearchBar(
                controller: _searchCtrl,
                hintText: 'Tìm theo mã hóa đơn, người thuê, phòng...',
                onChanged: (_) => setState(() => _page = 1),
              ),
              AppSelect<String>(
                label: 'Tháng',
                width: 165,
                value: _monthFilter,
                options: [
                  const AppSelectOption(value: 'ALL', label: 'Tất cả các tháng'),
                  for (final m in monthKeys) AppSelectOption(value: m, label: 'Tháng $m'),
                ],
                onChanged: (v) => setState(() {
                  _monthFilter = v ?? 'ALL';
                  _page = 1;
                }),
              ),
              AppSelect<String>(
                label: 'Trạng thái',
                width: 190,
                value: _statusFilter,
                options: const [
                  AppSelectOption(value: 'ALL', label: 'Tất cả trạng thái'),
                  AppSelectOption(value: 'PAID', label: 'Đã thanh toán'),
                  AppSelectOption(value: 'UNPAID', label: 'Chưa thanh toán'),
                  AppSelectOption(value: 'OVERDUE', label: 'Quá hạn'),
                  AppSelectOption(value: 'CANCELLED', label: 'Đã hủy'),
                ],
                onChanged: (v) => setState(() {
                  _statusFilter = v ?? 'ALL';
                  _page = 1;
                }),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        SectionListGate(
          state: repo.sectionState(DataSection.invoices),
          isSyncing: repo.isSyncing,
          lastSyncError: repo.lastSyncError,
          hasData: repo.invoices.isNotEmpty,
          what: 'danh sách hóa đơn',
          keyPrefix: 'invoice_list',
          onRetry: repo.syncWithBackend,
          empty: EmptyState(
            key: const Key('invoice_list_empty'),
            icon: Icons.receipt_long_outlined,
            title: 'Chưa có hóa đơn nào',
            subtitle: 'Hệ thống chưa có hóa đơn nào trong phạm vi quản lý của bạn.',
            actionLabel: SprintFeatures.invoiceWrite ? '+ Lập hóa đơn' : null,
            onAction: SprintFeatures.invoiceWrite ? () => _openInvoiceForm() : null,
          ),
          noMatch: filtered.isNotEmpty
              ? null
              : EmptyState(
                  key: const Key('invoice_list_no_match'),
                  icon: Icons.search_off_rounded,
                  title: 'Chưa có hóa đơn nào phù hợp',
                  subtitle: 'Không có hóa đơn nào khớp với tháng, trạng thái hoặc từ khóa đã chọn.',
                  actionLabel: hasFilter ? 'Đặt lại bộ lọc' : null,
                  onAction: hasFilter
                      ? () => setState(() {
                            _searchCtrl.clear();
                            _monthFilter = 'ALL';
                            _statusFilter = 'ALL';
                            _page = 1;
                          })
                      : null,
                ),
          builder: (_) => AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                AppTable<InvoiceItem>(
                  items: paged,
                  columns: [
                    AppTableColumn(
                      label: 'MÃ HÓA ĐƠN',
                      width: 145,
                      cellBuilder: (i) => CodeBadge(i.code),
                    ),
                    AppTableColumn(
                      label: 'NGƯỜI THUÊ',
                      flex: 2,
                      cellBuilder: (i) => Text(i.tenantName, style: AppTypography.bodySemiBold),
                    ),
                    AppTableColumn(
                      label: 'PHÒNG',
                      flex: 2,
                      cellBuilder: (i) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(i.roomName, style: AppTypography.bodyMedium),
                          Text(
                            i.propertyName,
                            style: AppTypography.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AppTableColumn(
                      label: 'THÁNG',
                      width: 105,
                      cellBuilder: (i) => Text(i.billingMonth, style: AppTypography.bodyMedium),
                    ),
                    AppTableColumn(
                      label: 'TỔNG TIỀN',
                      width: 145,
                      cellBuilder: (i) => Text(
                        AppFormatters.currency(i.totalAmount),
                        style: AppTypography.bodySemiBold,
                      ),
                    ),
                    AppTableColumn(
                      label: 'HẠN THANH TOÁN',
                      width: 135,
                      cellBuilder: (i) => Text(i.dueDate, style: AppTypography.body),
                    ),
                    AppTableColumn(
                      label: 'TRẠNG THÁI',
                      width: 150,
                      cellBuilder: (i) => StatusBadge.fromInvoiceStatus(i.status),
                    ),
                    if (SprintFeatures.invoiceWrite)
                    AppTableColumn(
                      label: 'THAO TÁC',
                      width: 170,
                      alignment: Alignment.centerRight,
                      cellBuilder: (i) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i.status == 'UNPAID' || i.status == 'OVERDUE')
                            IconButton(
                              tooltip: 'Xác nhận đã thu tiền',
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 19,
                                color: AppColors.success,
                              ),
                              onPressed: () => _markPaid(i),
                            ),
                          if (i.status != 'PAID' && i.status != 'CANCELLED')
                            IconButton(
                              tooltip: 'Hủy hóa đơn',
                              icon: const Icon(
                                Icons.block_rounded,
                                size: 18,
                                color: AppColors.warningText,
                              ),
                              onPressed: () => _cancelInvoice(i),
                            ),
                          if (i.status != 'PAID' && i.status != 'CANCELLED')
                            IconButton(
                              tooltip: 'Chỉnh sửa',
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              onPressed: () => _openInvoiceForm(i),
                            ),
                          IconButton(
                            tooltip: 'Xóa',
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppColors.error,
                            ),
                            onPressed: () => _confirmDelete(i),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                PaginationWidget(
                  currentPage: page,
                  totalItems: filtered.length,
                  pageSize: _pageSize,
                  onPageChanged: (p) => setState(() => _page = p),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

