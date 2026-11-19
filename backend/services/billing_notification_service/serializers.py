from rest_framework import serializers

from .models import Invoice, InvoiceStatus, Notification


class InvoiceSerializer(serializers.ModelSerializer):
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    notify_user_id = serializers.IntegerField(
        write_only=True, required=False,
        help_text='ID tài khoản (Identity) nhận thông báo hóa đơn mới — tùy chọn.')

    class Meta:
        model = Invoice
        fields = [
            'id', 'invoice_code', 'room_id', 'contract_id', 'tenant_id', 'landlord_id',
            'billing_month', 'billing_year', 'room_fee',
            'electricity_old_num', 'electricity_new_num', 'electricity_unit_price', 'electricity_cost',
            'water_old_num', 'water_new_num', 'water_unit_price', 'water_cost',
            'other_service_cost', 'total_amount',
            'status', 'status_display', 'due_date', 'paid_at', 'notify_user_id',
            'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'landlord_id', 'total_amount', 'status', 'paid_at', 'created_at', 'updated_at']

    def validate_billing_month(self, value):
        if not 1 <= value <= 12:
            raise serializers.ValidationError('Tháng phải trong khoảng 1–12.')
        return value

    def validate(self, attrs):
        for kind in ('electricity', 'water'):
            old = attrs.get(f'{kind}_old_num', getattr(self.instance, f'{kind}_old_num', 0))
            new = attrs.get(f'{kind}_new_num', getattr(self.instance, f'{kind}_new_num', 0))
            if new < old:
                raise serializers.ValidationError({f'{kind}_new_num': 'Chỉ số mới không được nhỏ hơn chỉ số cũ.'})
        if self.instance is not None and self.instance.status in (InvoiceStatus.PAID, InvoiceStatus.CANCELLED):
            raise serializers.ValidationError('Không thể sửa hóa đơn đã thanh toán hoặc đã hủy.')
        return attrs


class NotificationSerializer(serializers.ModelSerializer):
    category_display = serializers.CharField(source='get_category_display', read_only=True)

    class Meta:
        model = Notification
        fields = ['id', 'user_id', 'created_by_id', 'category', 'category_display', 'reference_id',
                  'title', 'content', 'is_read', 'created_at']
        read_only_fields = ['id', 'created_by_id', 'is_read', 'created_at']
