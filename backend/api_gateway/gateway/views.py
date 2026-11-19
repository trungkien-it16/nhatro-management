import re
import time
from concurrent.futures import ThreadPoolExecutor

import requests
from django.conf import settings
from django.http import HttpResponse, JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt

from . import client
from .registry import route_table, service_for_path, services


def _error(http_status, message, **extra):
    return JsonResponse({'error': message, **extra}, status=http_status, json_dumps_params={'ensure_ascii': False})


# ==============================================================================
# 1. ROUTING / REVERSE PROXY
# ==============================================================================
@csrf_exempt
def proxy(request, path):
    """/api/<path> -> <service_url>/api/<path> (giữ nguyên method, query, body, Authorization)."""
    key, conf = service_for_path(path)
    if conf is None:
        return _error(404, f'Không có service nào phục vụ đường dẫn /api/{path}',
                      available_routes=list(route_table().keys()))

    url = f"{conf['url'].rstrip('/')}/api/{path}"
    query = request.META.get('QUERY_STRING')
    if query:
        url = f'{url}?{query}'

    try:
        upstream = client.session().request(
            method=request.method,
            url=url,
            headers=client.forward_headers(request),
            data=request.body if request.body else None,
            timeout=(settings.GATEWAY_CONNECT_TIMEOUT, settings.GATEWAY_READ_TIMEOUT),
            allow_redirects=False,
        )
    except requests.exceptions.Timeout:
        return _error(504, f"{conf['name']} không phản hồi kịp (timeout).", service=key, status='DOWN')
    except requests.exceptions.ConnectionError:
        return _error(503, f"{conf['name']} hiện không hoạt động (port {conf['port']}).", service=key, status='DOWN')

    response = HttpResponse(upstream.content, status=upstream.status_code)
    for header, value in upstream.headers.items():
        if header.lower() not in client.STRIP_RESPONSE:
            response[header] = value
    response['X-Served-By'] = key
    return response


def legacy_v1_proxy(request, path):
    """Alias tương thích ngược: /api/v1/<path> -> /api/<path>."""
    return proxy(request, path)


# ==============================================================================
# 2. SYSTEM HEALTH
# ==============================================================================
def check_service(key, conf):
    started = time.monotonic()
    result = {'key': key, 'name': conf['name'], 'port': conf['port']}
    try:
        resp = client.get_json(f"{conf['url'].rstrip('/')}/health/", timeout=settings.GATEWAY_HEALTH_TIMEOUT)
    except requests.exceptions.Timeout:
        return {**result, 'status': 'DOWN', 'error': 'Timeout khi kiểm tra health.'}
    except requests.exceptions.ConnectionError:
        return {**result, 'status': 'DOWN', 'error': 'Không kết nối được tới service.'}
    result['response_time_ms'] = round((time.monotonic() - started) * 1000, 1)
    try:
        body = resp.json()
    except ValueError:
        return {**result, 'status': 'UNKNOWN', 'error': f'Phản hồi health không hợp lệ (HTTP {resp.status_code}).'}

    reported = body.get('status') if isinstance(body, dict) else None
    if resp.status_code == 200 and reported == 'UP':
        status = 'UP'
    elif reported == 'DOWN':
        status = 'DOWN'
    else:
        status = 'UNKNOWN'
    result['status'] = status
    if isinstance(body, dict) and isinstance(body.get('database'), dict):
        result['database'] = body['database']
    if status != 'UP':
        result['error'] = (body.get('database') or {}).get('error') if isinstance(body, dict) else None
        result['error'] = result['error'] or f'HTTP {resp.status_code}'
    return result


def system_health(request):
    """
    GET /api/system/health/
    Gateway gọi song song /health/ của từng service và trả về trạng thái THỰC TẾ.
    """
    registry = services()
    with ThreadPoolExecutor(max_workers=len(registry)) as pool:
        results = list(pool.map(lambda item: check_service(*item), registry.items()))

    up = sum(1 for r in results if r['status'] == 'UP')
    if up == len(results):
        overall = 'UP'
    elif up == 0:
        overall = 'DOWN'
    else:
        overall = 'DEGRADED'
    return JsonResponse({
        'gateway': {'name': 'API Gateway', 'status': 'UP', 'port': settings.GATEWAY_PORT},
        'overall_status': overall,
        'summary': {'total': len(results), 'up': up, 'down': len(results) - up},
        'services': results,
        'checked_at': timezone.now().isoformat(),
    }, json_dumps_params={'ensure_ascii': False})


