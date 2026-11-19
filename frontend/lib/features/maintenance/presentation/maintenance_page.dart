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

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final _searchCtrl = TextEditingController();
  String _priorityFilter = 'ALL';
  String _statusFilter = 'ALL';
  int _page = 1;
  static const int _pageSize = 6;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openMaintenanceForm([MaintenanceItem? existing]) {
    final repo = context.read<AppDataRepository>();
    final formKey = GlobalKey<FormState>();
    final codeCtrl = TextEditingController(
      text: existing?.code ?? 'BT-00${repo.maintenances.length + 1}',
    );
    final roomCtrl = TextEditingController(text: existing?.roomName ?? 'Phòng A101');
    final propCtrl = TextEditingController(
      text: existing?.propertyName ??
          (repo.properties.isNotEmpty ? repo.properties.first.name : ''),
    );
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final dateCtrl = TextEditingController(text: existing?.createdAt ?? '13/11/2026');
    final costCtrl = TextEditingController(
      text: '${existing?.estimatedCost.toInt() ?? 350000}',
    );
    String priority = existing?.priority ?? 'MEDIUM';
    String status = existing?.status ?? 'PENDING';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(
            existing == null ? 'Tạo yêu cầu bảo trì' : 'Cập nhật yêu cầu bảo trì',
            style: AppTypography.sectionTitle,
          ),
          content: SizedBox(
            width: 520,
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
                            label: 'Mã yêu cầu',
                            controller: codeCtrl,
                            requiredField: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Ngày tạo',
                            controller: dateCtrl,
                            requiredField: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Phòng',
                            controller: roomCtrl,
                            requiredField: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppTextField(
                            label: 'Chi phí dự kiến (VNĐ)',
                            controller: costCtrl,
                            isNumber: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: 'Nhà trọ',
                      controller: propCtrl,
                      requiredField: true,
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: 'Nội dung yêu cầu',
                      controller: titleCtrl,
                      hint: 'VD: Sửa điều hòa, thay bóng đèn...',
                      requiredField: true,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: AppSelect<String>(
                            label: 'Mức độ ưu tiên',
                            width: null,
                            value: priority,
                            options: const [
                              AppSelectOption(value: 'LOW', label: 'Thấp'),
                              AppSelectOption(value: 'MEDIUM', label: 'Trung bình'),
                              AppSelectOption(value: 'HIGH', label: 'Cao'),
                            ],
                            onChanged: (v) => setModalState(() => priority = v ?? 'MEDIUM'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppSelect<String>(
                            label: 'Trạng thái',
                            width: null,
                            value: status,
                            options: const [
                              AppSelectOption(value: 'PENDING', label: 'Chờ xử lý'),
                              AppSelectOption(value: 'IN_PROGRESS', label: 'Đang xử lý'),
                              AppSelectOption(value: 'COMPLETED', label: 'Hoàn thành'),
                              AppSelectOption(value: 'CANCELLED', label: 'Đã hủy'),
                            ],
                            onChanged: (v) => setModalState(() => status = v ?? 'PENDING'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: 'Mô tả chi tiết / Phương án xử lý',
                      controller: descCtrl,
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
              label: existing == null ? 'Tạo yêu cầu' : 'Lưu thay đổi',
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final cost = double.tryParse(costCtrl.text.trim()) ?? 0;

                if (existing == null) {
                  final err = await repo.addMaintenance(
                    MaintenanceItem(
                      id: DateTime.now().millisecondsSinceEpoch,
                      code: codeCtrl.text.trim(),
                      roomId: 0,
                      roomName: roomCtrl.text.trim(),
                      propertyName: propCtrl.text.trim(),
                      title: titleCtrl.text.trim(),
                      description: descCtrl.text.trim(),
                      createdAt: dateCtrl.text.trim(),
                      priority: priority,
                      status: status,
                      estimatedCost: cost,
                    ),
                  );
                  if (!ctx.mounted || !mounted) return;
                  if (err != null) {
                    showErrorToast(context, err);
                    return;
                  }
                  Navigator.pop(ctx);
                  showSuccessToast(context, 'Đã tạo yêu cầu bảo trì "${codeCtrl.text.trim()}"');
                } else {
                  final err = await repo.updateMaintenance(
                    existing.copyWith(
                      code: codeCtrl.text.trim(),
                      roomName: roomCtrl.text.trim(),
                      propertyName: propCtrl.text.trim(),
                      title: titleCtrl.text.trim(),
                      description: descCtrl.text.trim(),
                      createdAt: dateCtrl.text.trim(),
                      priority: priority,
                      status: status,
                      estimatedCost: cost,
                    ),
                  );
                  if (!ctx.mounted || !mounted) return;
                  if (err != null) {
                    showErrorToast(context, err);
                    return;
                  }
                  Navigator.pop(ctx);
                  showSuccessToast(context, 'Đã cập nhật yêu cầu "${codeCtrl.text.trim()}"');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startMaintenance(MaintenanceItem item) async {
    final err = await context
        .read<AppDataRepository>()
        .updateMaintenance(item.copyWith(status: 'IN_PROGRESS'));
    if (!mounted) return;
    if (err != null) {
      showErrorToast(context, err);
      return;
    }
    showSuccessToast(context, 'Đã chuyển yêu cầu ${item.code} sang Đang xử lý.');
  }

  void _openRecordCostDialog(MaintenanceItem item) {
    final formKey = GlobalKey<FormState>();
    final estCtrl = TextEditingController(text: '${item.estimatedCost.toInt()}');
    final actCtrl = TextEditingController(
      text: '${item.actualCost > 0 ? item.actualCost.toInt() : item.estimatedCost.toInt()}',
    );
    final infoCtrl = TextEditingController(text: item.repairInfo);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ghi nhận chi phí: ${item.code}', style: AppTypography.sectionTitle),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'Chi phí dự kiến (VNĐ)',
                        controller: estCtrl,
                        requiredField: true,
                        isNumber: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        label: 'Chi phí thực tế (VNĐ)',
                        controller: actCtrl,
                        requiredField: true,
                        isNumber: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Ghi chú sửa chữa / vật tư',
                  controller: infoCtrl,
                  maxLines: 2,
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
            label: 'Lưu chi phí',
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final err = await context.read<AppDataRepository>().recordMaintenanceCost(
                    item.id,
                    estimatedCost: double.tryParse(estCtrl.text.trim()) ?? 0,
                    actualCost: double.tryParse(actCtrl.text.trim()) ?? 0,
                    repairInfo: infoCtrl.text.trim(),
                  );
              if (!ctx.mounted || !mounted) return;
              if (err != null) {
                showErrorToast(context, err);
                return;
              }
              Navigator.pop(ctx);
              showSuccessToast(context, 'Đã ghi nhận chi phí cho ${item.code}.');
            },
          ),
        ],
      ),
    );
  }

  void _openCompleteDialog(MaintenanceItem item) {
    final formKey = GlobalKey<FormState>();
    final actCtrl = TextEditingController(
      text: '${item.actualCost > 0 ? item.actualCost.toInt() : item.estimatedCost.toInt()}',
    );
    final infoCtrl = TextEditingController(
      text: item.repairInfo.isNotEmpty
          ? item.repairInfo
          : 'Đã sửa chữa hoàn tất, thiết bị hoạt động ổn định.',
    );
    String roomStatus = 'AVAILABLE';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('Hoàn thành bảo trì: ${item.code}', style: AppTypography.sectionTitle),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Chi phí thực tế chốt (VNĐ)',
                          controller: actCtrl,
                          requiredField: true,
                          isNumber: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppSelect<String>(
                          label: 'Trạng thái phòng sau sửa',
                          width: null,
                          value: roomStatus,
                          options: const [
                            AppSelectOption(value: 'AVAILABLE', label: 'AVAILABLE — Phòng trống'),
                            AppSelectOption(value: 'OCCUPIED', label: 'OCCUPIED — Đang thuê'),
                          ],
                          onChanged: (v) => setModalState(() => roomStatus = v ?? 'AVAILABLE'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Nội dung nghiệm thu sửa chữa',
                    controller: infoCtrl,
                    requiredField: true,
                    maxLines: 2,
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
              label: 'Xác nhận hoàn thành',
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final err = await context.read<AppDataRepository>().completeMaintenance(
                      item.id,
                      actualCost: double.tryParse(actCtrl.text.trim()) ?? 0,
                      roomStatus: roomStatus,
                      repairInfo: infoCtrl.text.trim(),
                    );
                if (!ctx.mounted || !mounted) return;
                if (err != null) {
                  showErrorToast(context, err);
                  return;
                }
                Navigator.pop(ctx);
                showSuccessToast(context, 'Đã hoàn thành bảo trì ${item.code}.');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(MaintenanceItem item) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Xóa yêu cầu bảo trì',
      message: 'Bạn có chắc chắn muốn xóa yêu cầu "${item.code}" (${item.roomName})?',
    );
    if (!confirmed || !mounted) return;
    final err = await context.read<AppDataRepository>().deleteMaintenance(item.id);
    if (!mounted) return;
    if (err != null) {
      showErrorToast(context, err);
      return;
    }
    showSuccessToast(context, 'Đã xóa yêu cầu "${item.code}"');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppDataRepository>();
    final query = _searchCtrl.text.trim().toLowerCase();

    final filtered = repo.maintenances.where((m) {
      final matchesPriority = _priorityFilter == 'ALL' || m.priority == _priorityFilter;
      final matchesStatus = _statusFilter == 'ALL' || m.status == _statusFilter;
      final matchesQuery = query.isEmpty ||
          m.code.toLowerCase().contains(query) ||
          m.roomName.toLowerCase().contains(query) ||
          m.title.toLowerCase().contains(query);
      return matchesPriority && matchesStatus && matchesQuery;
    }).toList();

    final hasFilter = query.isNotEmpty || _priorityFilter != 'ALL' || _statusFilter != 'ALL';
    // Kẹp trang hiện tại khi lọc / xóa làm giảm số trang (tránh trang rỗng giả).
    final totalPages = filtered.isEmpty ? 1 : (filtered.length + _pageSize - 1) ~/ _pageSize;
    final page = _page.clamp(1, totalPages);
    final start = ((page - 1) * _pageSize).clamp(0, filtered.length);
    final end = (page * _pageSize).clamp(0, filtered.length);
    final paged = filtered.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Bảo trì & sửa chữa',
          subtitle: 'Tiếp nhận sự cố kỹ thuật, phân công sửa chữa và kiểm soát chi phí bảo trì phòng.',
          actions: [
            // Mọi API ghi của bảo trì đang tạm khóa ở backend (Sprint sau) -> ẩn nút, giữ source.
            if (SprintFeatures.maintenanceWrite)
              AppButton(
                label: '+ Tạo yêu cầu bảo trì',
                onPressed: () => _openMaintenanceForm(),
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
                hintText: 'Tìm theo mã yêu cầu, phòng, nội dung...',
                onChanged: (_) => setState(() => _page = 1),
              ),
              AppSelect<String>(
                label: 'Mức độ ưu tiên',
                width: 175,
                value: _priorityFilter,
                options: const [
                  AppSelectOption(value: 'ALL', label: 'Tất cả mức độ'),
                  AppSelectOption(value: 'HIGH', label: 'Cao'),
                  AppSelectOption(value: 'MEDIUM', label: 'Trung bình'),
                  AppSelectOption(value: 'LOW', label: 'Thấp'),
                ],
                onChanged: (v) => setState(() {
                  _priorityFilter = v ?? 'ALL';
                  _page = 1;
                }),
              ),
              AppSelect<String>(
                label: 'Trạng thái',
                width: 185,
                value: _statusFilter,
                options: const [
                  AppSelectOption(value: 'ALL', label: 'Tất cả trạng thái'),
                  AppSelectOption(value: 'PENDING', label: 'Chờ xử lý'),
                  AppSelectOption(value: 'IN_PROGRESS', label: 'Đang xử lý'),
                  AppSelectOption(value: 'COMPLETED', label: 'Hoàn thành'),
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
          state: repo.sectionState(DataSection.maintenance),
          isSyncing: repo.isSyncing,
          lastSyncError: repo.lastSyncError,
          hasData: repo.maintenances.isNotEmpty,
          what: 'danh sách yêu cầu bảo trì',
          keyPrefix: 'maintenance_list',
          onRetry: repo.syncWithBackend,
          empty: EmptyState(
            key: const Key('maintenance_list_empty'),
            icon: Icons.build_outlined,
            title: 'Chưa có yêu cầu bảo trì nào',
            subtitle: 'Các yêu cầu sửa chữa được tạo sẽ hiển thị tại đây.',
            actionLabel: SprintFeatures.maintenanceWrite ? '+ Tạo yêu cầu bảo trì' : null,
            onAction: SprintFeatures.maintenanceWrite ? () => _openMaintenanceForm() : null,
          ),
          noMatch: filtered.isNotEmpty
              ? null
              : EmptyState(
                  key: const Key('maintenance_list_no_match'),
                  icon: Icons.search_off_rounded,
                  title: 'Không có yêu cầu bảo trì nào phù hợp',
                  subtitle: 'Thử đổi từ khóa, mức độ ưu tiên hoặc trạng thái.',
                  actionLabel: hasFilter ? 'Đặt lại bộ lọc' : null,
                  onAction: hasFilter
                      ? () => setState(() {
                            _searchCtrl.clear();
                            _priorityFilter = 'ALL';
                            _statusFilter = 'ALL';
                            _page = 1;
                          })
                      : null,
                ),
          builder: (_) => AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                AppTable<MaintenanceItem>(
                  items: paged,
                  columns: [
                    AppTableColumn(
                      label: 'MÃ YÊU CẦU',
                      width: 120,
                      cellBuilder: (m) => CodeBadge(m.code),
                    ),
                    AppTableColumn(
                      label: 'PHÒNG',
                      width: 180,
                      cellBuilder: (m) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(m.roomName, style: AppTypography.bodySemiBold),
                          Text(
                            m.propertyName,
                            style: AppTypography.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AppTableColumn(
                      label: 'NỘI DUNG YÊU CẦU',
                      flex: 3,
                      cellBuilder: (m) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            m.title,
                            style: AppTypography.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Dự kiến: ${AppFormatters.currency(m.estimatedCost)} · Thực tế: ${AppFormatters.currency(m.actualCost)}',
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    AppTableColumn(
                      label: 'NGÀY TẠO',
                      width: 120,
                      cellBuilder: (m) => Text(m.createdAt, style: AppTypography.body),
                    ),
                    AppTableColumn(
                      label: 'MỨC ĐỘ ƯU TIÊN',
                      width: 140,
                      cellBuilder: (m) => StatusBadge.fromPriority(m.priority),
                    ),
                    AppTableColumn(
                      label: 'TRẠNG THÁI',
                      width: 145,
                      cellBuilder: (m) => StatusBadge.fromMaintenanceStatus(m.status),
                    ),
                    if (SprintFeatures.maintenanceWrite)
                    AppTableColumn(
                      label: 'THAO TÁC',
                      width: 205,
                      alignment: Alignment.centerRight,
                      cellBuilder: (m) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (m.status == 'PENDING')
                            IconButton(
                              tooltip: 'Bắt đầu xử lý',
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 19,
                                color: AppColors.secondary,
                              ),
                              onPressed: () => _startMaintenance(m),
                            ),
                          IconButton(
                            tooltip: 'Ghi nhận chi phí',
                            icon: const Icon(
                              Icons.payments_outlined,
                              size: 18,
                              color: AppColors.warningText,
                            ),
                            onPressed: () => _openRecordCostDialog(m),
                          ),
                          if (m.status != 'COMPLETED' && m.status != 'CANCELLED')
                            IconButton(
                              tooltip: 'Hoàn thành bảo trì',
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 19,
                                color: AppColors.success,
                              ),
                              onPressed: () => _openCompleteDialog(m),
                            ),
                          IconButton(
                            tooltip: 'Chỉnh sửa',
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () => _openMaintenanceForm(m),
                          ),
                          IconButton(
                            tooltip: 'Xóa',
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppColors.error,
                            ),
                            onPressed: () => _confirmDelete(m),
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

        const SizedBox(height: AppSpacing.xxl),

        // 7.8 Maintenance History Table
        AppSurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lịch sử bảo trì toàn hệ thống',
                      style: AppTypography.sectionTitle,
                    ),
                    SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Theo dõi các lần sửa chữa, chuyển trạng thái, chi phí và nội dung nghiệm thu',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SectionListGate(
                state: repo.sectionState(DataSection.maintenanceHistory),
                isSyncing: repo.isSyncing,
                lastSyncError: repo.lastSyncError,
                hasData: repo.maintenanceHistories.isNotEmpty,
                what: 'lịch sử bảo trì',
                keyPrefix: 'maintenance_history',
                onRetry: repo.syncWithBackend,
                empty: const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    'Chưa có lịch sử bảo trì nào.',
                    key: Key('maintenance_history_empty'),
                    style: AppTypography.caption,
                  ),
                ),
                noMatch: null,
                builder: (_) => AppTable<MaintenanceHistoryItem>(
                  items: repo.maintenanceHistories,
                  columns: [
                    AppTableColumn(
                      label: 'THỜI GIAN',
                      width: 155,
                      cellBuilder: (h) => Text(
                        h.repairDate.length > 16 ? h.repairDate.substring(0, 16) : h.repairDate,
                        style: AppTypography.caption,
                      ),
                    ),
                    AppTableColumn(
                      label: 'MÃ YC',
                      width: 115,
                      cellBuilder: (h) => CodeBadge(h.requestCode),
                    ),
                    AppTableColumn(
                      label: 'PHÒNG',
                      flex: 2,
                      cellBuilder: (h) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(h.roomNumber, style: AppTypography.bodyBold),
                          Text(h.propertyName, style: AppTypography.caption, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    AppTableColumn(
                      label: 'HÀNH ĐỘNG & TRẠNG THÁI',
                      flex: 2,
                      cellBuilder: (h) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(h.action, style: AppTypography.bodyMedium),
                          if (h.newStatus.isNotEmpty)
                            Text(
                              h.previousStatus.isNotEmpty
                                  ? '${h.previousStatus} → ${h.newStatus}'
                                  : h.newStatus,
                              style: AppTypography.caption,
                            ),
                        ],
                      ),
                    ),
                    AppTableColumn(
                      label: 'CHI PHÍ',
                      width: 130,
                      cellBuilder: (h) => Text(
                        AppFormatters.currency(h.cost),
                        style: AppTypography.bodyBold.copyWith(color: AppColors.secondary),
                      ),
                    ),
                    AppTableColumn(
                      label: 'NỘI DUNG SỬA CHỮA',
                      flex: 3,
                      cellBuilder: (h) => Text(
                        h.repairContent,
                        style: AppTypography.bodyMd,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

