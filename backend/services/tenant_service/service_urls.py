"""ROOT_URLCONF của service process tenant_service."""
from common.service_urls import build_service_urlpatterns

urlpatterns = build_service_urlpatterns('services.tenant_service.urls')
