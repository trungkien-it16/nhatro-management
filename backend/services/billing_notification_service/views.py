from django.db import transaction
from django.db.models import Count, Q, Sum
from django.utils import timezone
from django.utils.crypto import get_random_string
from rest_framework import permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from common.auth import IsManagerRole, get_user_id, is_admin, is_landlord, is_manager
from common.service_client import own_tenant_ids
from common.sprint import SprintFeatureLock
from .models import Invoice, InvoiceStatus, Notification, NotificationCategory
from .serializers import InvoiceSerializer, NotificationSerializer

UNPAID_STATUSES = (InvoiceStatus.UNPAID, InvoiceStatus.OVERDUE)


def scoped_invoices(user):
    """
    - ADMIN         : toàn bộ
    - LANDLORD      : hóa đơn do mình lập (landlord_id = user_id trong JWT)
    - TENANT (và STAFF legacy): hóa đơn có tenant_id thuộc hồ sơ người thuê gắn với user_id của mình
      (tra qua Tenant Service /api/tenants/links/; lỗi -> 503, không trả dữ liệu).
    """
    queryset = Invoice.objects.all()
    if is_admin(user):
        return queryset
    if is_landlord(user):
        return queryset.filter(landlord_id=get_user_id(user))
    return queryset.filter(tenant_id__in=own_tenant_ids(user))


def notify(user_id, title, content, category=NotificationCategory.SYSTEM, reference_id=None, created_by_id=None):
    return Notification.objects.create(user_id=user_id, title=title, content=content, category=category,
                                       reference_id=reference_id, created_by_id=created_by_id)


class InvoiceViewSet(viewsets.ModelViewSet):
    """
    SERVICE 5 — BILLING
    - CRUD hóa đơn (tự tính tiền điện/nước theo chỉ số × đơn giá, tự tính tổng)
    - Lọc: ?status= (UNPAID/PAID/OVERDUE/CANCELLED/DEBT), ?room_id=, ?tenant_id=, ?contract_id=, ?month=&year=
    - GET  /debt/         công nợ theo phòng
    - GET  /summary/      thống kê (Dashboard qua Gateway)
    Tạm khóa (D3 — nghiệp vụ Sprint sau, source code giữ nguyên):
    - POST/PUT/PATCH/DELETE hóa đơn (tạo/tính tiền), POST /{id}/pay/, POST /{id}/cancel/
    """
    serializer_class = InvoiceSerializer
    sprint_locked_actions = ('create', 'update', 'partial_update', 'destroy', 'pay', 'cancel')
    READ_ACTIONS = ('list', 'retrieve', 'debt', 'summary')

    def get_permissions(self):
        if self.action in self.READ_ACTIONS:
            return [permissions.IsAuthenticated(), SprintFeatureLock()]
        return [permissions.IsAuthenticated(), IsManagerRole(), SprintFeatureLock()]

    def get_queryset(self):
        queryset = scoped_invoices(self.request.user)
        params = self.request.query_params
        st = params.get('status')
        if st == 'DEBT':
            queryset = queryset.filter(status__in=UNPAID_STATUSES)
        elif st and st != 'ALL':
            queryset = queryset.filter(status=st)
        for field in ('room_id', 'tenant_id', 'contract_id'):
            if params.get(field):
                queryset = queryset.filter(**{field: params[field]})
        if params.get('month'):
            queryset = queryset.filter(billing_month=params['month'])
        if params.get('year'):
            queryset = queryset.filter(billing_year=params['year'])
        return queryset

    @staticmethod
    def _mark_overdue(queryset):
        """Hóa đơn UNPAID đã quá hạn -> OVERDUE (trạng thái thanh toán thực tế)."""
        queryset.filter(status=InvoiceStatus.UNPAID, due_date__lt=timezone.localdate()).update(
            status=InvoiceStatus.OVERDUE, updated_at=timezone.now())

    def list(self, request, *args, **kwargs):
        self._mark_overdue(scoped_invoices(request.user))
        return super().list(request, *args, **kwargs)

    @transaction.atomic
    def perform_create(self, serializer):
        notify_user_id = serializer.validated_data.pop('notify_user_id', None)
        code = serializer.validated_data.pop('invoice_code', None) or \
            f"HDN{timezone.now():%Y%m}-{get_random_string(6, '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ')}"
        invoice = Invoice(**serializer.validated_data, invoice_code=code, landlord_id=get_user_id(self.request.user))
        invoice.calculate()
        invoice.save()
        serializer.instance = invoice
        if notify_user_id:
            notify(notify_user_id, f'Hóa đơn tháng {invoice.billing_month}/{invoice.billing_year}',
                   f'Hóa đơn {invoice.invoice_code}: {invoice.total_amount:,.0f} VNĐ, hạn {invoice.due_date:%d/%m/%Y}.',
                   NotificationCategory.INVOICE, invoice.id, get_user_id(self.request.user))

    def perform_update(self, serializer):
        serializer.validated_data.pop('notify_user_id', None)
        invoice = serializer.save()
        invoice.calculate()
        invoice.save()

    @action(detail=True, methods=['post'])
    def pay(self, request, pk=None):
        invoice = self.get_object()
        if invoice.status not in UNPAID_STATUSES:
            return Response({'error': 'Hóa đơn không ở trạng thái chưa thanh toán.'}, status=status.HTTP_400_BAD_REQUEST)
        invoice.status = InvoiceStatus.PAID
        invoice.paid_at = timezone.now()
        invoice.save(update_fields=['status', 'paid_at', 'updated_at'])
        return Response(self.get_serializer(invoice).data)

    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        invoice = self.get_object()
        if invoice.status == InvoiceStatus.PAID:
            return Response({'error': 'Không thể hủy hóa đơn đã thanh toán.'}, status=status.HTTP_400_BAD_REQUEST)
        invoice.status = InvoiceStatus.CANCELLED
        invoice.save(update_fields=['status', 'updated_at'])
        return Response(self.get_serializer(invoice).data)

    @action(detail=False, methods=['get'])
    def debt(self, request):
        queryset = scoped_invoices(request.user)
        self._mark_overdue(queryset)
        rows = (queryset.filter(status__in=UNPAID_STATUSES)
                .values('room_id', 'tenant_id')
                .annotate(invoice_count=Count('id'), total_debt=Sum('total_amount'))
                .order_by('room_id'))
        return Response(list(rows))

    @action(detail=False, methods=['get'])
    def summary(self, request):
        queryset = scoped_invoices(request.user)
        self._mark_overdue(queryset)
        unpaid = queryset.filter(status__in=UNPAID_STATUSES)
        return Response({
            'total_invoices': queryset.count(),
            'unpaid_invoices': unpaid.count(),
            'overdue_invoices': queryset.filter(status=InvoiceStatus.OVERDUE).count(),
            'paid_invoices': queryset.filter(status=InvoiceStatus.PAID).count(),
            'unpaid_amount': str(unpaid.aggregate(s=Sum('total_amount'))['s'] or 0),
        })


