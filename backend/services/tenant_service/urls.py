from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import TenantProfileViewSet

router = DefaultRouter()
router.register(r'tenants', TenantProfileViewSet, basename='tenant')

urlpatterns = [
    path('', include(router.urls)),
]
