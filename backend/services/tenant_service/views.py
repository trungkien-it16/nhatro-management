from django.db.models import Q
from rest_framework import permissions, serializers, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from common.auth import IsManagerRole, get_user_id, is_admin, is_landlord
from common.service_client import auth_header_from_user, room_accessible, tenant_account_eligible
from common.sprint import SprintFeatureLock
from .models import TenantProfile, TenantStatus
from .serializers import RentalHistorySerializer, TenantProfileSerializer


def scoped_tenants(user):
    """
    - ADMIN         : toàn bộ
    - LANDLORD      : người thuê do mình quản lý (landlord_id)
    - TENANT (và STAFF legacy): chỉ hồ sơ gắn với tài khoản của mình (user_id)
    """
    queryset = TenantProfile.objects.all()
    if is_admin(user):
        return queryset
    if is_landlord(user):
        return queryset.filter(landlord_id=get_user_id(user))
    return queryset.filter(user_id=get_user_id(user))


class TenantProfileViewSet(viewsets.ModelViewSet):
    """
    SERVICE 3 — TENANT SERVICE
    - CRUD hồ sơ người thuê (quản lý: ADMIN/LANDLORD; TENANT chỉ xem hồ sơ của mình)
    - Lọc: ?search= (tên/SĐT/CCCD), ?status=, ?room_id=
    - GET /{id}/history/       lịch sử thuê (POST tạm khóa — ngoài Sprint hiện tại)
    - GET /summary/            thống kê (Dashboard qua Gateway)
    - GET /links/              liên kết user_id ↔ tenant_id ↔ room_id trong phạm vi người gọi
    """
    serializer_class = TenantProfileSerializer
    # D3: ghi lịch sử thuê là nghiệp vụ Sprint sau.
    sprint_locked_actions = ('history:POST',)

    def get_permissions(self):
        if self.action in ('list', 'retrieve', 'summary', 'links') or (
                self.action == 'history' and self.request.method == 'GET'):
            return [permissions.IsAuthenticated(), SprintFeatureLock()]
        return [permissions.IsAuthenticated(), IsManagerRole(), SprintFeatureLock()]

    def get_queryset(self):
        queryset = scoped_tenants(self.request.user)
        params = self.request.query_params
        search = params.get('search')
        if search:
            queryset = queryset.filter(
                Q(full_name__icontains=search) | Q(phone_number__icontains=search) |
                Q(identity_card__icontains=search))
        if params.get('status') and params['status'] != 'ALL':
            queryset = queryset.filter(status=params['status'])
        if params.get('room_id'):
            queryset = queryset.filter(room_id=params['room_id'])
        return queryset

    def _validate_links(self, serializer, landlord_id):
        """
        Kiểm tra quyền sở hữu trước khi ghi liên kết:
        - room_id phải là phòng người gọi được quản lý (hỏi Property Service bằng JWT của họ;
          LANDLORD chỉ thấy phòng thuộc nhà trọ của mình). Service không phản hồi -> 503 (fail-closed).
        - user_id không được đang gắn với hồ sơ còn hiệu lực của CHỦ TRỌ KHÁC
          (chặn việc "nhận" tài khoản người thuê của người khác để quản lý).
        - user_id phải là tài khoản TENANT đang hoạt động (hỏi Identity Service; lỗi -> 503).
        """
        data = serializer.validated_data
        instance = serializer.instance
        room_id = data.get('room_id')
        if room_id is not None and (instance is None or room_id != instance.room_id):
            if not room_accessible(auth_header_from_user(self.request.user), room_id):
                raise serializers.ValidationError({'room_id': 'Phòng không tồn tại hoặc không thuộc phạm vi quản lý của bạn.'})
        user_id = data.get('user_id')
        if user_id is not None and (instance is None or user_id != instance.user_id):
            conflict = TenantProfile.objects.filter(user_id=user_id).exclude(status=TenantStatus.MOVED_OUT)
            if instance is not None:
                conflict = conflict.exclude(pk=instance.pk)
            if conflict.exclude(landlord_id=landlord_id).exists():
                raise serializers.ValidationError(
                    {'user_id': 'Tài khoản này đang gắn với hồ sơ người thuê của chủ trọ khác.'})
            # Chỉ tài khoản role TENANT đang hoạt động (xác minh ở Identity Service, không tin client).
            if not tenant_account_eligible(auth_header_from_user(self.request.user), user_id):
                raise serializers.ValidationError(
                    {'user_id': 'Chỉ được liên kết tài khoản có vai trò Khách thuê (TENANT) đang hoạt động.'})

    def perform_create(self, serializer):
        landlord_id = get_user_id(self.request.user)
        self._validate_links(serializer, landlord_id)
        serializer.save(landlord_id=landlord_id)

    def perform_update(self, serializer):
        self._validate_links(serializer, serializer.instance.landlord_id)
        serializer.save()

    @action(detail=True, methods=['get', 'post'])
    def history(self, request, pk=None):
        tenant = self.get_object()
        if request.method == 'GET':
            return Response(RentalHistorySerializer(tenant.rental_history.all(), many=True).data)
        serializer = RentalHistorySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(tenant=tenant)
        return Response(serializer.data, status=201)

    @action(detail=False, methods=['get'])
    def summary(self, request):
        queryset = scoped_tenants(request.user)
        return Response({
            'total_tenants': queryset.count(),
            'active_tenants': queryset.filter(status=TenantStatus.ACTIVE).count(),
            'moved_out_tenants': queryset.filter(status=TenantStatus.MOVED_OUT).count(),
        })

    @action(detail=False, methods=['get'])
    def links(self, request):
        """
        Liên kết user_id ↔ tenant_id ↔ room_id (chỉ đọc) — dùng cho các service khác kiểm tra quyền sở hữu.
        Phạm vi theo JWT người gọi (scoped_tenants), KHÔNG nhận ID từ tham số client.
        """
        rows = scoped_tenants(request.user).values('id', 'user_id', 'room_id', 'landlord_id', 'status')
        return Response([
            {'tenant_id': r['id'], 'user_id': r['user_id'], 'room_id': r['room_id'],
             'landlord_id': r['landlord_id'], 'status': r['status']}
            for r in rows
        ])
