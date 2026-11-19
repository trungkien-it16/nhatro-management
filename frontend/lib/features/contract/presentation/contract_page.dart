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

class ContractPage extends StatefulWidget {
  const ContractPage({super.key});

  @override
  State<ContractPage> createState() => _ContractPageState();
}

class _ContractPageState extends State<ContractPage> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'ALL';
  int _page = 1;
  static const int _pageSize = 6;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openContractForm([ContractItem? existing]) {
    final repo = context.read<AppDataRepository>();
    final formKey = GlobalKey<FormState>();
    final codeCtrl = TextEditingController(
      text: existing?.code ?? 'HD-2026-0${repo.contracts.length + 10}',
    );
    final startCtrl = TextEditingController(text: existing?.startDate ?? '2026-11-01');
    final endCtrl = TextEditingController(text: existing?.endDate ?? '2027-11-01');
    final rentCtrl = TextEditingController(text: '${existing?.rentPrice.toInt() ?? 3800000}');
    final depCtrl = TextEditingController(text: '${existing?.depositAmount.toInt() ?? 7600000}');
    final billDayCtrl = TextEditingController(text: '${existing?.billingDayOfMonth ?? 5}');
    final termsCtrl = TextEditingController(text: existing?.termsAndConditions ?? '');
    int? selectedRoomId = existing?.roomId ?? (repo.rooms.isNotEmpty ? repo.rooms.first.id : null);
    int? selectedTenantId =
        existing?.tenantId ?? (repo.tenants.isNotEmpty ? repo.tenants.first.id : null);
    String status = existing?.status ?? 'ACTIVE';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(
            existing == null ? 'Tạo hợp đồng thuê mới' : 'Cập nhật hợp đồng',
            style: AppTypography.sectionTitle,
          ),
          content: SizedBox(
            width: 560,
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
                            label: 'Mã hợp đồng',
                            controller: codeCtrl,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: existing == null
                              ? AppSelect<String>(
                                  label: 'Trạng thái khởi tạo',
                                  width: null,
                                  value: status == 'DRAFT' ? 'DRAFT' : 'ACTIVE',
                                  options: const [
                                    AppSelectOption(value: 'ACTIVE', label: 'ACTIVE — Hiệu lực ngay'),
                                    AppSelectOption(value: 'DRAFT', label: 'DRAFT — Bản nháp'),
                                  ],
                                  onChanged: (v) => setModalState(() => status = v ?? 'ACTIVE'),
                                )
                              : AppTextField(
                                  label: 'Ngày thu tiền (1–28)',
                                  controller: billDayCtrl,
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppSelect<int?>(
                            label: 'Phòng thuê *',
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
                            onChanged: (v) => setModalState(() => selectedRoomId = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Ngày bắt đầu (YYYY-MM-DD)',
                            controller: startCtrl,
                            requiredField: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Ngày kết thúc (YYYY-MM-DD)',
                            controller: endCtrl,
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
                            label: 'Giá thuê (VNĐ/tháng)',
                            controller: rentCtrl,
                            requiredField: true,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Tiền đặt cọc (VNĐ)',
                            controller: depCtrl,
                            requiredField: true,
                            isNumber: true,
                          ),
                        ),
                      ],
                    ),
                    if (existing == null) ...[
                      const SizedBox(height: 12),
                      AppTextField(
                        label: 'Ngày thu tiền hàng tháng (1–28)',
                        controller: billDayCtrl,
                        isNumber: true,
                      ),
                    ],
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Điều khoản hợp đồng',
                      controller: termsCtrl,
                      maxLines: 2,
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
              label: existing == null ? 'Tạo hợp đồng' : 'Lưu thay đổi',
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final room = selectedRoomId != null
                    ? repo.rooms.where((r) => r.id == selectedRoomId).firstOrNull
                    : null;
                final tenant = selectedTenantId != null
                    ? repo.tenants.where((t) => t.id == selectedTenantId).firstOrNull
                    : null;
                final rent = double.tryParse(rentCtrl.text.trim()) ?? 0;
                final dep = double.tryParse(depCtrl.text.trim()) ?? 0;
                final billDay = (int.tryParse(billDayCtrl.text.trim()) ?? 5).clamp(1, 28);

                final item = ContractItem(
                  id: existing?.id ?? DateTime.now().millisecondsSinceEpoch,
                  roomId: selectedRoomId,
                  tenantId: selectedTenantId,
                  code: codeCtrl.text.trim(),
                  tenantName: tenant?.fullName ?? existing?.tenantName ?? '—',
                  roomName: room?.name ?? existing?.roomName ?? '—',
                  propertyName: room?.propertyName ?? existing?.propertyName ?? '',
                  startDate: startCtrl.text.trim(),
                  endDate: endCtrl.text.trim(),
                  rentPrice: rent,
                  depositAmount: dep,
                  billingDayOfMonth: billDay,
                  status: existing?.status ?? status,
                  termsAndConditions: termsCtrl.text.trim(),
                );
                final err = existing == null
                    ? await repo.addContract(item)
                    : await repo.updateContract(item);
                if (!ctx.mounted || !mounted) return;
                if (err != null) {
                  showErrorToast(context, err);
                  return;
                }
                Navigator.pop(ctx);
                showSuccessToast(
                  context,
                  existing == null
                      ? 'Đã tạo hợp đồng "${codeCtrl.text.trim()}"'
                      : 'Đã cập nhật hợp đồng "${codeCtrl.text.trim()}"',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _activateContract(ContractItem item) async {
    final err = await context.read<AppDataRepository>().activateContract(item.id);
    if (!mounted) return;
    if (err != null) {
      showErrorToast(context, err);
      return;
    }
    showSuccessToast(context, 'Đã kích hoạt hợp đồng ${item.code}');
  }

  void _openExtendDialog(ContractItem item) {
    final formKey = GlobalKey<FormState>();
    final endCtrl = TextEditingController(text: '2028-01-01');
    final priceCtrl = TextEditingController(text: '${item.rentPrice.toInt()}');
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Gia hạn hợp đồng: ${item.code}', style: AppTypography.sectionTitle),
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: 'Ngày kết thúc mới (YYYY-MM-DD)',
                  controller: endCtrl,
                  requiredField: true,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Giá thuê mới (VNĐ/tháng)',
                  controller: priceCtrl,
                  isNumber: true,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Ghi chú gia hạn',
                  controller: noteCtrl,
                ),
              ],
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
            label: 'Xác nhận gia hạn',
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final err = await context.read<AppDataRepository>().extendContract(
                    item.id,
                    newEndDate: endCtrl.text.trim(),
                    rentalPrice: double.tryParse(priceCtrl.text.trim()),
                    note: noteCtrl.text.trim(),
                  );
              if (!ctx.mounted || !mounted) return;
              if (err != null) {
                showErrorToast(context, err);
                return;
              }
              Navigator.pop(ctx);
              showSuccessToast(context, 'Đã gia hạn hợp đồng ${item.code}');
            },
          ),
        ],
      ),
    );
  }

  void _openTerminateDialog(ContractItem item) {
    final dateCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Thanh lý / Kết thúc: ${item.code}', style: AppTypography.sectionTitle),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: 'Ngày kết thúc (YYYY-MM-DD, để trống = hôm nay)',
                controller: dateCtrl,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Lý do kết thúc hợp đồng',
                controller: reasonCtrl,
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          AppButton(
            label: 'Hủy',
            variant: AppButtonVariant.outlined,
            onPressed: () => Navigator.pop(ctx),
          ),
          AppButton(
            label: 'Xác nhận thanh lý',
            variant: AppButtonVariant.danger,
            onPressed: () async {
              final err = await context.read<AppDataRepository>().terminateContract(
                    item.id,
                    terminatedAt: dateCtrl.text.trim(),
                    reason: reasonCtrl.text.trim(),
                  );
              if (!ctx.mounted || !mounted) return;
              if (err != null) {
                showErrorToast(context, err);
                return;
              }
              Navigator.pop(ctx);
              showSuccessToast(context, 'Đã thanh lý hợp đồng ${item.code}');
            },
          ),
        ],
      ),
    );
  }

  /// Mở hộp thoại ngay; lịch sử được tải bên trong (đang tải / lỗi + Thử lại / 403 / rỗng / dữ liệu).
  void _openContractHistoryDialog(ContractItem item) {
    final repo = context.read<AppDataRepository>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Lịch sử hợp đồng: ${item.code}', style: AppTypography.sectionTitle),
        content: SizedBox(
          width: 520,
          child: HistoryLoader<ContractEventItem>(
            load: () => repo.fetchContractHistory(item.id),
            what: 'lịch sử hợp đồng',
            emptyText: 'Chưa có sự kiện nào.',
            builder: (_, events) => ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: events.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, idx) {
                          final e = events[idx];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(e.eventTypeDisplay, style: AppTypography.bodyBold),
                            subtitle: Text(
                              '${e.oldEndDate.isNotEmpty ? '${e.oldEndDate} → ' : ''}${e.newEndDate}${e.note.isNotEmpty ? ' · ${e.note}' : ''}',
                              style: AppTypography.caption,
                            ),
                            trailing: Text(
                              e.createdAt.length > 10 ? e.createdAt.substring(0, 10) : e.createdAt,
                              style: AppTypography.captionSm,
                            ),
                          );
                        },
                      ),
                    ),
          ),
        ),
        actions: [
          AppButton(
            label: 'Đóng',
            variant: AppButtonVariant.outlined,
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(ContractItem item) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Xóa hợp đồng thuê',
      message: 'Bạn có chắc chắn muốn xóa hợp đồng "${item.code}" của khách ${item.tenantName}?',
    );
    if (!confirmed || !mounted) return;
    final err = await context.read<AppDataRepository>().deleteContract(item.id);
    if (!mounted) return;
    if (err != null) {
      showErrorToast(context, err);
      return;
    }
    showSuccessToast(context, 'Đã xóa hợp đồng "${item.code}"');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppDataRepository>();
    final query = _searchCtrl.text.trim().toLowerCase();

    final filtered = repo.contracts.where((c) {
      final matchesStatus = _statusFilter == 'ALL' || c.status == _statusFilter;
      final matchesQuery = query.isEmpty ||
          c.code.toLowerCase().contains(query) ||
          c.tenantName.toLowerCase().contains(query) ||
          c.roomName.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList();

    // Sau khi xóa / lọc, số trang có thể giảm: không để trang hiện tại vượt quá trang cuối.
    final pageCount = filtered.isEmpty ? 1 : (filtered.length + _pageSize - 1) ~/ _pageSize;
    final page = _page.clamp(1, pageCount);
    final start = ((page - 1) * _pageSize).clamp(0, filtered.length);
    final end = (page * _pageSize).clamp(0, filtered.length);
    final paged = filtered.sublist(start, end);
    final hasFilter = query.isNotEmpty || _statusFilter != 'ALL';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Quản lý hợp đồng',
          subtitle: 'Quản lý thời hạn hợp đồng, tiền đặt cọc và gia hạn thuê phòng.',
          actions: [
            // Tạo / sửa / xóa / kích hoạt / gia hạn / chấm dứt hợp đồng đang tạm khóa ở backend.
            if (SprintFeatures.contractWrite)
              AppButton(
                label: '+ Tạo hợp đồng',
                onPressed: () => _openContractForm(),
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
                hintText: 'Tìm theo mã hợp đồng, người thuê, phòng...',
                onChanged: (_) => setState(() => _page = 1),
              ),
              AppSelect<String>(
                label: 'Trạng thái',
                value: _statusFilter,
                options: const [
                  AppSelectOption(value: 'ALL', label: 'Tất cả trạng thái'),
                  AppSelectOption(value: 'DRAFT', label: 'Bản nháp'),
                  AppSelectOption(value: 'ACTIVE', label: 'Đang hiệu lực'),
                  AppSelectOption(value: 'EXTENDED', label: 'Đã gia hạn'),
                  AppSelectOption(value: 'EXPIRING', label: 'Sắp hết hạn'),
                  AppSelectOption(value: 'EXPIRED', label: 'Đã hết hạn'),
                  AppSelectOption(value: 'TERMINATED', label: 'Đã thanh lý'),
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
          state: repo.sectionState(DataSection.contracts),
          isSyncing: repo.isSyncing,
          lastSyncError: repo.lastSyncError,
          hasData: repo.contracts.isNotEmpty,
          what: 'danh sách hợp đồng',
          keyPrefix: 'contract_list',
          onRetry: repo.syncWithBackend,
          empty: EmptyState(
            key: const Key('contract_list_empty'),
            icon: Icons.description_outlined,
            title: 'Chưa có hợp đồng nào',
            subtitle: 'Hệ thống chưa có hợp đồng thuê nào trong phạm vi quản lý của bạn.',
            actionLabel: SprintFeatures.contractWrite ? '+ Tạo hợp đồng' : null,
            onAction: SprintFeatures.contractWrite ? () => _openContractForm() : null,
          ),
          noMatch: filtered.isNotEmpty
              ? null
              : EmptyState(
                  key: const Key('contract_list_no_match'),
                  icon: Icons.search_off_rounded,
                  title: 'Không có hợp đồng nào phù hợp',
                  subtitle: 'Không có hợp đồng nào khớp với từ khóa hoặc bộ lọc hiện tại.',
                  actionLabel: hasFilter ? 'Đặt lại bộ lọc' : null,
                  onAction: hasFilter
                      ? () => setState(() {
                            _searchCtrl.clear();
                            _statusFilter = 'ALL';
                            _page = 1;
                          })
                      : null,
                ),
          builder: (_) => AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                AppTable<ContractItem>(
                  items: paged,
                  columns: [
                    AppTableColumn(
                      label: 'MÃ HỢP ĐỒNG',
                      width: 130,
                      cellBuilder: (c) => CodeBadge(c.code),
                    ),
                    AppTableColumn(
                      label: 'NGƯỜI THUÊ',
                      flex: 2,
                      cellBuilder: (c) => Text(c.tenantName, style: AppTypography.bodySemiBold),
                    ),
                    AppTableColumn(
                      label: 'PHÒNG',
                      flex: 2,
                      cellBuilder: (c) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(c.roomName, style: AppTypography.bodyMedium),
                          Text(
                            c.propertyName,
                            style: AppTypography.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AppTableColumn(
                      label: 'NGÀY BẮT ĐẦU',
                      width: 125,
                      cellBuilder: (c) => Text(c.startDate, style: AppTypography.body),
                    ),
                    AppTableColumn(
                      label: 'NGÀY KẾT THÚC',
                      width: 125,
                      cellBuilder: (c) => Text(c.endDate, style: AppTypography.body),
                    ),
                    AppTableColumn(
                      label: 'TIỀN ĐẶT CỌC',
                      width: 130,
                      cellBuilder: (c) => Text(
                        AppFormatters.currency(c.depositAmount),
                        style: AppTypography.bodySemiBold,
                      ),
                    ),
                    AppTableColumn(
                      label: 'TRẠNG THÁI',
                      width: 140,
                      cellBuilder: (c) => StatusBadge.fromContractStatus(c.status),
                    ),
                    AppTableColumn(
                      label: 'THAO TÁC',
                      // Khi khóa Sprint chỉ còn nút Lịch sử -> không giữ chỗ cho các nút ghi đang ẩn.
                      width: SprintFeatures.contractWrite ? 215 : 90,
                      alignment: Alignment.centerRight,
                      cellBuilder: (c) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (SprintFeatures.contractWrite && c.status == 'DRAFT')
                            IconButton(
                              tooltip: 'Kích hoạt hợp đồng',
                              icon: const Icon(
                                Icons.play_circle_outline_rounded,
                                size: 18,
                                color: AppColors.success,
                              ),
                              onPressed: () => _activateContract(c),
                            ),
                          if (SprintFeatures.contractWrite &&
                              (c.status == 'ACTIVE' ||
                                  c.status == 'EXTENDED' ||
                                  c.status == 'EXPIRING' ||
                                  c.status == 'EXPIRED')) ...[
                            IconButton(
                              tooltip: 'Gia hạn hợp đồng',
                              icon: const Icon(
                                Icons.event_repeat_rounded,
                                size: 18,
                                color: AppColors.secondary,
                              ),
                              onPressed: () => _openExtendDialog(c),
                            ),
                            IconButton(
                              tooltip: 'Thanh lý / Kết thúc',
                              icon: const Icon(
                                Icons.cancel_outlined,
                                size: 18,
                                color: AppColors.warningText,
                              ),
                              onPressed: () => _openTerminateDialog(c),
                            ),
                          ],
                          IconButton(
                            tooltip: 'Lịch sử hợp đồng',
                            icon: const Icon(
                              Icons.history_rounded,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () => _openContractHistoryDialog(c),
                          ),
                          if (SprintFeatures.contractWrite) ...[
                            IconButton(
                              tooltip: 'Chỉnh sửa',
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              onPressed: () => _openContractForm(c),
                            ),
                            IconButton(
                              tooltip: 'Xóa',
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: AppColors.error,
                              ),
                              onPressed: () => _confirmDelete(c),
                            ),
                          ],
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

