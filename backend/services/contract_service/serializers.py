from rest_framework import serializers

from .models import Contract, ContractEvent, ContractStatus


class ContractEventSerializer(serializers.ModelSerializer):
    event_type_display = serializers.CharField(source='get_event_type_display', read_only=True)

    class Meta:
        model = ContractEvent
        fields = ['id', 'event_type', 'event_type_display', 'actor_id', 'old_end_date', 'new_end_date',
                  'note', 'created_at']


class ContractSerializer(serializers.ModelSerializer):
    status_display = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model = Contract
        fields = [
            'id', 'contract_number', 'room_id', 'tenant_id', 'landlord_id',
            'start_date', 'end_date', 'rental_price', 'deposit_amount', 'billing_day_of_month',
            'status', 'status_display', 'terminated_at', 'termination_reason',
            'terms_and_conditions', 'contract_file_url', 'created_at', 'updated_at',
        ]
        # Trạng thái chỉ thay đổi qua action (activate / extend / terminate).
        read_only_fields = ['id', 'landlord_id', 'terminated_at', 'termination_reason',
                            'created_at', 'updated_at']

    def validate_status(self, value):
        if self.instance is not None and value != self.instance.status:
            raise serializers.ValidationError('Dùng các action activate/extend/terminate để đổi trạng thái.')
        if self.instance is None and value not in (ContractStatus.DRAFT, ContractStatus.ACTIVE):
            raise serializers.ValidationError('Hợp đồng mới chỉ có thể là DRAFT hoặc ACTIVE.')
        return value

    def validate_billing_day_of_month(self, value):
        if not 1 <= value <= 28:
            raise serializers.ValidationError('Ngày thu tiền phải trong khoảng 1–28.')
        return value

    def validate(self, attrs):
        start = attrs.get('start_date', getattr(self.instance, 'start_date', None))
        end = attrs.get('end_date', getattr(self.instance, 'end_date', None))
        if start and end and end <= start:
            raise serializers.ValidationError({'end_date': 'Ngày kết thúc phải sau ngày bắt đầu.'})

        status_value = attrs.get('status', getattr(self.instance, 'status', ContractStatus.ACTIVE))
        room_id = attrs.get('room_id', getattr(self.instance, 'room_id', None))
        if status_value in Contract.ACTIVE_STATUSES and room_id is not None:
            clash = Contract.objects.filter(room_id=room_id, status__in=Contract.ACTIVE_STATUSES)
            if self.instance is not None:
                clash = clash.exclude(pk=self.instance.pk)
            if clash.exists():
                raise serializers.ValidationError({'room_id': 'Phòng này đang có hợp đồng hiệu lực.'})
        return attrs
