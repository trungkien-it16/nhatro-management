import 'package:flutter/material.dart';

/// Một mục menu (sidebar / mobile nav) theo vai trò.
class RoleMenuItem {
  final String label;
  final String route;
  final IconData icon;

  /// Port của service sở hữu dữ liệu trang này (chỉ để hiển thị).
  final int? port;

  const RoleMenuItem(this.label, this.route, this.icon, {this.port});
}

/// Phân quyền truy cập trang theo vai trò (frontend).
///
/// Bám theo quyền thực tế của backend (JWT claim `role`). Ba vai trò chính thức:
/// - ADMIN    : quản trị toàn hệ thống (+ Tài khoản, Quản trị hệ thống).
/// - LANDLORD : quản lý dữ liệu nhà trọ của mình.
/// - TENANT   : chỉ xem dữ liệu của chính mình (các trang /my-*).
/// STAFF (legacy) / vai trò rỗng / không xác định: quyền hẹp nhất như TENANT.
///
/// Đây chỉ là lớp chặn giao diện; backend vẫn là nơi kiểm tra quyền cuối cùng.
class RoleAccess {
  RoleAccess._();

  static const admin = 'ADMIN';
  static const landlord = 'LANDLORD';
  static const managerRoles = {admin, landlord};

  // ---- Route chuẩn của ứng dụng ----
  static const home = '/';
  static const accounts = '/accounts';
  static const properties = '/properties';
  static const rooms = '/rooms';
  static const tenants = '/tenants';
  static const contracts = '/contracts';
  static const bills = '/bills';
  static const notifications = '/notifications';
  static const system = '/system';
  static const settings = '/settings';
  static const myRoom = '/my-room';
  static const myProfile = '/my-profile';
  static const myContracts = '/my-contracts';
  static const myBills = '/my-bills';

  /// Bảo trì: source code giữ lại cho Sprint sau nhưng không mở cho vai trò nào ở Sprint hiện tại
  /// (API ghi đã khóa ở backend).
  static const maintenance = '/maintenance';

  /// Trang báo không có quyền.
  static const forbiddenRoute = '/forbidden';

  /// Route cũ -> route chuẩn (tương thích link / bookmark cũ).
  static const legacyRedirects = {
    '/dashboard': home,
    '/property': properties,
    '/tenant': tenants,
    '/contract': contracts,
    '/billing': bills,
  };

  /// Trang chung cho mọi người dùng đã đăng nhập.
  static const _sharedRoutes = [home, notifications, settings];

  static const _landlordRoutes = [properties, rooms, tenants, contracts, bills];
  static const _adminOnlyRoutes = [accounts, system];
  static const _tenantRoutes = [myRoom, myProfile, myContracts, myBills];

  static bool isManager(String? role) => managerRoles.contains(role);
  static bool isAdmin(String? role) => role == admin;

  /// Vai trò chính thức dùng để hiển thị menu (STAFF / không xác định -> TENANT).
  static String effectiveRole(String? role) => isManager(role) ? role! : 'TENANT';

  static bool _matches(String path, String route) =>
      route == home ? path == home : (path == route || path.startsWith('$route/'));

  static List<String> allowedRoutes(String? role) => [
        ..._sharedRoutes,
        if (isManager(role)) ..._landlordRoutes,
        if (isAdmin(role)) ..._adminOnlyRoutes,
        if (!isManager(role)) ..._tenantRoutes,
      ];

  /// Người dùng có [role] có được mở [path] không (chỉ áp dụng cho trang cần đăng nhập).
  /// Mặc định từ chối: trang mới phải được khai báo rõ cho vai trò.
  static bool canAccess(String? role, String path) {
    if (path == forbiddenRoute) return true;
    return allowedRoutes(role).any((r) => _matches(path, r));
  }