def gateway_health(request):
    return JsonResponse({'service': 'API Gateway', 'key': 'gateway', 'port': settings.GATEWAY_PORT, 'status': 'UP'})


# ==============================================================================
# 3. DASHBOARD AGGREGATION
# ==============================================================================
# service key -> (endpoint thống kê, các trường lấy về Dashboard)
DASHBOARD_SOURCES = {
    'property': ('/api/properties/summary/', [
        'total_properties', 'total_rooms', 'occupied_rooms', 'available_rooms', 'maintenance_rooms',
        'reserved_rooms', 'full_rooms', 'inactive_rooms', 'occupancy_rate_percent',
        'estimated_monthly_revenue', 'open_maintenance_requests']),
    'tenant': ('/api/tenants/summary/', ['total_tenants', 'active_tenants']),
    'contract': ('/api/contracts/summary/', ['active_contracts', 'expiring_soon_contracts']),
    'billing': ('/api/billing/invoices/summary/', ['unpaid_invoices', 'overdue_invoices', 'unpaid_amount']),
}


def _fetch_source(key, auth_header):
    conf = services()[key]
    endpoint, fields = DASHBOARD_SOURCES[key]
    meta = {'service': conf['name'], 'port': conf['port']}
    try:
        resp = client.get_json(f"{conf['url'].rstrip('/')}{endpoint}", headers={'Authorization': auth_header})
    except requests.exceptions.Timeout:
        return key, fields, None, {**meta, 'status': 'DOWN', 'error': 'Timeout'}
    except requests.exceptions.ConnectionError:
        return key, fields, None, {**meta, 'status': 'DOWN', 'error': 'Không kết nối được tới service.'}
    if resp.status_code != 200:
        return key, fields, None, {**meta, 'status': 'ERROR', 'http_status': resp.status_code,
                                   'error': f'HTTP {resp.status_code}'}
    try:
        return key, fields, resp.json(), {**meta, 'status': 'UP'}
    except ValueError:
        return key, fields, None, {**meta, 'status': 'UNKNOWN', 'error': 'Phản hồi không phải JSON.'}


def dashboard_summary(request):
    """
    GET /api/dashboard/summary/  (cần Authorization: Bearer <token>)
    Gateway gọi song song endpoint thống kê của Property/Tenant/Contract/Billing với token
    của người dùng (để mỗi service tự phân quyền phạm vi dữ liệu), rồi gộp kết quả.
    Service nào lỗi -> các trường của nó là null và được liệt kê trong `errors`.
    """
    auth_header = request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        return _error(401, 'Cần đăng nhập (Authorization: Bearer <token>).')

    with ThreadPoolExecutor(max_workers=len(DASHBOARD_SOURCES)) as pool:
        results = list(pool.map(lambda k: _fetch_source(k, auth_header), DASHBOARD_SOURCES))

    if any(meta.get('http_status') == 401 for *_, meta in results):
        return _error(401, 'Phiên đăng nhập đã hết hạn hoặc token không hợp lệ.')

    data, sources, errors = {}, {}, []
    for key, fields, payload, meta in results:
        sources[key] = meta
        for field in fields:
            data[field] = payload.get(field) if isinstance(payload, dict) else None
        if meta['status'] != 'UP':
            errors.append({'source': key, **meta})

    return JsonResponse({
        **data,
        'sources': sources,
        'errors': errors,
        'complete': not errors,
        'generated_at': timezone.now().isoformat(),
    }, json_dumps_params={'ensure_ascii': False})


