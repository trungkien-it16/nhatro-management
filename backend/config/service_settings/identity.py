"""SERVICE 1 — IDENTITY SERVICE (:8001). Owner: tài khoản, mật khẩu, JWT, role."""
from config.common import *  # noqa: F401,F403
from config.common import BASE_INSTALLED_APPS, MIDDLEWARE as _BASE_MIDDLEWARE, REST_FRAMEWORK as _BASE_RF
from config.common import SIMPLE_JWT as _BASE_JWT, service_database, spectacular_settings

SERVICE_KEY = 'identity'
SERVICE_NAME = 'Identity Service'
SERVICE_PORT = 8001

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.sessions',
    'django.contrib.messages',
    *BASE_INSTALLED_APPS,
    'rest_framework_simplejwt.token_blacklist',
    'services.identity_service',
]

MIDDLEWARE = [
    _BASE_MIDDLEWARE[0],
    'django.contrib.sessions.middleware.SessionMiddleware',
    *_BASE_MIDDLEWARE[1:],
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

ROOT_URLCONF = 'services.identity_service.service_urls'
DATABASES = {'default': service_database(SERVICE_KEY)}

AUTH_USER_MODEL = 'identity_service.User'
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator', 'OPTIONS': {'min_length': 6}},
]

# Identity là service duy nhất được tra cứu bảng User khi xác thực.
REST_FRAMEWORK = {
    **_BASE_RF,
    'DEFAULT_AUTHENTICATION_CLASSES': ('rest_framework_simplejwt.authentication.JWTAuthentication',),
}
SIMPLE_JWT = {**_BASE_JWT, 'BLACKLIST_AFTER_ROTATION': True}

# /api/auth/test-users/ (tài khoản mẫu) chỉ bật khi dev.
import os as _os  # noqa: E402
EXPOSE_TEST_ACCOUNTS = _os.getenv('EXPOSE_TEST_ACCOUNTS', str(DEBUG)).strip().lower() in ('1', 'true', 'yes')  # noqa: F405

SPECTACULAR_SETTINGS = spectacular_settings(
    'Identity Service API (:8001)', 'Đăng ký, đăng nhập, JWT, refresh, logout, đổi mật khẩu, quản lý tài khoản & role.')
