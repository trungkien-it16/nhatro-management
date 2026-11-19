from rest_framework import serializers

from .models import RentalHistory, TenantProfile


class RentalHistorySerializer(serializers.ModelSerializer):
    class Meta:
        model = RentalHistory
        fields = ['id', 'tenant', 'room_id', 'contract_id', 'move_in_date', 'move_out_date', 'note', 'created_at']
        read_only_fields = ['id', 'tenant', 'created_at']

    def validate(self, attrs):
        move_in = attrs.get('move_in_date', getattr(self.instance, 'move_in_date', None))
        move_out = attrs.get('move_out_date', getattr(self.instance, 'move_out_date', None))
        if move_in and move_out and move_out < move_in:
            raise serializers.ValidationError({'move_out_date': 'Ngày chuyển đi phải sau ngày vào ở.'})
        return attrs


class TenantProfileSerializer(serializers.ModelSerializer):
    status_display = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model = TenantProfile
        fields = [
            'id', 'user_id', 'landlord_id', 'room_id',
            'full_name', 'phone_number', 'email', 'identity_card', 'permanent_address',
            'birth_date', 'gender', 'hometown', 'occupation',
            'emergency_contact_name', 'emergency_contact_phone', 'temporary_residence_registered',
            'status', 'status_display', 'notes', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'landlord_id', 'created_at', 'updated_at']

    def validate_full_name(self, value):
        if not value or not value.strip():
            raise serializers.ValidationError('Họ tên không được để trống.')
        return value.strip()