  /// Mô tả ai được mở [path] — dùng cho thông báo "Không có quyền truy cập" (không quyết định quyền).
  static String audienceFor(String path) {
    if (_adminOnlyRoutes.any((r) => _matches(path, r))) return 'Trang này chỉ dành cho Quản trị viên (ADMIN).';
    if (_landlordRoutes.any((r) => _matches(path, r))) {
      return 'Trang này chỉ dành cho Quản trị viên hoặc Chủ nhà trọ.';
    }
    if (_tenantRoutes.any((r) => _matches(path, r))) {
      return 'Trang này dành cho Khách thuê; vai trò quản lý xem dữ liệu ở các trang quản lý.';
    }
    return 'Trang này chưa được mở cho vai trò của bạn trong Sprint hiện tại.';
  }

  /// Trang chính sau đăng nhập: Dashboard theo vai trò.
  static String homeFor(String? role) => home;

  /// Menu chính (không gồm Cài đặt — Cài đặt luôn nằm cuối sidebar).
  static List<RoleMenuItem> menuFor(String? role) {
    if (isAdmin(role)) {
      return const [
        RoleMenuItem('Dashboard', home, Icons.bar_chart_rounded),
        RoleMenuItem('Tài khoản', accounts, Icons.manage_accounts_outlined, port: 8001),
        ..._managerData,
        RoleMenuItem('Thông báo', notifications, Icons.notifications_none_rounded, port: 8005),
        RoleMenuItem('Quản trị hệ thống', system, Icons.hub_outlined),
      ];
    }
    if (isManager(role)) {
      return const [
        RoleMenuItem('Dashboard', home, Icons.bar_chart_rounded),
        ..._managerData,
        RoleMenuItem('Thông báo', notifications, Icons.notifications_none_rounded, port: 8005),
      ];
    }
    return const [
      RoleMenuItem('Dashboard cá nhân', home, Icons.dashboard_outlined),
      RoleMenuItem('Phòng đang thuê', myRoom, Icons.door_front_door_outlined, port: 8002),
      RoleMenuItem('Hồ sơ của tôi', myProfile, Icons.badge_outlined, port: 8003),
      RoleMenuItem('Hợp đồng của tôi', myContracts, Icons.description_outlined, port: 8004),
      RoleMenuItem('Hóa đơn của tôi', myBills, Icons.payments_outlined, port: 8005),
      RoleMenuItem('Thông báo', notifications, Icons.notifications_none_rounded, port: 8005),
    ];
  }

  static const _managerData = [
    RoleMenuItem('Nhà trọ', properties, Icons.apartment_rounded, port: 8002),
    RoleMenuItem('Phòng', rooms, Icons.door_front_door_outlined, port: 8002),
    RoleMenuItem('Khách thuê', tenants, Icons.people_outline_rounded, port: 8003),
    RoleMenuItem('Hợp đồng', contracts, Icons.description_outlined, port: 8004),
    RoleMenuItem('Hóa đơn', bills, Icons.payments_outlined, port: 8005),
  ];

  static const settingsItem = RoleMenuItem('Cài đặt', settings, Icons.settings_outlined, port: 8001);

  /// Tiêu đề trang cho thanh trên cùng.
  static String titleFor(String path) {
    const titles = {
      accounts: 'Quản lý tài khoản',
      properties: 'Quản lý nhà trọ',
      rooms: 'Quản lý phòng',
      tenants: 'Quản lý khách thuê',
      contracts: 'Hợp đồng',
      bills: 'Hóa đơn',
      notifications: 'Thông báo',
      system: 'Quản trị hệ thống',
      settings: 'Cài đặt',
      myRoom: 'Phòng đang thuê',
      myProfile: 'Hồ sơ của tôi',
      myContracts: 'Hợp đồng của tôi',
      myBills: 'Hóa đơn của tôi',
      maintenance: 'Bảo trì & sửa chữa',
      forbiddenRoute: 'Không có quyền truy cập',
    };
    if (path == home) return 'Dashboard';
    for (final e in titles.entries) {
      if (_matches(path, e.key)) return e.value;
    }
    return 'Nhatro Pro';
  }
}
