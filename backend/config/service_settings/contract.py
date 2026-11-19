"""SERVICE — Contract Service (:8004)."""
from config.common import *  # noqa: F401,F403
from config.common import BASE_INSTALLED_APPS, service_database, spectacular_settings

SERVICE_KEY = 'contract'
SERVICE_NAME = 'Contract Service'
SERVICE_PORT = 8004

INSTALLED_APPS = [
    *BASE_INSTALLED_APPS,
    'services.contract_service',
]

ROOT_URLCONF = 'services.contract_service.service_urls'
DATABASES = {'default': service_database(SERVICE_KEY)}
# Service stateless: DB không có bảng auth/contenttypes (xem StatelessServiceRouter).
DATABASE_ROUTERS = ['config.db_router.StatelessServiceRouter']

SPECTACULAR_SETTINGS = spectacular_settings('Contract Service API (:8004)', 'Hợp đồng thuê: tạo, gia hạn, kết thúc, lịch sử.')
