from django.db import models


class TenantStatus(models.TextChoices):
    ACTIVE = 'ACTIVE', 'Đang thuê'
    INACTIVE = 'INACTIVE', 'Chưa thuê / Tạm ngưng'
    MOVED_OUT = 'MOVED_OUT', 'Đã chuyển đi'


class TenantProfile(models.Model):
    """
    SERVICE 3 — TENANT SERVICE: Hồ sơ người thuê.
    Owner của dữ liệu: thông tin cá nhân, liên hệ, lịch sử thuê.
    KHÔNG lưu mật khẩu / thông tin đăng nhập (thuộc Identity Service).
    Liên kết chéo service bằng ID: user_id (Identity, tùy chọn), landlord_id (Identity),
    room_id (Property). Không dùng Foreign Key chéo service.
    """
    user_id = models.IntegerField(null=True, blank=True, db_index=True,
                                  verbose_name='ID Tài khoản (Identity Service) — tùy chọn')
    landlord_id = models.IntegerField(null=True, blank=True, db_index=True,
                                      verbose_name='ID Chủ trọ quản lý (Identity Service)')
    room_id = models.IntegerField(null=True, blank=True, db_index=True,
                                  verbose_name='ID Phòng hiện tại (Property Service)')

    full_name = models.CharField(max_length=150, default='', verbose_name='Họ tên')
    phone_number = models.CharField(max_length=20, blank=True, null=True, verbose_name='Số điện thoại')
    email = models.EmailField(blank=True, null=True, verbose_name='Email')
    identity_card = models.CharField(max_length=20, blank=True, null=True, verbose_name='Số CCCD / CMND')
    permanent_address = models.CharField(max_length=255, blank=True, null=True, verbose_name='Địa chỉ thường trú')

    birth_date = models.DateField(null=True, blank=True, verbose_name='Ngày sinh')
    gender = models.CharField(max_length=10, blank=True, null=True, verbose_name='Giới tính')
    hometown = models.CharField(max_length=150, blank=True, null=True, verbose_name='Quê quán')
    occupation = models.CharField(max_length=150, blank=True, null=True, verbose_name='Nghề nghiệp / Đơn vị công tác')
    emergency_contact_name = models.CharField(max_length=100, blank=True, null=True, verbose_name='Người liên hệ khẩn cấp')
    emergency_contact_phone = models.CharField(max_length=20, blank=True, null=True, verbose_name='SĐT khẩn cấp')
    temporary_residence_registered = models.BooleanField(default=False, verbose_name='Đã đăng ký tạm trú')

    status = models.CharField(max_length=20, choices=TenantStatus.choices, default=TenantStatus.INACTIVE,
                              verbose_name='Trạng thái thuê')
    notes = models.TextField(blank=True, null=True, verbose_name='Ghi chú')

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Hồ sơ người thuê'
        verbose_name_plural = 'Danh sách Hồ sơ người thuê'
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.full_name or 'Người thuê'} (#{self.pk})"


class RentalHistory(models.Model):
    """Lịch sử thuê của một người thuê (nội bộ Tenant Service)."""
    tenant = models.ForeignKey(TenantProfile, on_delete=models.CASCADE, related_name='rental_history')
    room_id = models.IntegerField(verbose_name='ID Phòng (Property Service)')
    contract_id = models.IntegerField(null=True, blank=True, verbose_name='ID Hợp đồng (Contract Service)')
    move_in_date = models.DateField(verbose_name='Ngày vào ở')
    move_out_date = models.DateField(null=True, blank=True, verbose_name='Ngày chuyển đi')
    note = models.CharField(max_length=255, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Lịch sử thuê'
        verbose_name_plural = 'Lịch sử thuê'
        ordering = ['-move_in_date', '-id']

    def __str__(self):
        return f"Tenant #{self.tenant_id} - Phòng #{self.room_id} từ {self.move_in_date}"
