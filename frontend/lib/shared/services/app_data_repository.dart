import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';
import '../../models/dashboard_summary_model.dart';
import '../../models/system_health_model.dart';
import '../models/app_models.dart';
import 'api_client.dart';

/// Nhóm dữ liệu được đồng bộ độc lập; mỗi nhóm ứng với một endpoint qua API Gateway.
enum DataSection {
  properties,
  rooms,
  maintenance,
  maintenanceHistory,
  tenants,
  contracts,
  invoices,
  notifications,
  dashboard,
}

/// Trạng thái tải của một nhóm dữ liệu.
enum LoadStatus {
  /// Chưa tải lần nào trong phiên hiện tại.
  notLoaded,

  /// Đang tải (dữ liệu cũ của phiên, nếu có, vẫn được giữ).
  loading,

  /// Đã tải thành công: danh sách là dữ liệu thật (rỗng nghĩa là thật sự chưa có dữ liệu).
  loaded,

  /// Tải thất bại (mất kết nối, HTTP 5xx, phản hồi không hợp lệ...). Dữ liệu cũ được giữ.
  error,

  /// HTTP 403: vai trò hiện tại không có quyền xem nhóm dữ liệu này (không phải lỗi kết nối).
  forbidden,
}

/// Trạng thái hiện tại của một [DataSection].
class SectionState {
  final LoadStatus status;
  final String? message;
  final int? httpStatus;

  /// true nếu nhóm này đã tải thành công ít nhất một lần trong phiên: dữ liệu đang hiển thị là
  /// dữ liệu thật (có thể đã cũ khi [status] là error/loading).
  final bool hasData;

  const SectionState(this.status, {this.message, this.httpStatus, this.hasData = false});

  static const notLoaded = SectionState(LoadStatus.notLoaded);

  bool get isLoading => status == LoadStatus.loading;
  bool get isLoaded => status == LoadStatus.loaded;
  bool get isError => status == LoadStatus.error;
  bool get isForbidden => status == LoadStatus.forbidden;

  @override
  String toString() => 'SectionState(${status.name}${message == null ? '' : ', $message'})';
}

/// Kết quả gọi một endpoint trong lượt đồng bộ (không ném lỗi ra ngoài).
class _Fetched {
  final dynamic data;
  final Object? error;

  const _Fetched(this.data) : error = null;
  const _Fetched.failed(Object this.error) : data = null;

  /// Gateway có trả về HTTP response (kể cả 4xx/5xx) hay không.
  bool get gatewayResponded {
    final e = error;
    return e == null || (e is ApiException && e.statusCode != null);
  }
}

/// Repository dữ liệu của ứng dụng (Clean Architecture).
///
/// - MỌI request đi qua API Gateway (:8000). Flutter không gọi trực tiếp 5 service (8001–8005);
///   việc định tuyến, kiểm tra health và tổng hợp số liệu Dashboard do Gateway đảm nhiệm.
/// - Khi đã đăng nhập và Gateway phản hồi: Nhà trọ / Phòng / Bảo trì là dữ liệu THẬT
///   (kể cả khi danh sách rỗng), Dashboard lấy từ /api/dashboard/summary/,
///   trạng thái SOA lấy từ /api/system/health/.
/// - KHÔNG có dữ liệu mẫu: trước lần đồng bộ thành công đầu tiên mọi danh sách rỗng.
///   Khi Gateway lỗi: [isBackendConnected] = false, [lastSyncError] mô tả lỗi để UI hiện
///   trạng thái lỗi + nút "Thử lại"; danh sách giữ dữ liệu THẬT của lần đồng bộ gần nhất (nếu có).
/// - Mọi thao tác ghi chỉ thành công khi backend xác nhận; chưa kết nối -> trả [offlineWriteError].
class AppDataRepository extends ChangeNotifier {
  /// Thông báo trả về cho thao tác ghi khi chưa kết nối được API Gateway.
  static const String offlineWriteError =
      'Chưa kết nối được API Gateway nên thay đổi chưa được lưu. Hãy kiểm tra kết nối rồi bấm "Thử lại".';

  /// Thông báo cho thao tác đọc phụ (lịch sử, kiểm tra phòng) khi chưa kết nối.
  static const String offlineReadError = 'Chưa kết nối được API Gateway nên chưa tải được dữ liệu này.';

  bool isBackendConnected = false;
  bool isSyncing = false;
  String? lastSyncError;

  /// true sau lần đồng bộ đầu tiên của phiên mà Gateway có phản hồi. Trạng thái chi tiết của
  /// từng nhóm dữ liệu xem ở [sectionState] (phân biệt chưa tải / rỗng thật / lỗi / không có quyền).
  bool hasSyncedOnce = false;

  /// Kết quả thao tác hoặc lượt đọc thuộc phiên đăng nhập trước khi người dùng đã đăng xuất / đổi tài khoản.
  static const String sessionChangedError =
      'Phiên đăng nhập đã thay đổi nên kết quả thao tác của phiên trước không được áp dụng.';

  final Map<DataSection, SectionState> _sections = {
    for (final s in DataSection.values) s: SectionState.notLoaded,
  };

  /// Trạng thái tải của một nhóm dữ liệu.
  SectionState sectionState(DataSection section) => _sections[section]!;

  /// Các nhóm đang lỗi (không gồm forbidden).
  List<DataSection> get failedSections => [
        for (final e in _sections.entries)
          if (e.value.isError) e.key,
      ];

  /// Thế hệ phiên đăng nhập: tăng mỗi lần [resetAfterLogout]. Mọi kết quả trả về sau khi
  /// thế hệ đã đổi đều bị bỏ qua, nên dữ liệu của tài khoản cũ không lọt sang tài khoản mới.
  int _sessionGeneration = 0;

  @visibleForTesting
  int get sessionGeneration => _sessionGeneration;

