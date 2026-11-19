"""HTTP client nội bộ gateway -> service (một Session dùng chung, có connection pooling)."""
import uuid

import requests
from django.conf import settings

_session = requests.Session()

HOP_BY_HOP = {
    'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailers',
    'transfer-encoding', 'upgrade', 'host', 'content-length',
}
# requests tự giải nén body nên không được chuyển tiếp content-encoding gốc.
STRIP_RESPONSE = HOP_BY_HOP | {'content-encoding'}


def session():
    return _session


def forward_headers(request):
    headers = {}
    for key, value in request.headers.items():
        if key.lower() not in HOP_BY_HOP and key.lower() != 'cookie':
            headers[key] = value
    headers['X-Forwarded-For'] = request.META.get('REMOTE_ADDR', '')
    headers['X-Forwarded-Host'] = request.get_host()
    headers['X-Request-ID'] = request.headers.get('X-Request-ID') or uuid.uuid4().hex
    return headers


def get_json(url, headers=None, timeout=None):
    timeout = timeout or (settings.GATEWAY_CONNECT_TIMEOUT, settings.GATEWAY_READ_TIMEOUT)
    return _session.get(url, headers=headers or {}, timeout=timeout)
