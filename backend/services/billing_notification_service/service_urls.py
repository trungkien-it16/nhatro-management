"""ROOT_URLCONF của service process billing_notification_service."""
from common.service_urls import build_service_urlpatterns

urlpatterns = build_service_urlpatterns('services.billing_notification_service.urls')