  /// Lượt đồng bộ đang chạy của phiên hiện tại (gộp các yêu cầu đồng bộ liên tiếp).
  Future<void>? _activeSync;
  int _activeSyncGeneration = -1;
  bool _resyncRequested = false;

  /// Số lượt đồng bộ đã thực sự chạy (phục vụ kiểm thử).
  @visibleForTesting
  int syncRunCount = 0;

  /// Trạng thái thực tế Gateway + 5 service (null = chưa kiểm tra).
  SystemHealth? systemHealth;

  /// Số liệu Dashboard do Gateway tổng hợp (null = chưa có / Gateway lỗi).
  DashboardSummary? dashboardSummary;
  String? dashboardError;

  late List<PropertyItem> _properties;
  late List<RoomItem> _rooms;
  late List<TenantItem> _tenants;
  late List<ContractItem> _contracts;
  late List<InvoiceItem> _invoices;
  late List<MaintenanceItem> _maintenances;
  late List<MaintenanceHistoryItem> _maintenanceHistories;
  late List<NotificationItem> _notifications;
  late List<MonthlyRevenuePoint> _revenuePoints;

  AppDataRepository() {
    _clearData();
  }

  List<PropertyItem> get properties => List.unmodifiable(_properties);
  List<RoomItem> get rooms => List.unmodifiable(_rooms);
  List<TenantItem> get tenants => List.unmodifiable(_tenants);
  List<ContractItem> get contracts => List.unmodifiable(_contracts);
  List<InvoiceItem> get invoices => List.unmodifiable(_invoices);
  List<MaintenanceItem> get maintenances => List.unmodifiable(_maintenances);
  List<MaintenanceHistoryItem> get maintenanceHistories =>
      List.unmodifiable(_maintenanceHistories);
  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  List<MonthlyRevenuePoint> get revenuePoints => List.unmodifiable(_revenuePoints);

  /// Trạng thái từng service theo port (dùng cho trang Cài đặt). Không có dữ liệu -> false.
  Map<int, bool> get portStatus => {
        for (final s in systemHealth?.services ?? const <ServiceHealth>[]) s.port: s.status == ServiceStatus.up,
      };

  // Dashboard computed statistics (dữ liệu cục bộ; Dashboard ưu tiên [dashboardSummary])
  int get totalPropertiesCount => _properties.length;
  int get totalRoomsCount => _rooms.length;
  int get occupiedRoomsCount => _rooms
      .where((r) =>
          r.status == 'OCCUPIED' ||
          r.status == 'FULL' ||
          r.status == 'RESERVED')
      .length;
  int get availableRoomsCount =>
      _rooms.where((r) => r.status == 'AVAILABLE').length;
  int get maintenanceRoomsCount =>
      _rooms.where((r) => r.status == 'MAINTENANCE').length;
  int get activeContractsCount =>
      _contracts.where((c) => c.status == 'ACTIVE' || c.status == 'EXPIRING').length;
  int get unpaidInvoicesCount =>
      _invoices.where((i) => i.status == 'UNPAID' || i.status == 'OVERDUE').length;
  int get unreadNotificationCount =>
      _notifications.where((n) => !n.isRead).length;

  /// Trạng thái rỗng: chưa có dữ liệu nào cho tới khi Gateway trả về dữ liệu thật.
  void _clearData() {
    _properties = <PropertyItem>[];
    _rooms = <RoomItem>[];
    _tenants = <TenantItem>[];
    _contracts = <ContractItem>[];
    _invoices = <InvoiceItem>[];
    _maintenances = <MaintenanceItem>[];
    _maintenanceHistories = <MaintenanceHistoryItem>[];
    _notifications = <NotificationItem>[];
    _revenuePoints = <MonthlyRevenuePoint>[];
  }

  /// Dùng cho thao tác đọc phụ (lịch sử, kiểm tra phòng): báo lỗi thay vì tự suy đoán dữ liệu.
  void _ensureConnected() {
    if (!isBackendConnected) throw ApiException(offlineReadError);
  }

  /// Kết quả đọc thuộc phiên đăng nhập trước -> không trả cho phiên hiện tại.
  void _ensureSameSession(int gen) {
    if (gen != _sessionGeneration) throw ApiException(sessionChangedError);
  }

  // =====================================================================
  // GATEWAY: HEALTH & DASHBOARD (từ nhánh origin/baodev)
  // =====================================================================

  /// Trạng thái thực tế của Gateway + 5 service.
  /// Không ném lỗi: nếu Gateway không phản hồi thì Gateway = DOWN, các service = UNKNOWN.
  Future<SystemHealth> fetchSystemHealth() async {
    try {
      final res = await ApiClient.get(ApiConstants.systemHealth, requireAuth: false);
      if (res is Map<String, dynamic>) {
        return SystemHealth.fromJson(res);
      }
      return SystemHealth.gatewayUnreachable('Phản hồi không hợp lệ từ API Gateway.');
    } catch (e) {
      return SystemHealth.gatewayUnreachable(e.toString());
    }
  }

  /// Thông tin kết nối + endpoint thực tế của 1 service (Gateway đọc OpenAPI `/api/schema/`
  /// của chính service đó). Chỉ ADMIN: gửi kèm JWT, Gateway trả 401 (chưa đăng nhập) / 403 (không phải ADMIN).
  /// Ném [ApiException] khi Gateway lỗi hoặc không có quyền.
  Future<ServiceEndpointCatalog> fetchServiceEndpoints(String key) async {
    final res = await ApiClient.get(ApiConstants.serviceEndpoints(key));
    if (res is Map<String, dynamic>) return ServiceEndpointCatalog.fromJson(res);
    throw ApiException('Phản hồi không hợp lệ từ API Gateway.');
  }

