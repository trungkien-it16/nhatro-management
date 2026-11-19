/// Số liệu tổng hợp do API Gateway gộp từ các service: GET /api/dashboard/summary/
/// Trường nào null nghĩa là service sở hữu số liệu đó đang không phản hồi.
class DashboardSummary {
  final int? totalProperties;
  final int? totalRooms;
  final int? occupiedRooms;
  final int? availableRooms;
  final int? maintenanceRooms;
  final int? reservedRooms;
  final int? fullRooms;
  final double? estimatedMonthlyRevenue;
  final double? occupancyRatePercent;
  final int? openMaintenanceRequests;
  final int? totalTenants;
  final int? activeTenants;
  final int? activeContracts;
  final int? expiringSoonContracts;
  final int? unpaidInvoices;
  final int? overdueInvoices;
  final double? unpaidAmount;
  final bool complete;
  final List<String> failedSources;

  const DashboardSummary({
    this.totalProperties,
    this.totalRooms,
    this.occupiedRooms,
    this.availableRooms,
    this.maintenanceRooms,
    this.reservedRooms,
    this.fullRooms,
    this.estimatedMonthlyRevenue,
    this.occupancyRatePercent,
    this.openMaintenanceRequests,
    this.totalTenants,
    this.activeTenants,
    this.activeContracts,
    this.expiringSoonContracts,
    this.unpaidInvoices,
    this.overdueInvoices,
    this.unpaidAmount,
    this.complete = true,
    this.failedSources = const [],
  });

  static int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  static double? _double(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final errors = (json['errors'] as List?) ?? const [];
    return DashboardSummary(
      totalProperties: _int(json['total_properties']),
      totalRooms: _int(json['total_rooms']),
      occupiedRooms: _int(json['occupied_rooms']),
      availableRooms: _int(json['available_rooms']),
      maintenanceRooms: _int(json['maintenance_rooms']),
      reservedRooms: _int(json['reserved_rooms']),
      fullRooms: _int(json['full_rooms']),
      estimatedMonthlyRevenue: _double(json['estimated_monthly_revenue']),
      occupancyRatePercent: _double(json['occupancy_rate_percent']),
      openMaintenanceRequests: _int(json['open_maintenance_requests']),
      totalTenants: _int(json['total_tenants']),
      activeTenants: _int(json['active_tenants']),
      activeContracts: _int(json['active_contracts']),
      expiringSoonContracts: _int(json['expiring_soon_contracts']),
      unpaidInvoices: _int(json['unpaid_invoices']),
      overdueInvoices: _int(json['overdue_invoices']),
      unpaidAmount: _double(json['unpaid_amount']),
      complete: json['complete'] != false,
      failedSources: errors
          .whereType<Map>()
          .map((e) => '${e['service'] ?? e['source']}')
          .toList(),
    );
  }
}
