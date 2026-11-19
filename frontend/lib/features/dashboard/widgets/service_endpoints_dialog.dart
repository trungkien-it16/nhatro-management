import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/state_views.dart';
import '../../../models/system_health_model.dart';
import 'soa_architecture_card.dart';

/// Hộp thoại "thông tin kết nối & API endpoint" của 1 service (mở từ thẻ Kiến trúc SOA).
///
/// Danh sách endpoint KHÔNG nhập tay: Gateway đọc OpenAPI `/api/schema/` do chính service sinh
/// từ URL routing thật -> backend thêm / đổi route thì danh sách tự cập nhật.
class ServiceEndpointsDialog extends StatefulWidget {
  final String serviceKey;
  final String name;
  final int port;

  /// Trạng thái do Gateway kiểm tra /health/ (thẻ Kiến trúc SOA).
  final ServiceStatus healthStatus;
  final Future<ServiceEndpointCatalog> Function(String key) load;

  const ServiceEndpointsDialog({
    super.key,
    required this.serviceKey,
    required this.name,
    required this.port,
    required this.healthStatus,
    required this.load,
  });

  static Future<void> show(
    BuildContext context, {
    required String serviceKey,
    required String name,
    required int port,
    required ServiceStatus healthStatus,
    required Future<ServiceEndpointCatalog> Function(String key) load,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ServiceEndpointsDialog(
        serviceKey: serviceKey,
        name: name,
        port: port,
        healthStatus: healthStatus,
        load: load,
      ),
    );
  }

  /// Tên nhóm theo prefix routing của Gateway (Billing & Notification dùng chung :8005).
  static const Map<String, String> groupTitles = {
    'auth': 'Xác thực',
    'users': 'Người dùng',
    'properties': 'Nhà trọ',
    'rooms': 'Phòng',
    'maintenance': 'Bảo trì',
    'maintenance-history': 'Lịch sử bảo trì',
    'tenants': 'Tenant',
    'contracts': 'Contract',
    'billing': 'Billing',
    'notifications': 'Notification',
    'health': 'Health check',
  };

  static Color methodColor(String method) {
    switch (method) {
      case 'GET':
        return const Color(0xFF2563EB);
      case 'POST':
        return const Color(0xFF16A34A);
      case 'PUT':
        return const Color(0xFFD97706);
      case 'PATCH':
        return const Color(0xFF7C3AED);
      case 'DELETE':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  State<ServiceEndpointsDialog> createState() => _ServiceEndpointsDialogState();
}

class _ServiceEndpointsDialogState extends State<ServiceEndpointsDialog> {
  late Future<ServiceEndpointCatalog> _future = _start();
  String? _copied;

  Future<ServiceEndpointCatalog> _start() {
    final f = widget.load(widget.serviceKey);
    f.ignore(); // lỗi được FutureBuilder hiển thị; tránh "unhandled" khi thử lại
    return f;
  }

  void _retry() {
    final next = _start();
    setState(() {
      _future = next;
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = text);
    showSuccessToast(context, 'Đã sao chép: $text');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      key: const Key('service_endpoints_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 900, maxHeight: size.height * 0.86),
        child: FutureBuilder<ServiceEndpointCatalog>(
          future: _future,
          builder: (context, snap) {
            final catalog = snap.connectionState == ConnectionState.done ? snap.data : null;
            final status = catalog?.status ?? widget.healthStatus;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, status),
                _connection(catalog),
                const Divider(height: 1),
                Flexible(child: _body(snap)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ServiceStatus status) {
    final color = SoaArchitectureCard.statusColor(status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.hub_rounded, size: 20, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
          ),
          Container(
            key: const Key('service_endpoints_status'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(
              SoaArchitectureCard.statusLabel(status),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
            ),
          ),
          IconButton(
            tooltip: 'Đóng',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _connection(ServiceEndpointCatalog? catalog) {
    final baseUrl = catalog?.baseUrl ?? '';
    const label = TextStyle(fontSize: 12, color: Color(0xFF64748B));
    const value = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Wrap(
        spacing: 24,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Base URL: ', style: label),
              SelectableText(baseUrl.isEmpty ? '—' : baseUrl,
                  key: const Key('service_endpoints_base_url'), style: value),
              if (baseUrl.isNotEmpty) _copyButton(baseUrl, 'Sao chép Base URL'),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Port: ', style: label),
              Text('${catalog?.port ?? widget.port}', key: const Key('service_endpoints_port'), style: value),
            ],
          ),
          if (catalog?.source != null)
            Text('Nguồn: OpenAPI ${catalog!.source}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  Widget _copyButton(String text, String tooltip) {
    final done = _copied == text;
    return IconButton(
      key: Key('copy_$text'),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      icon: Icon(done ? Icons.check_rounded : Icons.copy_rounded,
          color: done ? const Color(0xFF16A34A) : const Color(0xFF64748B)),
      onPressed: () => _copy(text),
    );
  }

  Widget _body(AsyncSnapshot<ServiceEndpointCatalog> snap) {
    if (snap.connectionState != ConnectionState.done) {
      return const Padding(
        key: Key('service_endpoints_loading'),
        padding: EdgeInsets.all(24),
        child: LoadingState(message: 'Đang đọc danh sách API từ service...'),
      );
    }
    if (snap.hasError) {
      return Padding(
        key: const Key('service_endpoints_error'),
        padding: const EdgeInsets.all(16),
        child: ErrorState(message: 'Không lấy được danh sách API: ${snap.error}', onRetry: _retry),
      );
    }
    final catalog = snap.data!;
    if (catalog.status != ServiceStatus.up) {
      return Padding(
        key: const Key('service_endpoints_down'),
        padding: const EdgeInsets.all(16),
        child: ErrorState(
          message: '${catalog.name} không hoạt động nên chưa đọc được danh sách API'
              '${catalog.error != null ? ': ${catalog.error}' : '.'}',
          onRetry: _retry,
        ),
      );
    }
    if (catalog.endpoints.isEmpty) {
      return const Padding(
        key: Key('service_endpoints_empty'),
        padding: EdgeInsets.all(24),
        child: Text('Service không công bố endpoint nào trong OpenAPI.'),
      );
    }

    final groups = <String, List<ServiceEndpoint>>{};
    for (final e in catalog.endpoints) {
      groups.putIfAbsent(e.group, () => []).add(e);
    }
    return ListView(
      key: const Key('service_endpoints_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        Text(
          '${catalog.endpoints.length} endpoint • {id} trong URL là tham số, thay bằng ID thật khi gọi.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        for (final entry in groups.entries) ...[
          const SizedBox(height: 14),
          Text(
            ServiceEndpointsDialog.groupTitles[entry.key] ?? entry.key,
            key: Key('service_endpoints_group_${entry.key}'),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 6),
          for (final e in entry.value) _row(e),
        ],
      ],
    );
  }

  Widget _row(ServiceEndpoint e) {
    final color = ServiceEndpointsDialog.methodColor(e.method);
    return Container(
      key: Key('endpoint_${e.method}_${e.path}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(e.method, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.path,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace', color: Color(0xFF0F172A))),
                if (e.description.isNotEmpty)
                  Text(e.description, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                SelectableText(e.fullUrl,
                    style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: Color(0xFF64748B))),
              ],
            ),
          ),
          _copyButton(e.fullUrl, 'Sao chép Full URL'),
        ],
      ),
    );
  }
}