  /// Số liệu Dashboard tổng hợp (theo phạm vi quyền của user đang đăng nhập).
  /// Ném [ApiException] khi Gateway lỗi hoặc token hết hạn.
  Future<DashboardSummary> fetchDashboardSummary() async {
    final res = await ApiClient.get(ApiConstants.dashboardSummary);
    if (res is Map<String, dynamic>) {
      return DashboardSummary.fromJson(res);
    }
    throw ApiException('Phản hồi không hợp lệ từ API Gateway.');
  }

  /// Chỉ kiểm tra trạng thái hệ thống (không cần đăng nhập).
  Future<void> refreshSystemHealth() async {
    final gen = _sessionGeneration;
    final health = await fetchSystemHealth();
    if (gen != _sessionGeneration) return;
    systemHealth = health;
    notifyListeners();
  }

  /// Đồng bộ dữ liệu thật qua API Gateway (cần đã đăng nhập).
  ///
  /// - Mỗi nhóm dữ liệu tải độc lập (song song); lỗi của nhóm này không chặn nhóm khác.
  /// - Lỗi: giữ dữ liệu thật đã tải trước đó trong phiên, nhóm chuyển [LoadStatus.error].
  ///   HTTP 403: [LoadStatus.forbidden] (vd. TENANT với Contract/Billing), không phải lỗi kết nối.
  /// - [isBackendConnected] chỉ phản ánh Gateway có phản hồi hay không.
  /// - Gọi khi đang có lượt đồng bộ của CÙNG phiên: không bỏ qua mà gộp thành đúng một lượt
  ///   chạy tiếp sau lượt hiện tại; Future trả về chỉ hoàn tất sau lượt đó.
  /// - Lượt đồng bộ của phiên cũ (đã đăng xuất) không được ghi vào state của phiên mới.
  Future<void> syncWithBackend() {
    final gen = _sessionGeneration;
    final active = _activeSync;
    if (active != null && _activeSyncGeneration == gen) {
      _resyncRequested = true;
      return active;
    }
    _resyncRequested = false;
    _activeSyncGeneration = gen;
    final run = _syncLoop(gen);
    _activeSync = run;
    return run;
  }

  Future<void> _syncLoop(int gen) async {
    isSyncing = true;
    notifyListeners();
    try {
      do {
        _resyncRequested = false;
        await _syncOnce(gen);
        // Chỉ chạy lại khi có yêu cầu mới trong lúc chạy -> không lặp vô hạn.
      } while (_resyncRequested && gen == _sessionGeneration);
    } finally {
      if (gen == _sessionGeneration) {
        _activeSync = null;
        _activeSyncGeneration = -1;
        isSyncing = false;
        notifyListeners();
      }
    }
  }

  static String _endpointOf(DataSection s) => switch (s) {
        DataSection.properties => ApiConstants.properties,
        DataSection.rooms => ApiConstants.rooms,
        DataSection.maintenance => ApiConstants.maintenance,
        DataSection.maintenanceHistory => ApiConstants.maintenanceHistory,
        DataSection.tenants => ApiConstants.tenants,
        DataSection.contracts => ApiConstants.contracts,
        DataSection.invoices => ApiConstants.invoices,
        DataSection.notifications => ApiConstants.notifications,
        DataSection.dashboard => ApiConstants.dashboardSummary,
      };

  static Future<_Fetched> _fetch(String url) async {
    try {
      return _Fetched(await ApiClient.get(url));
    } catch (e) {
      return _Fetched.failed(e);
    }
  }

  static String _messageOf(Object error) => error is ApiException ? error.message : '$error';

  Future<void> _syncOnce(int gen) async {
    bool stale() => gen != _sessionGeneration;
    syncRunCount++;
    lastSyncError = null;
    for (final s in DataSection.values) {
      _sections[s] = SectionState(LoadStatus.loading, hasData: _sections[s]!.hasData);
    }
    notifyListeners();

    final health = await fetchSystemHealth();
    if (stale()) return;
    systemHealth = health;
    if (health.gatewayStatus != ServiceStatus.up) {
      _markGatewayUnreachable(health.error ?? 'API Gateway không phản hồi.');
      return;
    }

    final fetched = await Future.wait([
      for (final s in DataSection.values) _fetch(_endpointOf(s)),
    ]);
    // Đã đăng xuất / đổi tài khoản trong lúc chờ: bỏ toàn bộ kết quả của phiên cũ.
    if (stale()) return;
    final r = {
      for (var i = 0; i < DataSection.values.length; i++) DataSection.values[i]: fetched[i],
    };

    if (!r.values.any((f) => f.gatewayResponded)) {
      // Không request nào nhận được HTTP response: Gateway không còn phản hồi.
      _markGatewayUnreachable(_messageOf(r.values.first.error!));
      return;
    }
    isBackendConnected = true;

    // Thứ tự áp dụng theo phụ thuộc ánh xạ: phòng -> người thuê -> hợp đồng / hóa đơn.
    _applyList(DataSection.properties, r[DataSection.properties]!,
        (rows) => _properties = rows.map(_propertyFromJson).toList());
    _applyList(DataSection.rooms, r[DataSection.rooms]!,
        (rows) => _rooms = rows.map(_roomFromJson).toList());
    _applyList(DataSection.maintenance, r[DataSection.maintenance]!,
        (rows) => _maintenances = rows.map(_maintenanceFromJson).toList());
    _applyList(DataSection.maintenanceHistory, r[DataSection.maintenanceHistory]!,
        (rows) => _maintenanceHistories = rows.map(_maintenanceHistoryFromJson).toList());
    _applyList(DataSection.tenants, r[DataSection.tenants]!,
        (rows) => _tenants = rows.map((t) => _tenantFromJson(t, _rooms)).toList());
    _applyList(DataSection.contracts, r[DataSection.contracts]!,
        (rows) => _contracts = rows.map((c) => _contractFromJson(c, _rooms, _tenants)).toList());
    _applyList(DataSection.invoices, r[DataSection.invoices]!,
        (rows) => _invoices = rows.map((i) => _invoiceFromJson(i, _rooms, _tenants)).toList());
    _applyList(DataSection.notifications, r[DataSection.notifications]!,
        (rows) => _notifications = rows.map(_notificationFromJson).toList());
    _applyDashboard(r[DataSection.dashboard]!);

    hasSyncedOnce = true;
    notifyListeners();
  }