# ==============================================================================
# 4. SERVICE ENDPOINT CATALOG (chỉ đọc, phục vụ Dashboard)
# ==============================================================================
# Danh sách endpoint KHÔNG nhập tay: đọc OpenAPI mà chính service sinh ra từ URL routing
# thật (drf-spectacular, GET <service>/api/schema/). Backend đổi route -> danh sách tự đổi theo.
HTTP_METHODS = ('get', 'post', 'put', 'patch', 'delete')
SCHEMA_PATH = '/api/schema/?format=json'
_CRUD_TEXT = {
    ('collection', 'GET'): 'Danh sách',
    ('collection', 'POST'): 'Tạo mới',
    ('detail', 'GET'): 'Xem chi tiết',
    ('detail', 'PUT'): 'Cập nhật toàn bộ',
    ('detail', 'PATCH'): 'Cập nhật một phần',
    ('detail', 'DELETE'): 'Xóa',
}


# Dòng docstring liệt kê action, vd. "- GET/POST /{id}/history/  lịch sử thuê".
_DOC_LINE = re.compile(
    r'^-?\s*((?:GET|POST|PUT|PATCH|DELETE)(?:\s*/\s*(?:GET|POST|PUT|PATCH|DELETE))*)\s+(/\S*)\s+(.+)$')
_SERVICE_TAG = re.compile(r'^SERVICE\s+\d+\s+—\s+[^:]+:\s*')


def _first_line(text):
    line = next((line.strip() for line in (text or '').splitlines() if line.strip()), '')
    return _SERVICE_TAG.sub('', line)


def _describe(path, method, description, shared, kind):
    """
    Mô tả lấy từ docstring của view trong source code:
      - docstring riêng của view/action (không dùng chung với path khác) -> dòng đầu của nó;
      - docstring chung của ViewSet -> dòng liệt kê đúng method + action đó;
      - endpoint CRUD chuẩn của router -> tên thao tác CRUD.
    """
    if description and not shared:
        return _first_line(description)
    for line in (description or '').splitlines():
        m = _DOC_LINE.match(line.strip())
        if m and method in {x.strip() for x in m.group(1).split('/')} and path.endswith(m.group(2)):
            return m.group(3).strip()
    if kind in ('collection', 'detail'):
        return _CRUD_TEXT.get((kind, method), _first_line(description))
    action = [s for s in path.strip('/').split('/') if not s.startswith('{')][-1]
    return f'Thao tác "{action}"'


def _path_kind(path, all_paths):
    """detail: /x/{id}/ — collection: /x/ có /x/{id}/ đi kèm (router) — còn lại: action / view riêng."""
    if re.search(r'/\{[^/]+\}/$', path):
        return 'detail'
    if any(re.fullmatch(re.escape(path) + r'\{[^/]+\}/', p) for p in all_paths):
        return 'collection'
    return 'action'


def parse_openapi_endpoints(schema, base_url, prefixes):
    """OpenAPI 3 -> [{group, method, path, full_url, description, operation_id}] theo thứ tự route."""
    operations = []
    for path, item in (schema.get('paths') or {}).items():
        for method in HTTP_METHODS:
            op = item.get(method) if isinstance(item, dict) else None
            if isinstance(op, dict):
                operations.append((path, method.upper(), op))
    # Docstring xuất hiện ở NHIỀU path khác nhau = docstring chung của ViewSet.
    paths_by_description = {}
    for path, _method, op in operations:
        paths_by_description.setdefault((op.get('description') or '').strip(), set()).add(path)
    all_paths = {path for path, _m, _o in operations}

    endpoints = []
    for path, method, op in operations:
        description = (op.get('description') or op.get('summary') or '').strip()
        segments = path.strip('/').split('/')
        group = segments[1] if len(segments) > 1 and segments[0] == 'api' else segments[0]
        # Prefix nhiều cấp (vd. /api/billing/invoices/) vẫn thuộc prefix 'billing' của registry.
        if group not in prefixes and group != 'health':
            group = next((p for p in prefixes if path.startswith(f'/api/{p}/')), group)
        endpoints.append({
            'group': group,
            'method': method,
            'path': path,
            'full_url': f"{base_url.rstrip('/')}{path}",
            'description': _describe(path, method, description,
                                     len(paths_by_description.get(description, ())) > 1,
                                     _path_kind(path, all_paths)),
            'operation_id': op.get('operationId', ''),
        })
    return endpoints


