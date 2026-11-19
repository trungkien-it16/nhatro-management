from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import InvoiceViewSet, NotificationViewSet

router = DefaultRouter()
router.register(r'billing/invoices', InvoiceViewSet, basename='invoice')
router.register(r'notifications', NotificationViewSet, basename='notification')

urlpatterns = [
    path('', include(router.urls)),
]
