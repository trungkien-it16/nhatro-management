"""ROOT_URLCONF của Identity Service process (:8001)."""
from django.contrib import admin
from django.urls import path

from common.service_urls import build_service_urlpatterns

urlpatterns = build_service_urlpatterns(
    'services.identity_service.urls',
    extra=[path('admin/', admin.site.urls)],
)
