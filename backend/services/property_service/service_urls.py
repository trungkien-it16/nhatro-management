"""ROOT_URLCONF của Property & Maintenance Service process (:8002)."""
from common.service_urls import build_service_urlpatterns

urlpatterns = build_service_urlpatterns('services.property_service.urls')
