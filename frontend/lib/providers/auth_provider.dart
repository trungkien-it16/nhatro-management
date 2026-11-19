import 'package:flutter/foundation.dart';

import '../core/constants/api_constants.dart';
import '../shared/services/api_client.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Trạng thái đăng nhập của ứng dụng. Xác thực qua Identity Service, đi qua API Gateway.
class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider() {
    ApiClient.onSessionExpired = _handleSessionExpired;
  }

  AuthStatus get status => _status;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get user => _user;

  String get role => '${_user?['role'] ?? ''}';
  String get displayName {
    final name = '${_user?['full_name'] ?? ''}'.trim();
    return name.isNotEmpty ? name : '${_user?['username'] ?? 'Người dùng'}';
  }

  String get roleDisplay {
    final display = '${_user?['role_display'] ?? ''}'.trim();
    if (display.isNotEmpty) return display;
    return switch (role) {
      'ADMIN' => 'Quản trị viên',
      'LANDLORD' => 'Chủ nhà trọ',
      'STAFF' => 'Quản lý / Nhân viên',
      'TENANT' => 'Khách thuê',
      _ => role,
    };
  }

  /// Vai trò quản lý chính thức (ADMIN, LANDLORD). STAFF legacy không có quyền quản lý trên giao diện.
  bool get isManager => const {'ADMIN', 'LANDLORD'}.contains(role);

  bool get isAdmin => role == 'ADMIN';

  /// Khôi phục phiên đã lưu và xác minh token với Identity Service (/auth/me/).
  Future<void> restoreSession() async {
    final token = await ApiClient.getAccessToken();
    if (token == null || token.isEmpty) {
      _setUnauthenticated();
      return;
    }
    _user = await ApiClient.getSavedUser();
    try {
      final me = await ApiClient.get(ApiConstants.currentUser);
      if (me is Map<String, dynamic>) {
        _user = me;
        await ApiClient.saveSession(access: (await ApiClient.getAccessToken())!, user: me);
      }
      _status = AuthStatus.authenticated;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await ApiClient.clearSession();
        _setUnauthenticated();
        return;
      }
      // Gateway/Identity tạm không phản hồi: giữ phiên cục bộ, dữ liệu sẽ đồng bộ lại sau.
      _status = _user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _user = await ApiClient.login(username.trim(), password);
      _status = AuthStatus.authenticated;
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.isUnauthorized ? 'Sai tên đăng nhập hoặc mật khẩu.' : e.message;
      _status = AuthStatus.unauthenticated;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await ApiClient.logout();
    _setUnauthenticated();
  }

  /// Vai trò được phép tự đăng ký (backend RegisterSerializer.PUBLIC_ROLES).
  static const publicRegisterRoles = {'LANDLORD', 'TENANT'};

  /// Đăng ký tài khoản mới qua Identity Service (/auth/register/).
  /// Không đăng nhập tự động và không đổi trạng thái phiên: backend không trả token.
  /// Ném [ApiException] (kèm `body` lỗi theo trường của DRF) khi thất bại.
  Future<Map<String, dynamic>> register(Map<String, dynamic> payload) async {
    final role = payload['role'];
    if (!publicRegisterRoles.contains(role)) {
      throw ApiException('Chỉ được đăng ký vai trò Chủ nhà trọ hoặc Khách thuê.');
    }
    final res = await ApiClient.post(
      ApiConstants.register,
      payload,
      requireAuth: false,
      retryOnUnauthorized: false,
    );
    if (res is! Map<String, dynamic>) {
      throw ApiException('Phản hồi đăng ký không hợp lệ từ API Gateway.');
    }
    return res;
  }

  /// Đổi mật khẩu tài khoản đang đăng nhập qua Identity Service (/auth/change-password/).
  Future<String?> changePassword(String oldPassword, String newPassword) async {
    try {
      await ApiClient.post(ApiConstants.changePassword, {
        'old_password': oldPassword,
        'new_password': newPassword,
      });
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Cập nhật hồ sơ người dùng hiện tại (/auth/me/).
  Future<String?> updateProfile(Map<String, dynamic> payload) async {
    try {
      final res = await ApiClient.patch(ApiConstants.currentUser, payload);
      if (res is Map<String, dynamic>) {
        _user = res;
        final token = await ApiClient.getAccessToken();
        if (token != null) {
          await ApiClient.saveSession(access: token, user: res);
        }
        notifyListeners();
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Lấy danh sách tài khoản mẫu khi backend bật DEBUG=True (/auth/test-users/).
  Future<List<Map<String, dynamic>>> fetchTestAccounts() async {
    try {
      final res = await ApiClient.get(ApiConstants.testUsers, requireAuth: false);
      if (res is Map<String, dynamic> && res['test_accounts'] is List) {
        return (res['test_accounts'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      }
    } catch (_) {
      // Production trả 404 hoặc Gateway chưa chạy -> ẩn danh sách nhanh.
    }
    return const [];
  }

  /// Quản lý tài khoản & phân quyền (/api/users/ — ADMIN / LANDLORD).
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final res = await ApiClient.get(ApiConstants.users);
    if (res is List) {
      return res.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  Future<String?> createUser(Map<String, dynamic> payload) async {
    try {
      await ApiClient.post(ApiConstants.users, payload);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Tạo tài khoản và trả về id do Identity Service cấp (để liên kết hồ sơ người thuê).
  /// Chỉ gọi POST đúng một lần; không tự thử lại để tránh tạo trùng tài khoản.
  Future<({int? id, String? error})> createUserReturningId(Map<String, dynamic> payload) async {
    try {
      final res = await ApiClient.post(ApiConstants.users, payload);
      final id = res is Map ? int.tryParse('${res['id']}') : null;
      if (id == null) {
        return (id: null, error: 'Identity Service không trả về mã tài khoản vừa tạo. '
            'Kiểm tra lại danh sách tài khoản trước khi thử tạo lại để tránh trùng.');
      }
      return (id: id, error: null);
    } on ApiException catch (e) {
      return (id: null, error: e.message);
    } catch (e) {
      return (id: null, error: e.toString());
    }
  }

  Future<String?> updateUser(int id, Map<String, dynamic> payload) async {
    try {
      await ApiClient.patch('${ApiConstants.users}$id/', payload);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteUser(int id) async {
    try {
      await ApiClient.delete('${ApiConstants.users}$id/');
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  void _handleSessionExpired() {
    if (_status == AuthStatus.authenticated) {
      _errorMessage = 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.';
      _setUnauthenticated();
    }
  }

  void _setUnauthenticated() {
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