class NotificationViewSet(viewsets.ModelViewSet):
    """
    SERVICE 5 — NOTIFICATION
    - GET  /notifications/              thông báo của tôi (?unread=1, ?category=); ?sent=1: thông báo tôi đã gửi
    - POST /notifications/{id}/read/    đánh dấu đã đọc (thông báo của mình)
    - POST /notifications/read-all/     đánh dấu tất cả đã đọc
    - DELETE /notifications/{id}/       xóa (ADMIN/LANDLORD, trong phạm vi)
    Tạm khóa (D3): POST /notifications/ (gửi thông báo) — nghiệp vụ Sprint sau.
    """
    serializer_class = NotificationSerializer
    http_method_names = ['get', 'post', 'delete', 'head', 'options']
    sprint_locked_actions = ('create',)

    def get_permissions(self):
        if self.action in ('create', 'destroy'):
            return [permissions.IsAuthenticated(), IsManagerRole(), SprintFeatureLock()]
        return [permissions.IsAuthenticated(), SprintFeatureLock()]

    def get_queryset(self):
        user = self.request.user
        uid = get_user_id(user)
        params = self.request.query_params
        if params.get('sent') == '1' and is_manager(user):
            queryset = Notification.objects.filter(created_by_id=uid)
        elif self.action == 'destroy':
            queryset = Notification.objects.all() if is_admin(user) else \
                Notification.objects.filter(Q(created_by_id=uid) | Q(user_id=uid))
        else:
            queryset = Notification.objects.filter(user_id=uid)
        if params.get('unread') == '1':
            queryset = queryset.filter(is_read=False)
        if params.get('category'):
            queryset = queryset.filter(category=params['category'])
        return queryset

    def perform_create(self, serializer):
        serializer.save(created_by_id=get_user_id(self.request.user))

    @action(detail=True, methods=['post'])
    def read(self, request, pk=None):
        notification = self.get_object()
        if not notification.is_read:
            notification.is_read = True
            notification.save(update_fields=['is_read'])
        return Response(self.get_serializer(notification).data)

    @action(detail=False, methods=['post'], url_path='read-all')
    def read_all(self, request):
        updated = Notification.objects.filter(user_id=get_user_id(request.user), is_read=False).update(is_read=True)
        return Response({'updated': updated})
