"""
Phân quyền dựa trên JWT claims do Identity Service phát hành.

Các service 2–5 dùng JWTStatelessUserAuthentication -> request.user là TokenUser,
mọi thuộc tính lấy từ claims (user_id, username, role, is_superuser).
Identity Service dùng User thật nhưng có cùng thuộc tính `role` / `is_superuser`,
nên các hàm dưới đây hoạt động ở cả hai nơi mà không cần import model User.

Ba vai trò chính thức: ADMIN, LANDLORD, TENANT.
STAFF chỉ còn để tương thích dữ liệu cũ: KHÔNG có quyền quản trị/quản lý; mọi chỗ
kiểm tra quyền đều xử lý STAFF như vai trò hẹp nhất (chỉ dữ liệu gắn với chính tài khoản đó).
"""
from rest_framework import permissions

# Giá trị role là "hợp đồng" giữa các service (claim `role` trong JWT).
# Nguồn gốc định nghĩa: identity_service.models.UserRole.
ADMIN = 'ADMIN'
LANDLORD = 'LANDLORD'
STAFF = 'STAFF'  # legacy — không được cấp quyền nào ngoài quyền tối thiểu
TENANT = 'TENANT'
ALL_ROLES = (ADMIN, LANDLORD, STAFF, TENANT)
OFFICIAL_ROLES = (ADMIN, LANDLORD, TENANT)


def get_role(user):
    if not user or not getattr(user, 'is_authenticated', False):
        return None
    if getattr(user, 'is_superuser', False):
        return ADMIN
    role = getattr(user, 'role', None)
    # Token không có claim role (token cũ) -> xử lý như quyền hẹp nhất.
    return role if role in ALL_ROLES else TENANT


def get_user_id(user):
    uid = getattr(user, 'id', None)
    try:
        return int(uid) if uid is not None else None
    except (TypeError, ValueError):
        return None


def is_admin(user):
    return get_role(user) == ADMIN


def is_landlord(user):
    return get_role(user) == LANDLORD


def is_manager(user):
    """ADMIN / LANDLORD — các vai trò được quản lý dữ liệu (STAFF KHÔNG thuộc nhóm này)."""
    return get_role(user) in (ADMIN, LANDLORD)


class IsManagerRole(permissions.BasePermission):
    """Chỉ ADMIN hoặc LANDLORD."""
    message = 'Chỉ Quản trị viên hoặc Chủ trọ được thực hiện thao tác này.'

    def has_permission(self, request, view):
        return is_manager(request.user)


class IsManagerOrReadOnly(permissions.BasePermission):
    """Mọi user đã đăng nhập được đọc (trong phạm vi dữ liệu của mình); chỉ ADMIN/LANDLORD được ghi."""
    message = IsManagerRole.message

    def has_permission(self, request, view):
        if not (request.user and request.user.is_authenticated):
            return False
        if request.method in permissions.SAFE_METHODS:
            return True
        return is_manager(request.user)
