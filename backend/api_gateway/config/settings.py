"""
API GATEWAY (:8000)

Gateway KHÔNG có database và KHÔNG chứa business logic nghiệp vụ. Nhiệm vụ:
  1. Routing   : /api/<prefix>/... -> service sở hữu prefix đó
  2. Health    : /api/system/health/ — kiểm tra thực tế /health/ của 5 service
  3. Aggregate : /api/dashboard/summary/ — gộp số liệu thống kê từ các service
  4. Biên an ninh cho Frontend: CORS chỉ bật ở Gateway, URL nội bộ của service bị ẩn.
"""
import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR.parent / '.env')

# Mặc định DEBUG=False; bật khi phát triển bằng DEBUG=True trong backend/.env.
DEBUG = os.getenv('DEBUG', 'False').strip().lower() in ('1', 'true', 'yes')
SECRET_KEY = os.getenv('GATEWAY_SECRET_KEY') or os.getenv('SECRET_KEY') or ''
if not SECRET_KEY:
    if not DEBUG:
        from django.core.exceptions import ImproperlyConfigured
        raise ImproperlyConfigured('Thiếu SECRET_KEY/GATEWAY_SECRET_KEY cho API Gateway.')
    SECRET_KEY = 'dev-only-insecure-gateway-secret-key'
_hosts = os.getenv('ALLOWED_HOSTS', '').strip()
ALLOWED_HOSTS = [h.strip() for h in _hosts.split(',') if h.strip()] if _hosts else (
    ['*'] if DEBUG else ['127.0.0.1', 'localhost'])

INSTALLED_APPS = [
    'corsheaders',
    'gateway',
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'django.middleware.common.CommonMiddleware',
]

ROOT_URLCONF = 'config.urls'
WSGI_APPLICATION = 'config.wsgi.application'
DATABASES = {}
USE_TZ = True
TIME_ZONE = 'Asia/Ho_Chi_Minh'
# Gateway chỉ chuyển tiếp nguyên trạng, không tự thêm/bỏ dấu "/".
APPEND_SLASH = False
# Body upload tối đa chuyển tiếp qua gateway (10 MB).
DATA_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024

GATEWAY_PORT = int(os.getenv('GATEWAY_PORT', '8000'))

# ------------------------------------------------------------------------------
# SERVICE REGISTRY — nguồn sự thật duy nhất về vị trí các service.
# Frontend không cần biết các URL này.
# ------------------------------------------------------------------------------
SERVICE_REGISTRY = {
    'identity': {
        'name': 'Identity Service',
        'port': 8001,
        'url': os.getenv('IDENTITY_SERVICE_URL', 'http://127.0.0.1:8001'),
        'prefixes': ['auth', 'users'],
    },
    'property': {
        'name': 'Property & Maintenance Service',
        'port': 8002,
        'url': os.getenv('PROPERTY_SERVICE_URL', 'http://127.0.0.1:8002'),
        'prefixes': ['properties', 'rooms', 'maintenance', 'maintenance-history'],
    },
    'tenant': {
        'name': 'Tenant Service',
        'port': 8003,
        'url': os.getenv('TENANT_SERVICE_URL', 'http://127.0.0.1:8003'),
        'prefixes': ['tenants'],
    },
    'contract': {
        'name': 'Contract Service',
        'port': 8004,
        'url': os.getenv('CONTRACT_SERVICE_URL', 'http://127.0.0.1:8004'),
        'prefixes': ['contracts'],
    },
    'billing': {
        'name': 'Billing & Notification Service',
        'port': 8005,
        'url': os.getenv('BILLING_SERVICE_URL', 'http://127.0.0.1:8005'),
        'prefixes': ['billing', 'notifications'],
    },
}

GATEWAY_CONNECT_TIMEOUT = float(os.getenv('GATEWAY_CONNECT_TIMEOUT', '2'))
GATEWAY_READ_TIMEOUT = float(os.getenv('GATEWAY_READ_TIMEOUT', '15'))
GATEWAY_HEALTH_TIMEOUT = float(os.getenv('GATEWAY_HEALTH_TIMEOUT', '2'))

# CORS: chỉ Gateway mở cho trình duyệt. Mặc định cho phép mọi origin khi dev;
# production đặt CORS_ALLOWED_ORIGINS="https://app.example.com,https://admin.example.com".
_cors = os.getenv('CORS_ALLOWED_ORIGINS', '').strip()
if _cors:
    CORS_ALLOWED_ORIGINS = [o.strip() for o in _cors.split(',') if o.strip()]
elif DEBUG:
    CORS_ALLOW_ALL_ORIGINS = True
else:
    CORS_ALLOWED_ORIGINS = []
# Xác thực bằng header Authorization: Bearer (không dùng cookie) -> không cần credentials.
CORS_ALLOW_CREDENTIALS = False