  /// Gateway không phản hồi: mọi nhóm chuyển lỗi nhưng GIỮ dữ liệu thật đã tải trong phiên.
  void _markGatewayUnreachable(String message) {
    isBackendConnected = false;
    lastSyncError = message;
    for (final s in DataSection.values) {
      _sections[s] = SectionState(LoadStatus.error, message: message, hasData: _sections[s]!.hasData);
    }
  }

  /// Áp dụng kết quả một nhóm danh sách. Không bao giờ coi lỗi là danh sách rỗng hợp lệ.
  void _applyList(
    DataSection section,
    _Fetched f,
    void Function(List<Map<String, dynamic>> rows) assign,
  ) {
    final prev = _sections[section]!;
    final error = f.error;
    if (error == null) {
      if (f.data is List) {
        assign((f.data as List).whereType<Map<String, dynamic>>().toList());
        _sections[section] = const SectionState(LoadStatus.loaded, hasData: true);
      } else {
        _sections[section] = SectionState(
          LoadStatus.error,
          message: 'Phản hồi không hợp lệ từ API Gateway.',
          hasData: prev.hasData,
        );
      }
      return;
    }
    if (error is ApiException && error.statusCode == 403) {
      // Không có quyền: không giữ / hiển thị dữ liệu của nhóm này.
      assign(const []);
      _sections[section] = SectionState(LoadStatus.forbidden, message: error.message, httpStatus: 403);
      return;
    }
    _sections[section] = SectionState(
      LoadStatus.error,
      message: _messageOf(error),
      httpStatus: error is ApiException ? error.statusCode : null,
      hasData: prev.hasData,
    );
  }

  void _applyDashboard(_Fetched f) {
    const section = DataSection.dashboard;
    final prev = _sections[section]!;
    final error = f.error;
    if (error == null && f.data is Map<String, dynamic>) {
      dashboardSummary = DashboardSummary.fromJson(f.data as Map<String, dynamic>);
      dashboardError = null;
      _sections[section] = const SectionState(LoadStatus.loaded, hasData: true);
      return;
    }
    if (error is ApiException && error.statusCode == 403) {
      dashboardSummary = null;
      dashboardError = error.message;
      _sections[section] = SectionState(LoadStatus.forbidden, message: error.message, httpStatus: 403);
      return;
    }
    // Lỗi: giữ số liệu thật lần trước (nếu có) và báo lỗi.
    final message = error == null ? 'Phản hồi không hợp lệ từ API Gateway.' : _messageOf(error);
    dashboardError = message;
    _sections[section] = SectionState(
      LoadStatus.error,
      message: message,
      httpStatus: error is ApiException ? error.statusCode : null,
      hasData: prev.hasData,
    );
  }

  /// Gọi khi đăng xuất / phiên hết hạn / trước khi đăng nhập tài khoản khác: vô hiệu hóa mọi
  /// request đang chờ của phiên cũ và xóa toàn bộ dữ liệu của phiên đó (không nạp dữ liệu mẫu).
  void resetAfterLogout() {
    _sessionGeneration++;
    _activeSync = null;
    _activeSyncGeneration = -1;
    _resyncRequested = false;
    isSyncing = false;
    isBackendConnected = false;
    hasSyncedOnce = false;
    dashboardSummary = null;
    dashboardError = null;
    lastSyncError = null;
    _clearData();
    for (final s in DataSection.values) {
      _sections[s] = SectionState.notLoaded;
    }
    notifyListeners();
  }

  // ---------------- JSON MAPPING ----------------
  static int _int(dynamic v, [int fallback = 0]) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fallback;
  static int? _intOrNull(dynamic v) =>
      v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
  static double _double(dynamic v, [double fallback = 0]) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? fallback;

  static String _toIsoDate(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return trimmed;
    final parts = trimmed.split('/');
    if (parts.length == 3) {
      final d = parts[0].padLeft(2, '0');
      final m = parts[1].padLeft(2, '0');
      final y = parts[2];
      if (y.length == 4) return '$y-$m-$d';
    }
    return trimmed;
  }

  static PropertyItem _propertyFromJson(Map<String, dynamic> p) => PropertyItem(
        id: _int(p['id']),
        code: '${p['code'] ?? 'NT-${p['id']}'}',
        name: '${p['name'] ?? ''}',
        // `address` là địa chỉ chi tiết (trường ghi được); `full_address` là chuỗi ghép chỉ để hiển thị.
        // Trước đây `address` lấy từ `full_address` nên mỗi lần sửa lại ghép thêm phường/quận/thành phố.
        address: '${p['address'] ?? ''}',
        district: '${p['district'] ?? ''}',
        ward: '${p['ward'] ?? ''}',
        city: '${p['city'] ?? ''}',
        fullAddress: '${p['full_address'] ?? ''}',
        totalRooms: _int(p['total_rooms_count']),
        occupiedRooms: _int(p['occupied_rooms_count']),
        availableRooms: _int(p['available_rooms_count']),
        maintenanceRooms: _int(p['maintenance_rooms_count']),
        status: '${p['status'] ?? 'ACTIVE'}',
        description: '${p['description'] ?? ''}',
      );

