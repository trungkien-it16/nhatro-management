"""SERVICE — Tenant Service (:8003)."""
from config.common import *  # noqa: F401,F403
from config.common import BASE_INSTALLED_APPS, service_database, spectacular_settings

SERVICE_KEY = 'tenant'
SERVICE_NAME = 'Tenant Service'
SERVICE_PORT = 8003

INSTALLED_APPS = [
    *BASE_INSTALLED_APPS,
    'services.tenant_service',
]

ROOT_URLCONF = 'services.tenant_service.service_urls'
DATABASES = {'default': service_database(SERVICE_KEY)}
# Service stateless: DB không có bảng auth/contenttypes (xem StatelessServiceRouter).
DATABASE_ROUTERS = ['config.db_router.StatelessServiceRouter']

SPECTACULAR_SETTINGS = spectacular_settings('Tenant Service API (:8003)', 'Hồ sơ người thuê, liên hệ, lịch sử thuê.')
