"""SERVICE — Property & Maintenance Service (:8002)."""
from config.common import *  # noqa: F401,F403
from config.common import BASE_INSTALLED_APPS, service_database, spectacular_settings

SERVICE_KEY = 'property'
SERVICE_NAME = 'Property & Maintenance Service'
SERVICE_PORT = 8002

INSTALLED_APPS = [
    *BASE_INSTALLED_APPS,
    'services.property_service',
]

ROOT_URLCONF = 'services.property_service.service_urls'
DATABASES = {'default': service_database(SERVICE_KEY)}
# Service stateless: DB không có bảng auth/contenttypes (xem StatelessServiceRouter).
DATABASE_ROUTERS = ['config.db_router.StatelessServiceRouter']

SPECTACULAR_SETTINGS = spectacular_settings('Property & Maintenance Service API (:8002)', 'Nhà trọ, phòng trọ, bảo trì.')