  static RoomItem _roomFromJson(Map<String, dynamic> r) {
    final st = '${r['status'] ?? 'AVAILABLE'}';
    return RoomItem(
      id: _int(r['id']),
      code: '${r['code'] ?? ''}',
      name: '${r['room_number'] ?? ''}',
      propertyId: _int(r['property']),
      propertyName: '${r['property_name'] ?? ''}',
      floor: _int(r['floor'], 1),
      rentPrice: _double(r['rent_price']),
      area: _double(r['area'], 20),
      currentOccupants: _int(r['current_occupants']),
      maxOccupants: _int(r['max_occupants'], 2),
      status: st,
      description: '${r['description'] ?? ''}',
      isRentable: r['is_rentable'] != false,
      rentabilityReason: '${r['rentability_reason'] ?? ''}',
    );
  }

  static MaintenanceItem _maintenanceFromJson(Map<String, dynamic> m) => MaintenanceItem(
        id: _int(m['id']),
        code: '${m['code'] ?? ''}',
        roomId: _int(m['room']),
        roomName: '${m['room_number'] ?? ''}',
        propertyName: '${m['property_name'] ?? ''}',
        title: '${m['title'] ?? ''}',
        description: '${m['description'] ?? ''}',
        repairInfo: '${m['repair_info'] ?? ''}',
        technicianName: '${m['technician_name'] ?? ''}',
        createdAt: '${m['requested_date'] ?? ''}',
        priority: '${m['priority'] ?? 'MEDIUM'}',
        status: '${m['status'] ?? 'PENDING'}',
        estimatedCost: _double(m['estimated_cost']),
        actualCost: _double(m['actual_cost']),
      );

  static MaintenanceHistoryItem _maintenanceHistoryFromJson(Map<String, dynamic> h) =>
      MaintenanceHistoryItem(
        id: _int(h['id']),
        requestCode: '${h['request_code'] ?? ''}',
        roomNumber: '${h['room_number'] ?? ''}',
        propertyName: '${h['property_name'] ?? ''}',
        action: '${h['action'] ?? ''}',
        previousStatus: '${h['previous_status'] ?? ''}',
        newStatus: '${h['new_status'] ?? ''}',
        cost: _double(h['cost']),
        repairContent: '${h['repair_content'] ?? ''}',
        performedBy: '${h['performed_by'] ?? ''}',
        repairDate: '${h['repair_date'] ?? ''}',
      );

  static TenantItem _tenantFromJson(Map<String, dynamic> t, List<RoomItem> rooms) {
    final rid = _intOrNull(t['room_id']);
    final room = rid != null ? rooms.where((r) => r.id == rid).firstOrNull : null;
    final createdRaw = '${t['created_at'] ?? ''}';
    final dateShort = createdRaw.length >= 10 ? createdRaw.substring(0, 10) : createdRaw;
    return TenantItem(
      id: _int(t['id']),
      roomId: rid,
      userId: _intOrNull(t['user_id']),
      landlordId: _intOrNull(t['landlord_id']),
      fullName: '${t['full_name'] ?? ''}',
      phone: '${t['phone_number'] ?? ''}',
      email: '${t['email'] ?? ''}',
      idCard: '${t['identity_card'] ?? ''}',
      currentRoom: room?.name ?? (rid != null ? 'Phòng #$rid' : 'Chưa gán phòng'),
      propertyName: room?.propertyName ?? '',
      startDate: dateShort,
      status: '${t['status'] ?? 'ACTIVE'}',
      permanentAddress: '${t['permanent_address'] ?? ''}',
      birthDate: '${t['birth_date'] ?? ''}',
      gender: '${t['gender'] ?? ''}',
      occupation: '${t['occupation'] ?? ''}',
      emergencyContactName: '${t['emergency_contact_name'] ?? ''}',
      emergencyContactPhone: '${t['emergency_contact_phone'] ?? ''}',
      temporaryResidenceRegistered: t['temporary_residence_registered'] == true,
      notes: '${t['notes'] ?? ''}',
    );
  }

  static ContractItem _contractFromJson(
    Map<String, dynamic> c,
    List<RoomItem> rooms,
    List<TenantItem> tenants,
  ) {
    final rid = _intOrNull(c['room_id']);
    final tid = _intOrNull(c['tenant_id']);
    final room = rid != null ? rooms.where((r) => r.id == rid).firstOrNull : null;
    final tenant = tid != null ? tenants.where((t) => t.id == tid).firstOrNull : null;
    return ContractItem(
      id: _int(c['id']),
      roomId: rid,
      tenantId: tid,
      code: '${c['contract_number'] ?? 'HD-${c['id']}'}',
      tenantName: tenant?.fullName ?? (tid != null ? 'Khách #$tid' : '—'),
      roomName: room?.name ?? (rid != null ? 'Phòng #$rid' : '—'),
      propertyName: room?.propertyName ?? '',
      startDate: '${c['start_date'] ?? ''}',
      endDate: '${c['end_date'] ?? ''}',
      rentPrice: _double(c['rental_price']),
      depositAmount: _double(c['deposit_amount']),
      billingDayOfMonth: _int(c['billing_day_of_month'], 5),
      status: '${c['status'] ?? 'ACTIVE'}',
      termsAndConditions: '${c['terms_and_conditions'] ?? ''}',
      terminatedAt: '${c['terminated_at'] ?? ''}',
      terminationReason: '${c['termination_reason'] ?? ''}',
    );
  }

