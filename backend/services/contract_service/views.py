from datetime import timedelta

from django.db import transaction
from django.utils import timezone
from django.utils.crypto import get_random_string
from django.utils.dateparse import parse_date
from rest_framework import permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from common.auth import IsManagerRole, get_user_id, is_admin, is_landlord
from common.service_client import own_tenant_ids
from common.sprint import SprintFeatureLock
from .models import Contract, ContractEvent, ContractEventType, ContractStatus
from .serializers import ContractEventSerializer, ContractSerializer


def scoped_contracts(user):
    """
    - ADMIN         : toàn bộ
    - LANDLORD      : hợp đồng do mình lập (landlord_id = user_id trong JWT)
    - TENANT (và STAFF legacy): hợp đồng có tenant_id thuộc hồ sơ người thuê gắn với user_id của mình.
      Contract.tenant_id là ID hồ sơ ở Tenant Service (KHÔNG phải user_id) -> tra qua
      Tenant Service /api/tenants/links/ bằng JWT của người dùng; lỗi -> 503 (không trả dữ liệu).
    """
    queryset = Contract.objects.all()
    if is_admin(user):
        return queryset
    if is_landlord(user):
        return queryset.filter(landlord_id=get_user_id(user))
    return queryset.filter(tenant_id__in=own_tenant_ids(user))


def _generate_contract_number():
    return f"HD{timezone.now():%Y%m%d}-{get_random_string(6, '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ')}"


class ContractViewSet(viewsets.ModelViewSet):
    """
    SERVICE 4 — CONTRACT SERVICE
    - GET  /contracts/       danh sách (lọc ?status=, ?room_id=, ?tenant_id=) trong phạm vi người dùng
    - GET  /{id}/            chi tiết
    - GET  /{id}/history/    lịch sử thay đổi
    - GET  /summary/         thống kê (Dashboard qua Gateway)
    Tạm khóa (D3 — nghiệp vụ Sprint sau, source code giữ nguyên):
    - POST/PUT/PATCH/DELETE hợp đồng, POST /{id}/activate/, /{id}/extend/, /{id}/terminate/
    """
    serializer_class = ContractSerializer
    sprint_locked_actions = ('create', 'update', 'partial_update', 'destroy', 'activate', 'extend', 'terminate')
    READ_ACTIONS = ('list', 'retrieve', 'history', 'summary')

    def get_permissions(self):
        if self.action in self.READ_ACTIONS:
            return [permissions.IsAuthenticated(), SprintFeatureLock()]
        return [permissions.IsAuthenticated(), IsManagerRole(), SprintFeatureLock()]

    def get_queryset(self):
        queryset = scoped_contracts(self.request.user)
        params = self.request.query_params
        if params.get('status') and params['status'] != 'ALL':
            if params['status'] == 'ACTIVE_ALL':
                queryset = queryset.filter(status__in=Contract.ACTIVE_STATUSES)
            else:
                queryset = queryset.filter(status=params['status'])
        for field in ('room_id', 'tenant_id'):
            if params.get(field):
                queryset = queryset.filter(**{field: params[field]})
        return queryset

    def _log(self, contract, event_type, **kwargs):
        ContractEvent.objects.create(
            contract=contract, event_type=event_type, actor_id=get_user_id(self.request.user), **kwargs)

    @transaction.atomic
    def perform_create(self, serializer):
        number = serializer.validated_data.get('contract_number') or _generate_contract_number()
        contract = serializer.save(landlord_id=get_user_id(self.request.user), contract_number=number)
        self._log(contract, ContractEventType.CREATED, new_end_date=contract.end_date)

    @transaction.atomic
    def perform_update(self, serializer):
        contract = serializer.save()
        self._log(contract, ContractEventType.UPDATED)

    def _bad(self, message):
        return Response({'error': message}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=['post'])
    @transaction.atomic
    def activate(self, request, pk=None):
        contract = self.get_object()
        if contract.status != ContractStatus.DRAFT:
            return self._bad('Chỉ kích hoạt được hợp đồng ở trạng thái DRAFT.')
        if Contract.objects.filter(room_id=contract.room_id, status__in=Contract.ACTIVE_STATUSES).exists():
            return self._bad('Phòng này đang có hợp đồng hiệu lực.')
        contract.status = ContractStatus.ACTIVE
        contract.save(update_fields=['status', 'updated_at'])
        self._log(contract, ContractEventType.ACTIVATED)
        return Response(self.get_serializer(contract).data)

    @action(detail=True, methods=['post'])
    @transaction.atomic
    def extend(self, request, pk=None):
        contract = self.get_object()
        if not contract.is_active and contract.status != ContractStatus.EXPIRED:
            return self._bad('Chỉ gia hạn được hợp đồng đang hiệu lực hoặc vừa hết hạn.')
        new_end = parse_date(str(request.data.get('new_end_date', '')))
        if not new_end or new_end <= contract.end_date:
            return self._bad('new_end_date (YYYY-MM-DD) phải sau ngày kết thúc hiện tại.')
        old_end = contract.end_date
        contract.end_date = new_end
        if request.data.get('rental_price') not in (None, ''):
            contract.rental_price = request.data['rental_price']
        contract.status = ContractStatus.EXTENDED
        contract.save()
        self._log(contract, ContractEventType.EXTENDED, old_end_date=old_end, new_end_date=new_end,
                  note=request.data.get('note'))
        contract.refresh_from_db()
        return Response(self.get_serializer(contract).data)

    @action(detail=True, methods=['post'])
    @transaction.atomic
    def terminate(self, request, pk=None):
        contract = self.get_object()
        if contract.status in (ContractStatus.TERMINATED,):
            return self._bad('Hợp đồng đã kết thúc.')
        raw = request.data.get('terminated_at')
        ended = parse_date(str(raw)) if raw else timezone.localdate()
        if not ended:
            return self._bad('terminated_at phải có định dạng YYYY-MM-DD.')
        contract.status = ContractStatus.TERMINATED
        contract.terminated_at = ended
        contract.termination_reason = request.data.get('reason')
        contract.save()
        self._log(contract, ContractEventType.TERMINATED, old_end_date=contract.end_date,
                  new_end_date=ended, note=contract.termination_reason)
        return Response(self.get_serializer(contract).data)

    @action(detail=True, methods=['get'])
    def history(self, request, pk=None):
        contract = self.get_object()
        return Response(ContractEventSerializer(contract.events.all(), many=True).data)

    @action(detail=False, methods=['get'])
    def summary(self, request):
        queryset = scoped_contracts(request.user)
        today = timezone.localdate()
        active = queryset.filter(status__in=Contract.ACTIVE_STATUSES)
        return Response({
            'total_contracts': queryset.count(),
            'active_contracts': active.filter(end_date__gte=today).count(),
            'overdue_active_contracts': active.filter(end_date__lt=today).count(),
            'expiring_soon_contracts': active.filter(
                end_date__gte=today, end_date__lte=today + timedelta(days=30)).count(),
            'draft_contracts': queryset.filter(status=ContractStatus.DRAFT).count(),
            'terminated_contracts': queryset.filter(status=ContractStatus.TERMINATED).count(),
        })
