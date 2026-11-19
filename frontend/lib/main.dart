import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/auth/role_access.dart';
import 'core/theme/app_theme.dart';
import 'features/account/presentation/accounts_page.dart';
import 'features/auth/presentation/forbidden_page.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/register_page.dart';
import 'features/billing/presentation/billing_page.dart';
import 'features/contract/presentation/contract_page.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/maintenance/presentation/maintenance_page.dart';
import 'features/notification/presentation/notification_page.dart';
import 'features/notification/presentation/settings_page.dart';
import 'features/property/presentation/property_page.dart';
import 'features/system/presentation/system_page.dart';
import 'features/tenant_portal/presentation/my_bills_page.dart';
import 'features/tenant_portal/presentation/my_contracts_page.dart';
import 'features/tenant_portal/presentation/my_profile_page.dart';
import 'features/tenant_portal/presentation/my_room_page.dart';
import 'features/room/presentation/room_create_page.dart';
import 'features/room/presentation/room_detail_page.dart';
import 'features/room/presentation/room_page.dart';
import 'features/tenant/presentation/tenant_page.dart';
import 'providers/auth_provider.dart';
import 'shared/layouts/main_layout.dart';
import 'shared/services/app_data_repository.dart';

void main() {
  usePathUrlStrategy();
  runApp(const NhaTroManagerApp());
}

class NhaTroManagerApp extends StatefulWidget {
  /// Cho phép test truyền sẵn provider (không gọi mạng khi khởi tạo).
  final AuthProvider? authProvider;
  final AppDataRepository? repository;

  const NhaTroManagerApp({super.key, this.authProvider, this.repository});

  @override
  State<NhaTroManagerApp> createState() => _NhaTroManagerAppState();
}

class _NhaTroManagerAppState extends State<NhaTroManagerApp> {
  late final AuthProvider _auth = widget.authProvider ?? AuthProvider();
  late final AppDataRepository _repository = widget.repository ?? AppDataRepository();
  AuthStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    if (widget.authProvider == null) {
      _auth.restoreSession();
    } else {
      _onAuthChanged();
    }
  }

  /// Đăng nhập -> đồng bộ dữ liệu thật qua Gateway; đăng xuất -> xóa dữ liệu phiên.
  void _onAuthChanged() {
    final status = _auth.status;
    if (status == _lastStatus) return;
    _lastStatus = status;
    if (status == AuthStatus.authenticated) {
      _repository.syncWithBackend();
    } else if (status == AuthStatus.unauthenticated) {
      _repository.resetAfterLogout();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  static GoRoute _page(String path, Widget page) =>
      GoRoute(path: path, builder: (_, _) => MainPageScroll(child: page));

  late final GoRouter _router = GoRouter(
    initialLocation: RoleAccess.home,
    refreshListenable: _auth,
    redirect: (_, state) {
      final path = state.uri.path;
      // Route cũ -> route chuẩn (giữ tương thích link/bookmark).
      final legacy = RoleAccess.legacyRedirects[path];
      if (legacy != null) return legacy;
      // Trang công khai: đăng nhập và đăng ký (chỉ dành cho người chưa đăng nhập).
      final atPublic = const {'/login', '/register'}.contains(path);
      switch (_auth.status) {
        case AuthStatus.unknown:
          return null; // đang khôi phục phiên
        case AuthStatus.unauthenticated:
          return atPublic ? null : '/login';
        case AuthStatus.authenticated:
          final role = _auth.role;
          if (atPublic) return RoleAccess.homeFor(role);
          if (RoleAccess.canAccess(role, path)) return null;
          // Trang không thuộc vai trò (vd. gõ thẳng URL) -> báo không có quyền.
          return Uri(path: RoleAccess.forbiddenRoute, queryParameters: {'from': path}).toString();
      }
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, _) => const RegisterPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainLayout(
          currentLocation: state.uri.path,
          child: child,
        ),
        routes: [
          // Dashboard theo vai trò.
          _page(RoleAccess.home, const DashboardPage()),
          // ADMIN
          _page(RoleAccess.accounts, const AccountsPage()),
          _page(RoleAccess.system, const SystemPage()),
          // ADMIN + LANDLORD
          _page(RoleAccess.properties, const PropertyPage()),
          _page(RoleAccess.rooms, const RoomPage()),
          _page('${RoleAccess.rooms}/create', const RoomCreatePage()),
          GoRoute(
            path: '${RoleAccess.rooms}/:id',
            builder: (_, state) => MainPageScroll(
              child: RoomDetailPage(
                roomId: state.pathParameters['id'] ?? '',
              ),
            ),
          ),
          _page(RoleAccess.tenants, const TenantPage()),
          _page(RoleAccess.contracts, const ContractPage()),
          _page(RoleAccess.bills, const BillingPage()),
          // Bảo trì: giữ route/source cho Sprint sau; RoleAccess chưa mở cho vai trò nào.
          _page(RoleAccess.maintenance, const MaintenancePage()),
          // TENANT (chỉ xem dữ liệu của mình)
          _page(RoleAccess.myRoom, const MyRoomPage()),
          _page(RoleAccess.myProfile, const MyProfilePage()),
          _page(RoleAccess.myContracts, const MyContractsPage()),
          _page(RoleAccess.myBills, const MyBillsPage()),
          // Chung
          _page(RoleAccess.notifications, const NotificationPage()),
          _page(RoleAccess.settings, const SettingsPage()),
          GoRoute(
            path: RoleAccess.forbiddenRoute,
            builder: (_, state) => MainPageScroll(
              child: ForbiddenPage(attemptedPath: state.uri.queryParameters['from']),
            ),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider<AppDataRepository>.value(value: _repository),
      ],
      child: MaterialApp.router(
        title: 'Nhà Trọ Manager — SaaS SOA Platform',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: _router,
      ),
    );
  }
}
