from django.db import models

class ContractStatus(models.TextChoices):
    DRAFT = 'DRAFT', 'Bản nháp'
    ACTIVE = 'ACTIVE', 'Đang hiệu lực'
    EXTENDED = 'EXTENDED', 'Đã gia hạn'
    EXPIRED = 'EXPIRED', 'Đã hết hạn'
    TERMINATED = 'TERMINATED', 'Đã kết thúc / Chấm dứt'


class Contract(models.Model):
    """
    SERVICE 4 — CONTRACT SERVICE: Hợp đồng thuê trọ.
    Kiến trúc SOA: chỉ tham chiếu bằng ID — room_id (Property Service),
    tenant_id (Tenant Service), landlord_id (Identity Service).
    Không sao chép business logic của Room/Tenant sang đây.
    """
    contract_number = models.CharField(max_length=50, unique=True, blank=True, verbose_name='Mã hợp đồng')
    room_id = models.IntegerField(db_index=True, verbose_name='ID Phòng (Property Service)')
    landlord_id = models.IntegerField(db_index=True, verbose_name='ID Chủ trọ (Identity Service)')
    tenant_id = models.IntegerField(db_index=True, verbose_name='ID Người thuê (Tenant Service)')

    start_date = models.DateField(verbose_name='Ngày bắt đầu thuê')
    end_date = models.DateField(verbose_name='Ngày kết thúc hợp đồng')

    rental_price = models.DecimalField(max_digits=12, decimal_places=2, verbose_name='Giá thuê hàng tháng (VNĐ)')
    deposit_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0.0, verbose_name='Tiền cọc giữ chỗ (VNĐ)')
    billing_day_of_month = models.PositiveIntegerField(default=5, verbose_name='Ngày thu tiền hàng tháng')

    status = models.CharField(
        max_length=20,
        choices=ContractStatus.choices,
        default=ContractStatus.ACTIVE,
        verbose_name='Trạng thái hợp đồng'
    )
    terminated_at = models.DateField(null=True, blank=True, verbose_name='Ngày kết thúc thực tế')
    termination_reason = models.CharField(max_length=255, blank=True, null=True, verbose_name='Lý do kết thúc')
    terms_and_conditions = models.TextField(blank=True, null=True, verbose_name='Điều khoản hợp đồng')
    contract_file_url = models.URLField(blank=True, null=True, verbose_name='File hợp đồng scan/PDF')

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Hợp đồng thuê'
        verbose_name_plural = 'Danh sách Hợp đồng thuê'
        ordering = ['-created_at']

    ACTIVE_STATUSES = (ContractStatus.ACTIVE, ContractStatus.EXTENDED)

    @property
    def is_active(self):
        return self.status in self.ACTIVE_STATUSES

    def __str__(self):
        return f"HĐ {self.contract_number} (Phòng ID #{self.room_id})"


class ContractEventType(models.TextChoices):
    CREATED = 'CREATED', 'Tạo hợp đồng'
    ACTIVATED = 'ACTIVATED', 'Kích hoạt'
    UPDATED = 'UPDATED', 'Cập nhật'
    EXTENDED = 'EXTENDED', 'Gia hạn'
    TERMINATED = 'TERMINATED', 'Kết thúc'


class ContractEvent(models.Model):
    """Lịch sử thay đổi của hợp đồng (audit trail nội bộ Contract Service)."""
    contract = models.ForeignKey(Contract, on_delete=models.CASCADE, related_name='events')
    event_type = models.CharField(max_length=20, choices=ContractEventType.choices)
    actor_id = models.IntegerField(null=True, blank=True, verbose_name='ID Người thực hiện (Identity Service)')
    old_end_date = models.DateField(null=True, blank=True)
    new_end_date = models.DateField(null=True, blank=True)
    note = models.CharField(max_length=255, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']
        verbose_name = 'Lịch sử hợp đồng'
        verbose_name_plural = 'Lịch sử hợp đồng'

    def __str__(self):
        return f"{self.get_event_type_display()} - HĐ #{self.contract_id}"
