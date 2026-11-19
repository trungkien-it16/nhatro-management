from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    PropertyViewSet,
    RoomViewSet,
    MaintenanceRequestViewSet,
    MaintenanceHistoryViewSet,
)

router = DefaultRouter()
router.register(r'properties', PropertyViewSet, basename='property')
router.register(r'rooms', RoomViewSet, basename='room')
router.register(r'maintenance', MaintenanceRequestViewSet, basename='maintenance')
router.register(r'maintenance-history', MaintenanceHistoryViewSet, basename='maintenance-history')

urlpatterns = [
    path('', include(router.urls)),
]
