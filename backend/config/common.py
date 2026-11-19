"""
Cấu hình DÙNG CHUNG cho mọi service trong hệ thống SOA.

File này chỉ chứa hạ tầng (security, DRF, JWT, i18n, cách dựng cấu hình DB).
Nó KHÔNG khai báo app nghiệp vụ nào — mỗi service tự chọn app/DB/URL của mình
trong `config/service_settings/<service>.py`.
"""
import os
from datetime import timedelta
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent

load_dotenv(BASE_DIR / '.env')

# Mặc định DEBUG=False (an toàn cho production). Khi phát triển đặt DEBUG=True trong backend/.env.
DEBUG = os.getenv('DEBUG', 'False').strip().lower() in ('1', 'true', 'yes')

SECRET_KEY = os.getenv('SECRET_KEY', '')
if not SECRET_KEY:
    if not DEBUG:
        from django.core.exceptions import ImproperlyConfigured
        raise ImproperlyConfigured('Thiếu SECRET_KEY: đặt biến môi trường SECRET_KEY (xem backend/.env.example).')
    SECRET_KEY = 'dev-only-insecure-secret-key-do-not-use-in-production'

_hosts = os.getenv('ALLOWED_HOSTS', '').strip()
ALLOWED_HOSTS = [h.strip() for h in _hosts.split(',') if h.strip()] if _hosts else (
    ['*'] if DEBUG else ['127.0.0.1', 'localhost'])

# Khóa ký JWT dùng chung: Identity Service ký token, các service khác chỉ xác minh
# chữ ký (stateless) mà không cần truy cập database của Identity Service.
JWT_SIGNING_KEY = os.getenv('JWT_SIGNING_KEY', SECRET_KEY)

# ==============================================================================
# DATABASE PER SERVICE
# ==============================================================================
DB_ENGINE = os.getenv('DB_ENGINE', 'mssql').lower()

# service key -> (biến môi trường tên DB SQL Server, tên DB mặc định, file SQLite)
SERVICE_DATABASES = {
    'identity': ('DB_NAME_IDENTITY', 'nhatro_identity_db', 'db_identity.sqlite3'),
    'property': ('DB_NAME_PROPERTY', 'nhatro_property_db', 'db_property.sqlite3'),
    'tenant': ('DB_NAME_TENANT', 'nhatro_tenant_db', 'db_tenant.sqlite3'),
    'contract': ('DB_NAME_CONTRACT', 'nhatro_contract_db', 'db_contract.sqlite3'),
    'billing': ('DB_NAME_BILLING', 'nhatro_billing_db', 'db_billing.sqlite3'),
}


def service_database(service_key):
    """Trả về cấu hình database (SQL Server hoặc SQLite) của một service."""
    env_name, default_name, sqlite_file = SERVICE_DATABASES[service_key]
    if DB_ENGINE == 'mssql':
        db_trusted = os.getenv('DB_TRUSTED_CONNECTION', 'yes').lower() == 'yes'
        extra_params = 'TrustServerCertificate=yes;'
        if db_trusted:
            extra_params += 'Trusted_Connection=yes;'
        return {
            'ENGINE': 'mssql',
            'NAME': os.getenv(env_name, default_name),
            'HOST': os.getenv('DB_SERVER', r'.\SQLEXPRESS'),
            'PORT': os.getenv('DB_PORT', ''),
            'USER': os.getenv('DB_USER', ''),
            'PASSWORD': os.getenv('DB_PASSWORD', ''),
            'OPTIONS': {
                'driver': os.getenv('DB_DRIVER', 'ODBC Driver 17 for SQL Server'),
                'extra_params': extra_params,
            },
        }
    # SQLITE_DIR cho phép đặt file SQLite ở thư mục khác (vd. môi trường test/CI).
    sqlite_dir = Path(os.getenv('SQLITE_DIR', str(BASE_DIR)))
    return {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': sqlite_dir / sqlite_file,
    }


# ==============================================================================
# DJANGO CORE
# ==============================================================================
BASE_INSTALLED_APPS = [
    'django.contrib.contenttypes',
    'django.contrib.auth',
    'django.contrib.staticfiles',
    'rest_framework',
    'rest_framework_simplejwt',
    'drf_spectacular',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.middleware.common.CommonMiddleware',
]

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
            ],
        },
    },
]

LANGUAGE_CODE = 'vi-vn'
TIME_ZONE = 'Asia/Ho_Chi_Minh'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# ==============================================================================
# REST FRAMEWORK & JWT
# ==============================================================================
# Mặc định: xác thực STATELESS — chỉ kiểm tra chữ ký JWT và đọc claims
# (user_id, username, role, is_superuser). Không truy vấn bảng User.
# Riêng Identity Service ghi đè bằng JWTAuthentication (có tra DB).
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTStatelessUserAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_SCHEMA_CLASS': 'drf_spectacular.openapi.AutoSchema',
}

SIMPLE_JWT = {
    # Access token ngắn hạn: các service 2–5 xác thực stateless nên tài khoản bị khóa
    # chỉ mất quyền khi access token hết hạn. Client dùng refresh token để gia hạn.
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=int(os.getenv('JWT_ACCESS_MINUTES', '60'))),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=int(os.getenv('JWT_REFRESH_DAYS', '7'))),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': False,
    'AUTH_HEADER_TYPES': ('Bearer',),
    'USER_ID_FIELD': 'id',
    'USER_ID_CLAIM': 'user_id',
    'SIGNING_KEY': JWT_SIGNING_KEY,
}


# ==============================================================================
# SERVICE-TO-SERVICE & SPRINT FEATURE LOCK
# ==============================================================================
# Địa chỉ nội bộ các service (kiểm tra quyền sở hữu dữ liệu chéo service, xem common/service_client.py).
SERVICE_URLS = {
    'identity': os.getenv('IDENTITY_SERVICE_URL', 'http://127.0.0.1:8001'),
    'property': os.getenv('PROPERTY_SERVICE_URL', 'http://127.0.0.1:8002'),
    'tenant': os.getenv('TENANT_SERVICE_URL', 'http://127.0.0.1:8003'),
    'contract': os.getenv('CONTRACT_SERVICE_URL', 'http://127.0.0.1:8004'),
    'billing': os.getenv('BILLING_SERVICE_URL', 'http://127.0.0.1:8005'),
}
INTER_SERVICE_TIMEOUT = float(os.getenv('INTER_SERVICE_TIMEOUT', '3'))

# D3: khóa các API nghiệp vụ chưa thuộc Sprint hiện tại (xem common/sprint.py). Mặc định BẬT khóa.
SPRINT_FEATURE_LOCK = os.getenv('SPRINT_FEATURE_LOCK', 'True').strip().lower() in ('1', 'true', 'yes')


def spectacular_settings(title, description):
    return {
        'TITLE': title,
        'DESCRIPTION': description,
        'VERSION': '2.0.0',
        'SERVE_INCLUDE_SCHEMA': False,
    }