def require_admin(request):
    """
    Chỉ ADMIN: Gateway không tự giải mã JWT mà hỏi Identity Service (/api/auth/me/) bằng chính token
    của người gọi -> role lấy từ database Identity (không tin dữ liệu client).
    Trả về None nếu hợp lệ, ngược lại JsonResponse 401 / 403 / 503.
    """
    auth_header = request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        return _error(401, 'Cần đăng nhập (Authorization: Bearer <token>).')
    identity = services()['identity']
    try:
        resp = client.get_json(f"{identity['url'].rstrip('/')}/api/auth/me/", headers={'Authorization': auth_header},
                               timeout=settings.GATEWAY_HEALTH_TIMEOUT)
    except requests.exceptions.RequestException:
        return _error(503, 'Identity Service không phản hồi — không xác minh được quyền.', service='identity')
    if resp.status_code == 401:
        return _error(401, 'Phiên đăng nhập đã hết hạn hoặc token không hợp lệ.')
    try:
        me = resp.json() if resp.status_code == 200 else None
    except ValueError:
        me = None
    if not isinstance(me, dict):
        return _error(503, f'Không xác minh được quyền (Identity HTTP {resp.status_code}).', service='identity')
    if me.get('role') != 'ADMIN':
        return _error(403, 'Chỉ Quản trị viên (ADMIN) được xem danh sách endpoint nội bộ.')
    return None


def service_endpoints(request, key):
    """
    GET /api/system/services/<key>/endpoints/  (chỉ ADMIN)
    Thông tin kết nối + danh sách endpoint THỰC TẾ của 1 service (đọc OpenAPI của service đó).
    Service không phản hồi -> 200 với status DOWN, endpoints rỗng và lý do (như /api/system/health/).
    """
    denied = require_admin(request)
    if denied is not None:
        return denied
    conf = services().get(key)
    if conf is None:
        return _error(404, f'Không có service "{key}".', available=list(services()))
    base_url = conf['url'].rstrip('/')
    info = {
        'key': key,
        'name': conf['name'],
        'port': conf['port'],
        'base_url': base_url,
        'prefixes': conf['prefixes'],
        'source': f'{base_url}/api/schema/',
        'checked_at': timezone.now().isoformat(),
    }
    try:
        resp = client.get_json(f'{base_url}{SCHEMA_PATH}', headers={'Accept': 'application/json'})
    except requests.exceptions.Timeout:
        return JsonResponse({**info, 'status': 'DOWN', 'endpoints': [], 'error': 'Timeout khi đọc API schema.'},
                            json_dumps_params={'ensure_ascii': False})
    except requests.exceptions.ConnectionError:
        return JsonResponse({**info, 'status': 'DOWN', 'endpoints': [], 'error': 'Không kết nối được tới service.'},
                            json_dumps_params={'ensure_ascii': False})
    try:
        schema = resp.json() if resp.status_code == 200 else None
    except ValueError:
        schema = None
    if not isinstance(schema, dict) or not isinstance(schema.get('paths'), dict):
        return JsonResponse({**info, 'status': 'UNKNOWN', 'endpoints': [],
                             'error': f'Không đọc được API schema (HTTP {resp.status_code}).'},
                            json_dumps_params={'ensure_ascii': False})
    endpoints = parse_openapi_endpoints(schema, base_url, conf['prefixes'])
    return JsonResponse({**info, 'status': 'UP', 'count': len(endpoints), 'endpoints': endpoints},
                        json_dumps_params={'ensure_ascii': False})


def index(request):
    return JsonResponse({
        'name': 'Nhà Trọ — API Gateway',
        'port': settings.GATEWAY_PORT,
        'endpoints': {
            '/api/system/health/': 'Trạng thái thực tế của Gateway và 5 service',
            '/api/dashboard/summary/': 'Số liệu tổng hợp cho Dashboard (cần đăng nhập)',
        },
        'routes': route_table(),
    }, json_dumps_params={'ensure_ascii': False})