  static InvoiceItem _invoiceFromJson(
    Map<String, dynamic> i,
    List<RoomItem> rooms,
    List<TenantItem> tenants,
  ) {
    final rid = _intOrNull(i['room_id']);
    final tid = _intOrNull(i['tenant_id']);
    final room = rid != null ? rooms.where((r) => r.id == rid).firstOrNull : null;
    final tenant = tid != null ? tenants.where((t) => t.id == tid).firstOrNull : null;
    final month = _int(i['billing_month'], 11);
    final year = _int(i['billing_year'], 2026);
    return InvoiceItem(
      id: _int(i['id']),
      roomId: rid,
      contractId: _intOrNull(i['contract_id']),
      tenantId: tid,
      code: '${i['invoice_code'] ?? 'HDN-${i['id']}'}',
      tenantName: tenant?.fullName ?? (tid != null ? 'Khách #$tid' : '—'),
      roomName: room?.name ?? (rid != null ? 'Phòng #$rid' : '—'),
      propertyName: room?.propertyName ?? '',
      month: month,
      year: year,
      billingMonth: '$month/$year',
      roomFee: _double(i['room_fee']),
      electricityOld: _int(i['electricity_old_num']),
      electricityNew: _int(i['electricity_new_num']),
      electricityUnitPrice: _double(i['electricity_unit_price'], 3500),
      electricityCost: _double(i['electricity_cost']),
      waterOld: _int(i['water_old_num']),
      waterNew: _int(i['water_new_num']),
      waterUnitPrice: _double(i['water_unit_price'], 18000),
      waterCost: _double(i['water_cost']),
      otherServiceCost: _double(i['other_service_cost']),
      totalAmount: _double(i['total_amount']),
      dueDate: '${i['due_date'] ?? ''}',
      status: '${i['status'] ?? 'UNPAID'}',
    );
  }

  static NotificationItem _notificationFromJson(Map<String, dynamic> n) => NotificationItem(
        id: _int(n['id']),
        title: '${n['title'] ?? ''}',
        message: '${n['content'] ?? ''}',
        createdAt: '${n['created_at'] ?? ''}',
        category: '${n['category'] ?? 'SYSTEM'}',
        isRead: n['is_read'] == true,
      );

  /// Thực hiện thao tác ghi qua Gateway rồi đồng bộ lại. Trả về null nếu thành công,
  /// ngược lại trả về thông báo lỗi để UI hiển thị.
  /// Ghi qua Gateway rồi đồng bộ lại. Nếu người dùng đã đăng xuất / đổi tài khoản trong lúc
  /// request đang chờ thì không đồng bộ và không báo kết quả của phiên cũ cho phiên mới.
  Future<String?> _remoteWrite(Future<dynamic> Function() call) async {
    final gen = _sessionGeneration;
    try {
      await call();
    } on ApiException catch (e) {
      return gen == _sessionGeneration ? e.message : sessionChangedError;
    } catch (e) {
      return gen == _sessionGeneration ? e.toString() : sessionChangedError;
    }
    if (gen != _sessionGeneration) return sessionChangedError;
    // Đang có lượt đồng bộ khác -> được gộp thành một lượt chạy tiếp (không bị bỏ qua).
    await syncWithBackend();
    return null;
  }

  // ---------------- CRUD PROPERTY ----------------
  Map<String, dynamic> _propertyPayload(PropertyItem item) => {
        'name': item.name,
        'address': item.address,
        'district': item.district,
        'ward': item.ward,
        'status': item.status,
        'description': item.description,
        if (item.code.isNotEmpty) 'code': item.code,
      };

