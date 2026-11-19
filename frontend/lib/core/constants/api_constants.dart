/// Toàn bộ request của Frontend đi qua API Gateway (:8000).
/// Frontend KHÔNG biết địa chỉ nội bộ của 5 service (8001–8005).
///
/// Đổi địa chỉ Gateway khi build/chạy:
///   flutter run -d chrome --dart-define=API_GATEWAY_URL=http://192.168.1.10:8000
/// Android Emulator: --dart-define=API_GATEWAY_URL=http://10.0.2.2:8000
class ApiConstants {
  ApiConstants._();

  static const String gatewayUrl = String.fromEnvironment(
    'API_GATEWAY_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const String baseUrl = '$gatewayUrl/api';

  /// Nhãn địa chỉ Gateway để hiển thị (":8000" khi chạy local, "host[:port]" khi hosting) —
  /// lấy từ API_GATEWAY_URL, không hard-code cổng.
  static String get gatewayLabel {
    final uri = Uri.tryParse(gatewayUrl);
    if (uri == null || uri.host.isEmpty) return gatewayUrl;
    final port = uri.hasPort ? ':${uri.port}' : '';
    final isLocal = uri.host == '127.0.0.1' || uri.host == 'localhost' || uri.host == '10.0.2.2';
    return isLocal && port.isNotEmpty ? port : '${uri.host}$port';
  }

  // GATEWAY — endpoint do chính Gateway xử lý / tổng hợp
  static const String systemHealth = '$baseUrl/system/health/';
  static const String dashboardSummary = '$baseUrl/dashboard/summary/';
  /// Thông tin kết nối + endpoint thực tế của 1 service (Gateway đọc OpenAPI của service đó).
  static String serviceEndpoints(String key) => '$baseUrl/system/services/$key/endpoints/';

  // SERVICE 1 — IDENTITY (Gateway -> :8001)
  static const String login = '$baseUrl/auth/login/';
  static const String register = '$baseUrl/auth/register/';
  static const String refreshToken = '$baseUrl/auth/refresh/';
  static const String currentUser = '$baseUrl/auth/me/';
  static const String logout = '$baseUrl/auth/logout/';
  static const String changePassword = '$baseUrl/auth/change-password/';
  static const String testUsers = '$baseUrl/auth/test-users/';
  static const String users = '$baseUrl/users/';

  // SERVICE 2 — PROPERTY & MAINTENANCE (Gateway -> :8002)
  static const String properties = '$baseUrl/properties/';
  static const String rooms = '$baseUrl/rooms/';
  static const String maintenance = '$baseUrl/maintenance/';
  static const String maintenanceHistory = '$baseUrl/maintenance-history/';

  // SERVICE 3 — TENANT (Gateway -> :8003)
  static const String tenants = '$baseUrl/tenants/';

  // SERVICE 4 — CONTRACT (Gateway -> :8004)
  static const String contracts = '$baseUrl/contracts/';

  // SERVICE 5 — BILLING & NOTIFICATION (Gateway -> :8005)
  static const String invoices = '$baseUrl/billing/invoices/';
  static const String notifications = '$baseUrl/notifications/';
}
