from django.contrib import admin
from .models import Property, Room, MaintenanceRequest, MaintenanceHistory


@admin.register(Property)
class PropertyAdmin(admin.ModelAdmin):
    list_display = ('code', 'name', 'owner_id', 'district', 'ward', 'status', 'total_floors', 'created_at')
    search_fields = ('code', 'name', 'address', 'ward', 'district', 'city')
    list_filter = ('status', 'city', 'district')


@admin.register(Room)
class RoomAdmin(admin.ModelAdmin):
    list_display = ('code', 'room_number', 'property', 'floor', 'rent_price', 'area', 'max_occupants',
                    'current_occupants', 'status')
    list_filter = ('status', 'room_type', 'property', 'floor')
    search_fields = ('code', 'room_number', 'property__name', 'tenant_name')


@admin.register(MaintenanceRequest)
class MaintenanceRequestAdmin(admin.ModelAdmin):
    list_display = ('code', 'title', 'room', 'priority', 'status', 'reported_by_id', 'estimated_cost',
                    'actual_cost', 'requested_date', 'completed_date')
    list_filter = ('status', 'priority')
    search_fields = ('code', 'title', 'room__room_number', 'room__code')


@admin.register(MaintenanceHistory)
class MaintenanceHistoryAdmin(admin.ModelAdmin):
    list_display = ('maintenance_request', 'room', 'action', 'previous_status', 'new_status', 'cost',
                    'performed_by', 'repair_date')
    list_filter = ('new_status',)
