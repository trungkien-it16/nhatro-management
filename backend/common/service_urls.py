from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

from .health import HealthCheckView


def build_service_urlpatterns(api_module, extra=None):
    """
    URL chuẩn cho mỗi service:
        /health/        -> health check (gateway gọi)
        /api/...        -> API nghiệp vụ của service (gateway proxy tới)
        /api/schema/, /api/docs/ -> OpenAPI riêng của service
    """
    patterns = [
        path('health/', HealthCheckView.as_view(), name='health'),
        path('api/schema/', SpectacularAPIView.as_view(), name='schema'),
        path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
        path('api/', include(api_module)),
    ]
    if extra:
        patterns = list(extra) + patterns
    return patterns