  Future<String?> addProperty(PropertyItem item) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post(ApiConstants.properties, _propertyPayload(item)));
  }

  Future<String?> updateProperty(PropertyItem updated) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(
        () => ApiClient.patch('${ApiConstants.properties}${updated.id}/', _propertyPayload(updated)));
  }

  Future<String?> deleteProperty(int id) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.delete('${ApiConstants.properties}$id/'));
  }

  Future<String?> updatePropertyStatus(int id, String status) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post(
          '${ApiConstants.properties}$id/update_status/',
          {'status': status},
        ));
  }

  // ---------------- CRUD ROOM ----------------
  Map<String, dynamic> _roomPayload(RoomItem item) => {
        'property': item.propertyId,
        'room_number': item.name,
        'floor': item.floor,
        'rent_price': item.rentPrice,
        'area': item.area,
        'max_occupants': item.maxOccupants,
        'current_occupants': item.currentOccupants,
        'status': item.status,
        'description': item.description,
        if (item.code.isNotEmpty) 'code': item.code,
      };

  Future<String?> addRoom(RoomItem item) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post(ApiConstants.rooms, _roomPayload(item)));
  }

  Future<String?> updateRoom(RoomItem updated) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.patch('${ApiConstants.rooms}${updated.id}/', _roomPayload(updated)));
  }

  Future<String?> deleteRoom(int id) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.delete('${ApiConstants.rooms}$id/'));
  }

  Future<String?> updateRoomStatus(int id, String status, {int? currentOccupants}) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post(
          '${ApiConstants.rooms}$id/status/',
          {
            'status': status,
            'current_occupants': ?currentOccupants,
          },
        ));
  }

  /// Kiểm tra khả năng cho thuê do Property Service quyết định.
  /// Ném [ApiException] khi chưa kết nối hoặc phản hồi không hợp lệ (không tự suy đoán kết quả).
  Future<Map<String, dynamic>> checkRoomRentable(RoomItem room) async {
    _ensureConnected();
    final gen = _sessionGeneration;
    final res = await ApiClient.get('${ApiConstants.rooms}${room.id}/check_rentable/');
    _ensureSameSession(gen);
    if (res is Map<String, dynamic>) return res;
    throw ApiException('Phản hồi kiểm tra phòng không hợp lệ từ API Gateway.');
  }

  // ---------------- CRUD TENANT ----------------
  Map<String, dynamic> _tenantPayload(TenantItem item) {
    final rid = item.roomId ?? _resolveRoomIdByName(item.currentRoom, item.propertyName);
    return {
      'full_name': item.fullName,
      'phone_number': item.phone,
      'email': item.email,
      'identity_card': item.idCard,
      'permanent_address': item.permanentAddress,
      'occupation': item.occupation,
      'emergency_contact_name': item.emergencyContactName,
      'emergency_contact_phone': item.emergencyContactPhone,
      'temporary_residence_registered': item.temporaryResidenceRegistered,
      'status': item.status,
      'notes': item.notes,
      'room_id': ?rid,
      // Liên kết tài khoản đăng nhập TENANT (Identity). Chỉ gửi khi có — không tự gỡ liên kết cũ.
      'user_id': ?item.userId,
    };
  }

  Future<String?> addTenant(TenantItem item) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post(ApiConstants.tenants, _tenantPayload(item)));
  }

  Future<String?> updateTenant(TenantItem updated) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(
        () => ApiClient.patch('${ApiConstants.tenants}${updated.id}/', _tenantPayload(updated)));
  }

  Future<String?> deleteTenant(int id) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.delete('${ApiConstants.tenants}$id/'));
  }

  Future<List<TenantHistoryItem>> fetchTenantHistory(int tenantId) async {
    _ensureConnected();
    final gen = _sessionGeneration;
    final res = await ApiClient.get('${ApiConstants.tenants}$tenantId/history/');
    _ensureSameSession(gen);
    if (res is! List) throw ApiException('Phản hồi lịch sử thuê không hợp lệ từ API Gateway.');
    return res.whereType<Map<String, dynamic>>().map((h) {
      return TenantHistoryItem(
        id: _int(h['id']),
        roomId: _intOrNull(h['room_id']),
        contractId: _intOrNull(h['contract_id']),
        moveInDate: '${h['move_in_date'] ?? ''}',
        moveOutDate: '${h['move_out_date'] ?? ''}',
        note: '${h['note'] ?? ''}',
      );
    }).toList();
  }

  Future<String?> addTenantHistory(
    int tenantId, {
    required int roomId,
    int? contractId,
    required String moveInDate,
    String? moveOutDate,
    String note = '',
  }) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post(
          '${ApiConstants.tenants}$tenantId/history/',
          {
            'room_id': roomId,
            'contract_id': ?contractId,
            'move_in_date': _toIsoDate(moveInDate),
            if (moveOutDate != null && moveOutDate.trim().isNotEmpty)
              'move_out_date': _toIsoDate(moveOutDate),
            'note': note,
          },
        ));
  }

  // ---------------- CRUD CONTRACT ----------------
  int? _resolveRoomIdByName(String roomName, String propertyName) {
    final name = roomName.trim().toLowerCase();
    if (name.isEmpty) return null;
    final prop = propertyName.trim().toLowerCase();
    final matches = _rooms.where((r) =>
        r.name.toLowerCase() == name ||
        r.code.toLowerCase() == name ||
        'phòng ${r.name}'.toLowerCase() == name);
    final narrowed = prop.isEmpty
        ? matches
        : matches.where((r) => r.propertyName.toLowerCase() == prop);
    final list = narrowed.isNotEmpty ? narrowed.toList() : matches.toList();
    return list.isNotEmpty ? list.first.id : null;
  }

  int? _resolveTenantIdByName(String tenantName) {
    final name = tenantName.trim().toLowerCase();
    if (name.isEmpty) return null;
    final match = _tenants.where((t) => t.fullName.toLowerCase() == name).firstOrNull;
    return match?.id;
  }

  Map<String, dynamic> _contractPayload(ContractItem item, {bool isCreate = false}) {
    final rid = item.roomId ?? _resolveRoomIdByName(item.roomName, item.propertyName);
    final tid = item.tenantId ?? _resolveTenantIdByName(item.tenantName);
    return {
      if (item.code.isNotEmpty) 'contract_number': item.code,
      'room_id': ?rid,
      'tenant_id': ?tid,
      'start_date': _toIsoDate(item.startDate),
      'end_date': _toIsoDate(item.endDate),
      'rental_price': item.rentPrice,
      'deposit_amount': item.depositAmount,
      'billing_day_of_month': item.billingDayOfMonth,
      if (isCreate) 'status': item.status == 'DRAFT' ? 'DRAFT' : 'ACTIVE',
      'terms_and_conditions': item.termsAndConditions,
    };
  }

  Future<String?> addContract(ContractItem item) async {
    if (!isBackendConnected) return offlineWriteError;
    final payload = _contractPayload(item, isCreate: true);
    if (payload['room_id'] == null || payload['tenant_id'] == null) {
      return 'Vui lòng chọn Phòng và Người thuê hợp lệ.';
    }
    return _remoteWrite(() => ApiClient.post(ApiConstants.contracts, payload));
  }

  Future<String?> updateContract(ContractItem updated) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.patch(
        '${ApiConstants.contracts}${updated.id}/', _contractPayload(updated)));
  }

  Future<String?> deleteContract(int id) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.delete('${ApiConstants.contracts}$id/'));
  }

  Future<String?> activateContract(int id) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post('${ApiConstants.contracts}$id/activate/', {}));
  }

  Future<String?> extendContract(
    int id, {
    required String newEndDate,
    double? rentalPrice,
    String note = '',
  }) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post(
          '${ApiConstants.contracts}$id/extend/',
          {
            'new_end_date': _toIsoDate(newEndDate),
            'rental_price': ?rentalPrice,
            if (note.isNotEmpty) 'note': note,
          },
        ));
  }

  Future<String?> terminateContract(
    int id, {
    String? terminatedAt,
    String reason = '',
  }) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post(
          '${ApiConstants.contracts}$id/terminate/',
          {
            if (terminatedAt != null && terminatedAt.trim().isNotEmpty)
              'terminated_at': _toIsoDate(terminatedAt),
            if (reason.isNotEmpty) 'reason': reason,
          },
        ));
  }

  Future<List<ContractEventItem>> fetchContractHistory(int id) async {
    _ensureConnected();
    final gen = _sessionGeneration;
    final res = await ApiClient.get('${ApiConstants.contracts}$id/history/');
    _ensureSameSession(gen);
    if (res is! List) throw ApiException('Phản hồi lịch sử hợp đồng không hợp lệ từ API Gateway.');
    return res.whereType<Map<String, dynamic>>().map((e) {
      return ContractEventItem(
        id: _int(e['id']),
        eventType: '${e['event_type'] ?? ''}',
        eventTypeDisplay: '${e['event_type_display'] ?? e['event_type'] ?? ''}',
        oldEndDate: '${e['old_end_date'] ?? ''}',
        newEndDate: '${e['new_end_date'] ?? ''}',
        note: '${e['note'] ?? ''}',
        createdAt: '${e['created_at'] ?? ''}',
      );
    }).toList();
  }

  // ---------------- CRUD INVOICE ----------------
  Map<String, dynamic> _invoicePayload(InvoiceItem item) {
    final rid = item.roomId ?? _resolveRoomIdByName(item.roomName, item.propertyName);
    final tid = item.tenantId ?? _resolveTenantIdByName(item.tenantName);
    final matchingContract = _contracts
        .where((c) =>
            (rid != null && c.roomId == rid) ||
            (c.roomName == item.roomName && c.tenantName == item.tenantName))
        .firstOrNull;
    final cid = item.contractId ?? matchingContract?.id;
    return {
      if (item.code.isNotEmpty) 'invoice_code': item.code,
      'room_id': ?rid,
      'contract_id': ?cid,
      'tenant_id': ?tid,
      'billing_month': item.month,
      'billing_year': item.year,
      'room_fee': item.roomFee,
      'electricity_old_num': item.electricityOld,
      'electricity_new_num': item.electricityNew,
      'electricity_unit_price': item.electricityUnitPrice,
      'water_old_num': item.waterOld,
      'water_new_num': item.waterNew,
      'water_unit_price': item.waterUnitPrice,
      'other_service_cost': item.otherServiceCost,
      'due_date': _toIsoDate(item.dueDate),
    };
  }

  Future<String?> addInvoice(InvoiceItem item) async {
    if (!isBackendConnected) return offlineWriteError;
    final payload = _invoicePayload(item);
    if (payload['room_id'] == null || payload['tenant_id'] == null) {
      return 'Vui lòng chọn Phòng và Người thuê hợp lệ để lập hóa đơn.';
    }
    return _remoteWrite(() => ApiClient.post(ApiConstants.invoices, payload));
  }

  Future<String?> updateInvoice(InvoiceItem updated) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.patch(
        '${ApiConstants.invoices}${updated.id}/', _invoicePayload(updated)));
  }

  Future<String?> deleteInvoice(int id) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.delete('${ApiConstants.invoices}$id/'));
  }

  Future<String?> payInvoice(int id) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post('${ApiConstants.invoices}$id/pay/', {}));
  }

  Future<String?> cancelInvoice(int id) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post('${ApiConstants.invoices}$id/cancel/', {}));
  }

  // ---------------- CRUD MAINTENANCE ----------------
  /// Form bảo trì nhập tên phòng dạng chữ -> tìm id phòng thật (theo tên/mã, có thể kèm tên nhà trọ).
  int? _resolveRoomId(MaintenanceItem item) {
    if (item.roomId > 0) return item.roomId;
    return _resolveRoomIdByName(item.roomName, item.propertyName);
  }

  Future<String?> addMaintenance(MaintenanceItem item) async {
    if (!isBackendConnected) return offlineWriteError;
    final roomId = _resolveRoomId(item);
    if (roomId == null) {
      return 'Không xác định được phòng "${item.roomName}". Nhập đúng tên hoặc mã phòng (kèm tên nhà trọ nếu trùng).';
    }
    return _remoteWrite(() => ApiClient.post(ApiConstants.maintenance, {
          'room': roomId,
          'title': item.title,
          'description': item.description,
          'repair_info': item.repairInfo,
          'technician_name': item.technicianName,
          'priority': item.priority,
          'estimated_cost': item.estimatedCost,
        }));
  }

  Future<String?> updateMaintenance(MaintenanceItem updated) async {
    if (!isBackendConnected) return offlineWriteError;
    final current = _maintenances.where((m) => m.id == updated.id).firstOrNull;
    return _remoteWrite(() async {
      await ApiClient.patch('${ApiConstants.maintenance}${updated.id}/', {
        'title': updated.title,
        'description': updated.description,
        'repair_info': updated.repairInfo,
        'technician_name': updated.technicianName,
        'priority': updated.priority,
        'estimated_cost': updated.estimatedCost,
        'actual_cost': updated.actualCost,
      });
      // Trạng thái bảo trì chỉ đổi qua action để backend đồng bộ trạng thái phòng + lịch sử.
      if (current != null && current.status != updated.status && updated.status != 'PENDING') {
        await ApiClient.post('${ApiConstants.maintenance}${updated.id}/update_status/', {'status': updated.status});
      }
    });
  }

  Future<String?> recordMaintenanceCost(
    int id, {
    required double estimatedCost,
    required double actualCost,
    String repairInfo = '',
  }) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post(
          '${ApiConstants.maintenance}$id/record_cost/',
          {
            'estimated_cost': estimatedCost,
            'actual_cost': actualCost,
            if (repairInfo.isNotEmpty) 'repair_info': repairInfo,
          },
        ));
  }

  Future<String?> completeMaintenance(
    int id, {
    required double actualCost,
    required String roomStatus,
    required String repairInfo,
  }) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post(
          '${ApiConstants.maintenance}$id/complete/',
          {
            'actual_cost': actualCost,
            'room_status': roomStatus,
            'repair_info': repairInfo,
          },
        ));
  }

  Future<String?> deleteMaintenance(int id) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.delete('${ApiConstants.maintenance}$id/'));
  }

  // ---------------- NOTIFICATIONS ----------------
  Future<String?> markAllNotificationsRead() async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post('${ApiConstants.notifications}read-all/', {}));
  }

  Future<String?> markNotificationRead(int id) async {
    if (!isBackendConnected) return offlineWriteError;
    return _remoteWrite(() => ApiClient.post('${ApiConstants.notifications}$id/read/', {}));
  }
}

