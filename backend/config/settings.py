"""
TOOLBOX SETTINGS (không dùng để chạy runtime).

Runtime SOA: mỗi service chạy 1 process riêng với `config.service_settings.<service>`
và API Gateway chạy ở `backend/api_gateway` (xem run_all_services.py).

File này nạp cả 5 app + 5 database (định tuyến bằng ServiceDatabaseRouter) chỉ để
phục vụ các tác vụ quản trị/dev:
  - python seed_data.py                         (nạp dữ liệu mẫu vào DB của từng service)
  - python manage.py migrate --database=<alias> (migrate thủ công từng DB)
  - Django admin tổng hợp khi debug
"""
from config.common import *  # noqa: F401,F403
from config.common import BASE_INSTALLED_APPS, REST_FRAMEWORK as _BASE_RF, SIMPLE_JWT as _BASE_JWT, service_database

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.sessions',
    'django.contrib.messages',
    *BASE_INSTALLED_APPS,
    'rest_framework_simplejwt.token_blacklist',

    # SOA Services (mỗi service là 1 bounded context, 1 database riêng)
    'services.identity_service',
    'services.property_service',
    'services.tenant_service',
    'services.contract_service',
    'services.billing_notification_service',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]
TEMPLATES = [{
    'BACKEND': 'django.template.backends.django.DjangoTemplates',
    'DIRS': [],
    'APP_DIRS': True,
    'OPTIONS': {'context_processors': [
        'django.template.context_processors.debug',
        'django.template.context_processors.request',
        'django.contrib.auth.context_processors.auth',
        'django.contrib.messages.context_processors.messages',
    ]},
}]

ROOT_URLCONF = 'config.urls'
WSGI_APPLICATION = 'config.wsgi.application'

DATABASES = {
    'default': service_database('identity'),
    'property_db': service_database('property'),
    'tenant_db': service_database('tenant'),
    'contract_db': service_database('contract'),
    'billing_db': service_database('billing'),
}
DATABASE_ROUTERS = ['config.db_router.ServiceDatabaseRouter']

AUTH_USER_MODEL = 'identity_service.User'

REST_FRAMEWORK = {
    **_BASE_RF,
    'DEFAULT_AUTHENTICATION_CLASSES': ('rest_framework_simplejwt.authentication.JWTAuthentication',),
}
SIMPLE_JWT = {**_BASE_JWT, 'BLACKLIST_AFTER_ROTATION': True}
