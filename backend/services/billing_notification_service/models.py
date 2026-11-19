from decimal import Decimal

from django.db import models

class InvoiceStatus(models.TextChoices):
    UNPAID = 'UNPAID', 'Chưa thanh toán'
    PAID = 'PAID', 'Đã thanh toán'
    OVERDUE = 'OVERDUE', 'Quá hạn'
    CANCELLED = 'CANCELLED', 'Đã hủy'


class Invoice(models.Model):
    """
    SERVICE 5 — BILLING SERVICE: Hóa đơn tiền phòng, điện, nước, dịch vụ; công nợ.
    Kiến trúc SOA: chỉ tham chiếu ID — room_id (Property), contract_id (Contract),
    tenant_id (Tenant), landlord_id (Identity).
    """
    invoice_code = models.CharField(max_length=50, unique=True, blank=True, verbose_name='Mã hóa đơn')
    room_id = models.IntegerField(db_index=True, verbose_name='ID Phòng (Property Service)')
    contract_id = models.IntegerField(null=True, blank=True, verbose_name='ID Hợp đồng (Contract Service)')
    tenant_id = models.IntegerField(null=True, blank=True, db_index=True, verbose_name='ID Người thuê (Tenant Service)')
    landlord_id = models.IntegerField(null=True, blank=True, db_index=True, verbose_name='ID Chủ trọ (Identity Service)')
    billing_month = models.PositiveIntegerField(verbose_name='Tháng')
    billing_year = models.PositiveIntegerField(verbose_name='Năm')

    room_fee = models.DecimalField(max_digits=12, decimal_places=2, verbose_name='Tiền phòng')
    electricity_old_num = models.FloatField(default=0.0, verbose_name='Chỉ số điện cũ')
    electricity_new_num = models.FloatField(default=0.0, verbose_name='Chỉ số điện mới')
    electricity_unit_price = models.DecimalField(max_digits=12, decimal_places=2, default=0, verbose_name='Đơn giá điện')
    electricity_cost = models.DecimalField(max_digits=12, decimal_places=2, default=0.0, verbose_name='Tiền điện')

    water_old_num = models.FloatField(default=0.0, verbose_name='Chỉ số nước cũ')
    water_new_num = models.FloatField(default=0.0, verbose_name='Chỉ số nước mới')
    water_unit_price = models.DecimalField(max_digits=12, decimal_places=2, default=0, verbose_name='Đơn giá nước')
    water_cost = models.DecimalField(max_digits=12, decimal_places=2, default=0.0, verbose_name='Tiền nước')

    other_service_cost = models.DecimalField(max_digits=12, decimal_places=2, default=0.0, verbose_name='Phí dịch vụ khác')
    total_amount = models.DecimalField(max_digits=12, decimal_places=2, verbose_name='Tổng cộng phải thanh toán')

    status = models.CharField(
        max_length=20,
        choices=InvoiceStatus.choices,
        default=InvoiceStatus.UNPAID,
        verbose_name='Trạng thái thanh toán'
    )
    due_date = models.DateField(verbose_name='Hạn thanh toán')
    paid_at = models.DateTimeField(null=True, blank=True, verbose_name='Thời điểm thanh toán')

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Hóa đơn dịch vụ'
        verbose_name_plural = 'Danh sách Hóa đơn dịch vụ'
        ordering = ['-created_at']

    def calculate(self):
        """Tính tiền điện/nước theo chỉ số (nếu có đơn giá) và tổng tiền."""
        if self.electricity_unit_price:
            used = max(Decimal(str(self.electricity_new_num)) - Decimal(str(self.electricity_old_num)), Decimal(0))
            self.electricity_cost = used * Decimal(self.electricity_unit_price)
        if self.water_unit_price:
            used = max(Decimal(str(self.water_new_num)) - Decimal(str(self.water_old_num)), Decimal(0))
            self.water_cost = used * Decimal(self.water_unit_price)
        self.total_amount = (Decimal(self.room_fee or 0) + Decimal(self.electricity_cost or 0)
                             + Decimal(self.water_cost or 0) + Decimal(self.other_service_cost or 0))

    def __str__(self):
        return f"Hóa đơn {self.invoice_code} - Phòng ID #{self.room_id} (T{self.billing_month}/{self.billing_year})"


class NotificationCategory(models.TextChoices):
    INVOICE = 'INVOICE', 'Hóa đơn'
    CONTRACT = 'CONTRACT', 'Hợp đồng'
    MAINTENANCE = 'MAINTENANCE', 'Bảo trì'
    SYSTEM = 'SYSTEM', 'Hệ thống'


class Notification(models.Model):
    """
    SERVICE 5 — NOTIFICATION SERVICE
    Hệ thống thông báo gửi tới người dùng.
    Kiến trúc SOA: Loose coupling lưu user_id.
    """
    user_id = models.IntegerField(db_index=True, verbose_name='ID Người nhận (Identity Service)')
    created_by_id = models.IntegerField(null=True, blank=True, verbose_name='ID Người gửi (Identity Service)')
    category = models.CharField(max_length=20, choices=NotificationCategory.choices,
                                default=NotificationCategory.SYSTEM, verbose_name='Loại thông báo')
    reference_id = models.IntegerField(null=True, blank=True,
                                       verbose_name='ID đối tượng liên quan (hóa đơn/hợp đồng/bảo trì)')
    title = models.CharField(max_length=200, verbose_name='Tiêu đề thông báo')
    content = models.TextField(verbose_name='Nội dung thông báo')
    is_read = models.BooleanField(default=False, verbose_name='Đã xem')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Thông báo'
        verbose_name_plural = 'Danh sách Thông báo'
        ordering = ['-created_at']

    def __str__(self):
        return f"Thông báo: {self.title} -> User ID #{self.user_id}"
