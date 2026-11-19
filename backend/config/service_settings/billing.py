"""SERVICE — Billing & Notification Service (:8005)."""
from config.common import *  # noqa: F401,F403
from config.common import BASE_INSTALLED_APPS, service_database, spectacular_settings

SERVICE_KEY = 'billing'
SERVICE_NAME = 'Billing & Notification Service'
SERVICE_PORT = 8005

INSTALLED_APPS = [
    *BASE_INSTALLED_APPS,
    'services.billing_notification_service',
]

ROOT_URLCONF = 'services.billing_notification_service.service_urls'
DATABASES = {'default': service_database(SERVICE_KEY)}
# Service stateless: DB không có bảng auth/contenttypes (xem StatelessServiceRouter).
DATABASE_ROUTERS = ['config.db_router.StatelessServiceRouter']

SPECTACULAR_SETTINGS = spectacular_settings('Billing & Notification Service API (:8005)', 'Hóa đơn, công nợ, thông báo.')
