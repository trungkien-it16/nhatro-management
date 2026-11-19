"""ROOT_URLCONF của service process contract_service."""
from common.service_urls import build_service_urlpatterns

urlpatterns = build_service_urlpatterns('services.contract_service.urls')
