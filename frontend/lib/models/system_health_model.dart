/// Trạng thái thực tế trả về từ API Gateway: GET /api/system/health/
enum ServiceStatus { up, down, unknown }

ServiceStatus parseServiceStatus(dynamic value) {
  switch ('$value'.toUpperCase()) {
    case 'UP':
      return ServiceStatus.up;
    case 'DOWN':
      return ServiceStatus.down;
    default:
      return ServiceStatus.unknown;
  }
}

class ServiceHealth {
  final String key;
  final String name;
  final int port;
  final ServiceStatus status;
  final String? databaseStatus;
  final double? responseTimeMs;
  final String? error;

  const ServiceHealth({
    required this.key,
    required this.name,
    required this.port,
    required this.status,
    this.databaseStatus,
    this.responseTimeMs,
    this.error,
  });

  factory ServiceHealth.fromJson(Map<String, dynamic> json) {
    final db = json['database'];
    return ServiceHealth(
      key: '${json['key'] ?? ''}',
      name: '${json['name'] ?? json['key'] ?? 'Service'}',
      port: (json['port'] as num?)?.toInt() ?? 0,
      status: parseServiceStatus(json['status']),
      databaseStatus: db is Map ? db['status']?.toString() : null,
      responseTimeMs: (json['response_time_ms'] as num?)?.toDouble(),
      error: json['error']?.toString(),
    );
  }
}

class SystemHealth {
  final ServiceStatus gatewayStatus;
  final int gatewayPort;
  final String overallStatus;
  final List<ServiceHealth> services;
  final DateTime? checkedAt;

  /// Lỗi khi không gọi được Gateway (khi đó trạng thái service là UNKNOWN).
  final String? error;

  const SystemHealth({
    required this.gatewayStatus,
    required this.gatewayPort,
    required this.overallStatus,
    required this.services,
    this.checkedAt,
    this.error,
  });

  factory SystemHealth.fromJson(Map<String, dynamic> json) {
    final gateway = (json['gateway'] as Map?) ?? const {};
    final list = (json['services'] as List?) ?? const [];
    return SystemHealth(
      gatewayStatus: parseServiceStatus(gateway['status']),
      gatewayPort: (gateway['port'] as num?)?.toInt() ?? 8000,
      overallStatus: '${json['overall_status'] ?? 'UNKNOWN'}',
      services: list
          .whereType<Map>()
          .map((e) => ServiceHealth.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      checkedAt: DateTime.tryParse('${json['checked_at'] ?? ''}'),
    );
  }

  /// Gateway không phản hồi: Gateway = DOWN, không biết trạng thái các service phía sau.
  factory SystemHealth.gatewayUnreachable(String error) => SystemHealth(
        gatewayStatus: ServiceStatus.down,
        gatewayPort: 8000,
        overallStatus: 'DOWN',
        services: const [],
        error: error,
      );

  ServiceHealth? service(String key) {
    for (final s in services) {
      if (s.key == key) return s;
    }
    return null;
  }

  int get upCount => services.where((s) => s.status == ServiceStatus.up).length;
}

/// 1 endpoint thực tế của service: `GET /api/system/services/<key>/endpoints/`
class ServiceEndpoint {
  final String group;
  final String method;
  final String path;
  final String fullUrl;
  final String description;

  const ServiceEndpoint({
    required this.group,
    required this.method,
    required this.path,
    required this.fullUrl,
    required this.description,
  });

  factory ServiceEndpoint.fromJson(Map<String, dynamic> json) => ServiceEndpoint(
        group: '${json['group'] ?? ''}',
        method: '${json['method'] ?? ''}'.toUpperCase(),
        path: '${json['path'] ?? ''}',
        fullUrl: '${json['full_url'] ?? ''}',
        description: '${json['description'] ?? ''}',
      );
}

/// Thông tin kết nối + danh sách endpoint của 1 service (Gateway đọc từ OpenAPI của service).
class ServiceEndpointCatalog {
  final String key;
  final String name;
  final int port;
  final String baseUrl;
  final ServiceStatus status;
  final String? source;
  final String? error;
  final List<ServiceEndpoint> endpoints;

  const ServiceEndpointCatalog({
    required this.key,
    required this.name,
    required this.port,
    required this.baseUrl,
    required this.status,
    required this.endpoints,
    this.source,
    this.error,
  });

  factory ServiceEndpointCatalog.fromJson(Map<String, dynamic> json) => ServiceEndpointCatalog(
        key: '${json['key'] ?? ''}',
        name: '${json['name'] ?? json['key'] ?? 'Service'}',
        port: (json['port'] as num?)?.toInt() ?? 0,
        baseUrl: '${json['base_url'] ?? ''}',
        status: parseServiceStatus(json['status']),
        source: json['source']?.toString(),
        error: json['error']?.toString(),
        endpoints: ((json['endpoints'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ServiceEndpoint.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
