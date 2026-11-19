import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhatro_frontend/features/dashboard/widgets/soa_architecture_card.dart';
import 'package:nhatro_frontend/models/dashboard_summary_model.dart';
import 'package:nhatro_frontend/models/system_health_model.dart';

Map<String, dynamic> _healthJson() => {
      'gateway': {'status': 'UP', 'port': 8000},
      'overall_status': 'DEGRADED',
      'services': [
        {'key': 'identity', 'name': 'Identity Service', 'port': 8001, 'status': 'UP', 'database': {'status': 'UP'}},
        {'key': 'property', 'name': 'Property & Maintenance Service', 'port': 8002, 'status': 'UP'},
        {'key': 'tenant', 'name': 'Tenant Service', 'port': 8003, 'status': 'DOWN', 'error': 'refused'},
        {'key': 'contract', 'name': 'Contract Service', 'port': 8004, 'status': 'WEIRD'},
        {'key': 'billing', 'name': 'Billing & Notification Service', 'port': 8005, 'status': 'UP'},
      ],
    };

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  test('SystemHealth parse trạng thái thực tế từ Gateway', () {
    final h = SystemHealth.fromJson(_healthJson());
    expect(h.gatewayStatus, ServiceStatus.up);
    expect(h.service('tenant')!.status, ServiceStatus.down);
    expect(h.service('contract')!.status, ServiceStatus.unknown);
    expect(h.upCount, 3);
  });

  test('DashboardSummary giữ null khi service không phản hồi', () {
    final s = DashboardSummary.fromJson({
      'total_rooms': 7,
      'total_tenants': null,
      'unpaid_amount': '3729000',
      'complete': false,
      'errors': [
        {'source': 'tenant', 'service': 'Tenant Service'}
      ],
    });
    expect(s.totalRooms, 7);
    expect(s.totalTenants, isNull);
    expect(s.unpaidAmount, 3729000);
    expect(s.failedSources, ['Tenant Service']);
  });

  test('DashboardSummary đọc các trường mới của Property summary', () {
    final s = DashboardSummary.fromJson({'full_rooms': 2, 'estimated_monthly_revenue': '9800000'});
    expect(s.fullRooms, 2);
    expect(s.estimatedMonthlyRevenue, 9800000);
    expect(s.complete, isTrue);
  });

  testWidgets('SoaArchitectureCard tô màu theo trạng thái: UP xanh, DOWN đỏ, UNKNOWN xám', (tester) async {
    await tester.pumpWidget(_wrap(SoaArchitectureCard(health: SystemHealth.fromJson(_healthJson()), isLoading: false)));
    expect(find.text('API Gateway'), findsOneWidget);
    expect(find.text('Tenant Service'), findsOneWidget);
    expect(find.text('UP'), findsNWidgets(4)); // gateway + identity + property + billing
    expect(find.text('DOWN'), findsOneWidget);
    expect(find.text('UNKNOWN'), findsOneWidget);
    expect(SoaArchitectureCard.statusColor(ServiceStatus.up), const Color(0xFF16A34A));
    expect(SoaArchitectureCard.statusColor(ServiceStatus.down), const Color(0xFFDC2626));
  });

  testWidgets('Gateway không phản hồi -> Gateway DOWN, 5 service UNKNOWN', (tester) async {
    await tester.pumpWidget(_wrap(SoaArchitectureCard(
      health: SystemHealth.gatewayUnreachable('Không thể kết nối'),
      isLoading: false,
    )));
    expect(find.text('GATEWAY DOWN'), findsOneWidget);
    expect(find.text('UNKNOWN'), findsNWidgets(5));
  });

}
