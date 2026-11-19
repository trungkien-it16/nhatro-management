from unittest import mock

import requests
from django.test import SimpleTestCase


def _resp(status=200, json_body=None, content=b'', headers=None):
    r = mock.Mock()
    r.status_code = status
    r.headers = headers or {'Content-Type': 'application/json'}
    r.content = content
    if json_body is None:
        r.json.side_effect = ValueError('no json')
    else:
        r.json.return_value = json_body
    return r


class SystemHealthTests(SimpleTestCase):
    def test_reports_real_status_per_service(self):
        def fake_get(url, headers=None, timeout=None):
            if ':8003' in url:
                raise requests.exceptions.ConnectionError()
            if ':8005' in url:
                return _resp(503, {'status': 'DOWN', 'database': {'status': 'DOWN', 'error': 'db lỗi'}})
            if ':8004' in url:
                return _resp(500, None, b'<html>')
            return _resp(200, {'status': 'UP', 'database': {'status': 'UP'}})

        with mock.patch('gateway.client.get_json', side_effect=fake_get):
            data = self.client.get('/api/system/health/').json()

        self.assertEqual(data['gateway'], {'name': 'API Gateway', 'status': 'UP', 'port': 8000})
        status = {s['port']: s['status'] for s in data['services']}
        self.assertEqual(status, {8001: 'UP', 8002: 'UP', 8003: 'DOWN', 8004: 'UNKNOWN', 8005: 'DOWN'})
        self.assertEqual(data['overall_status'], 'DEGRADED')
        self.assertEqual(data['summary'], {'total': 5, 'up': 2, 'down': 3})

    def test_all_up(self):
        with mock.patch('gateway.client.get_json', return_value=_resp(200, {'status': 'UP'})):
            data = self.client.get('/api/system/health/').json()
        self.assertEqual(data['overall_status'], 'UP')
        self.assertEqual([s['name'] for s in data['services']], [
            'Identity Service', 'Property & Maintenance Service', 'Tenant Service',
            'Contract Service', 'Billing & Notification Service'])


class ProxyTests(SimpleTestCase):
    def _proxy(self, path, method='get', **kwargs):
        with mock.patch('gateway.client._session.request',
                        return_value=_resp(201, {}, b'{"ok":true}',
                                           {'Content-Type': 'application/json', 'Content-Encoding': 'gzip'})) as req:
            res = getattr(self.client, method)(path, **kwargs)
        return res, req

    def test_routes_to_owner_service_with_auth_and_query(self):
        cases = {
            '/api/auth/login/': 'http://127.0.0.1:8001/api/auth/login/',
            '/api/users/': 'http://127.0.0.1:8001/api/users/',
            '/api/properties/1/stats/': 'http://127.0.0.1:8002/api/properties/1/stats/',
            '/api/rooms/?status=AVAILABLE': 'http://127.0.0.1:8002/api/rooms/?status=AVAILABLE',
            '/api/maintenance/': 'http://127.0.0.1:8002/api/maintenance/',
            '/api/tenants/': 'http://127.0.0.1:8003/api/tenants/',
            '/api/contracts/5/extend/': 'http://127.0.0.1:8004/api/contracts/5/extend/',
            '/api/billing/invoices/': 'http://127.0.0.1:8005/api/billing/invoices/',
            '/api/notifications/': 'http://127.0.0.1:8005/api/notifications/',
            '/api/v1/rooms/3/': 'http://127.0.0.1:8002/api/rooms/3/',
        }
        for path, expected in cases.items():
            res, req = self._proxy(path, HTTP_AUTHORIZATION='Bearer abc')
            self.assertEqual(req.call_args.kwargs['url'], expected, path)
            self.assertEqual(req.call_args.kwargs['headers']['Authorization'], 'Bearer abc')
            self.assertEqual(res.status_code, 201)
            self.assertNotIn('Content-Encoding', res)

    def test_forwards_method_and_body(self):
        res, req = self._proxy('/api/rooms/', method='post', data='{"a":1}', content_type='application/json')
        self.assertEqual(req.call_args.kwargs['method'], 'POST')
        self.assertEqual(req.call_args.kwargs['data'], b'{"a":1}')

    def test_unknown_route_404(self):
        res = self.client.get('/api/unknown/')
        self.assertEqual(res.status_code, 404)
        self.assertIn('/api/rooms/', res.json()['available_routes'])

    def test_service_down_returns_503_json(self):
        with mock.patch('gateway.client._session.request', side_effect=requests.exceptions.ConnectionError()):
            res = self.client.get('/api/tenants/')
        self.assertEqual(res.status_code, 503)
        self.assertEqual(res.json()['service'], 'tenant')

    def test_timeout_returns_504(self):
        with mock.patch('gateway.client._session.request', side_effect=requests.exceptions.ReadTimeout()):
            self.assertEqual(self.client.get('/api/contracts/').status_code, 504)


class DashboardSummaryTests(SimpleTestCase):
    PAYLOADS = {
        '/api/properties/summary/': {'total_properties': 2, 'total_rooms': 20, 'occupied_rooms': 12,
                                     'available_rooms': 6, 'maintenance_rooms': 2, 'reserved_rooms': 0,
                                     'occupancy_rate_percent': 60.0, 'open_maintenance_requests': 1},
        '/api/tenants/summary/': {'total_tenants': 18, 'active_tenants': 15},
        '/api/contracts/summary/': {'active_contracts': 12, 'expiring_soon_contracts': 1},
        '/api/billing/invoices/summary/': {'unpaid_invoices': 5, 'overdue_invoices': 2, 'unpaid_amount': '1000'},
    }

    def _fake(self, down=None, unauthorized=False):
        def fake_get(url, headers=None, timeout=None):
            assert headers['Authorization'] == 'Bearer tok'
            for path, body in self.PAYLOADS.items():
                if url.endswith(path):
                    if down and down in path:
                        raise requests.exceptions.ConnectionError()
                    if unauthorized:
                        return _resp(401, {'detail': 'x'})
                    return _resp(200, body)
            raise AssertionError(url)
        return fake_get

    def test_requires_token(self):
        self.assertEqual(self.client.get('/api/dashboard/summary/').status_code, 401)

    def test_aggregates_all_sources(self):
        with mock.patch('gateway.client.get_json', side_effect=self._fake()):
            data = self.client.get('/api/dashboard/summary/', HTTP_AUTHORIZATION='Bearer tok').json()
        self.assertEqual(data['total_properties'], 2)
        self.assertEqual(data['total_rooms'], 20)
        self.assertEqual(data['total_tenants'], 18)
        self.assertEqual(data['active_contracts'], 12)
        self.assertEqual(data['unpaid_invoices'], 5)
        self.assertTrue(data['complete'])
        self.assertEqual(data['errors'], [])

    def test_partial_failure_returns_nulls_not_500(self):
        with mock.patch('gateway.client.get_json', side_effect=self._fake(down='tenants')):
            res = self.client.get('/api/dashboard/summary/', HTTP_AUTHORIZATION='Bearer tok')
        data = res.json()
        self.assertEqual(res.status_code, 200)
        self.assertIsNone(data['total_tenants'])
        self.assertEqual(data['total_rooms'], 20)
        self.assertFalse(data['complete'])
        self.assertEqual(data['errors'][0]['source'], 'tenant')
        self.assertEqual(data['sources']['tenant']['status'], 'DOWN')

    def test_invalid_token_propagates_401(self):
        with mock.patch('gateway.client.get_json', side_effect=self._fake(unauthorized=True)):
            res = self.client.get('/api/dashboard/summary/', HTTP_AUTHORIZATION='Bearer tok')
        self.assertEqual(res.status_code, 401)


# Trích OpenAPI đúng dạng drf-spectacular sinh cho Billing & Notification (:8005).
_BILLING_DOC = ('SERVICE 5 — BILLING\n- CRUD hóa đơn\n- POST /{id}/pay/     đánh dấu đã thanh toán\n'
                '- GET  /debt/         công nợ theo phòng')
_NOTI_DOC = ('SERVICE 5 — NOTIFICATION\n- GET  /notifications/   thông báo của tôi\n'
             '- POST /notifications/   gửi thông báo\n- POST /notifications/{id}/read/    đánh dấu đã đọc')
_BILLING_SCHEMA = {
    'openapi': '3.0.3',
    'paths': {
        '/api/billing/invoices/': {'get': {'operationId': 'billing_invoices_list', 'description': _BILLING_DOC},
                                   'post': {'operationId': 'billing_invoices_create', 'description': _BILLING_DOC}},
        '/api/billing/invoices/{id}/': {
            'parameters': [{'name': 'id', 'in': 'path'}],
            'get': {'operationId': 'billing_invoices_retrieve', 'description': _BILLING_DOC},
            'patch': {'operationId': 'billing_invoices_partial_update', 'description': _BILLING_DOC},
            'delete': {'operationId': 'billing_invoices_destroy', 'description': _BILLING_DOC}},
        '/api/billing/invoices/{id}/pay/': {'post': {'operationId': 'billing_invoices_pay_create',
                                                     'description': _BILLING_DOC}},
        '/api/billing/invoices/debt/': {'get': {'operationId': 'billing_invoices_debt_retrieve',
                                                'description': _BILLING_DOC}},
        '/api/notifications/': {'get': {'operationId': 'notifications_list', 'description': _NOTI_DOC},
                                'post': {'operationId': 'notifications_create', 'description': _NOTI_DOC}},
        '/api/notifications/{id}/': {'get': {'operationId': 'notifications_retrieve', 'description': _NOTI_DOC}},
        '/api/notifications/{id}/read/': {'post': {'operationId': 'notifications_read_create',
                                                   'description': _NOTI_DOC}},
        '/health/': {'get': {'operationId': 'health_retrieve',
                             'description': 'GET /health/ — trạng thái thực tế của service đang chạy.\n\nchi tiết'}},
    },
}


class ServiceEndpointsTests(SimpleTestCase):
    def _get(self, key, **patch_kwargs):
        # Quyền ADMIN được kiểm tra riêng ở ServiceEndpointsAdminGuardTests.
        with mock.patch('gateway.views.require_admin', return_value=None),                 mock.patch('gateway.client.get_json', **patch_kwargs) as fake:
            res = self.client.get(f'/api/system/services/{key}/endpoints/')
        return res, fake

    def test_lists_real_endpoints_from_service_openapi(self):
        res, fake = self._get('billing', return_value=_resp(200, _BILLING_SCHEMA))
        self.assertEqual(res.status_code, 200)
        data = res.json()
        # Đọc đúng schema của chính service sở hữu (Billing :8005), không nhập tay.
        self.assertEqual(fake.call_args.args[0], 'http://127.0.0.1:8005/api/schema/?format=json')
        self.assertEqual((data['key'], data['port'], data['base_url'], data['status']),
                         ('billing', 8005, 'http://127.0.0.1:8005', 'UP'))
        rows = [(e['group'], e['method'], e['path'], e['description']) for e in data['endpoints']]
        self.assertEqual(rows, [
            ('billing', 'GET', '/api/billing/invoices/', 'Danh sách'),
            ('billing', 'POST', '/api/billing/invoices/', 'Tạo mới'),
            ('billing', 'GET', '/api/billing/invoices/{id}/', 'Xem chi tiết'),
            ('billing', 'PATCH', '/api/billing/invoices/{id}/', 'Cập nhật một phần'),
            ('billing', 'DELETE', '/api/billing/invoices/{id}/', 'Xóa'),
            ('billing', 'POST', '/api/billing/invoices/{id}/pay/', 'đánh dấu đã thanh toán'),
            ('billing', 'GET', '/api/billing/invoices/debt/', 'công nợ theo phòng'),
            ('notifications', 'GET', '/api/notifications/', 'thông báo của tôi'),
            ('notifications', 'POST', '/api/notifications/', 'gửi thông báo'),
            ('notifications', 'GET', '/api/notifications/{id}/', 'Xem chi tiết'),
            ('notifications', 'POST', '/api/notifications/{id}/read/', 'đánh dấu đã đọc'),
            ('health', 'GET', '/health/', 'GET /health/ — trạng thái thực tế của service đang chạy.'),
        ])
        self.assertEqual(data['count'], 12)
        self.assertEqual(data['endpoints'][5]['full_url'], 'http://127.0.0.1:8005/api/billing/invoices/{id}/pay/')

    def test_view_specific_docstring_used_and_service_tag_stripped(self):
        schema = {'paths': {'/api/auth/me/': {
            'get': {'description': 'SERVICE 1 — IDENTITY: Lấy & cập nhật thông tin cá nhân.'},
            'patch': {'description': 'SERVICE 1 — IDENTITY: Lấy & cập nhật thông tin cá nhân.'}}}}
        data = self._get('identity', return_value=_resp(200, schema))[0].json()
        self.assertEqual([e['description'] for e in data['endpoints']],
                         ['Lấy & cập nhật thông tin cá nhân.'] * 2)
        self.assertEqual(data['endpoints'][0]['group'], 'auth')

    def test_service_down_reports_down_with_connection_info(self):
        res, _ = self._get('tenant', side_effect=requests.exceptions.ConnectionError())
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual((data['status'], data['endpoints'], data['port'], data['base_url']),
                         ('DOWN', [], 8003, 'http://127.0.0.1:8003'))
        self.assertIn('Không kết nối', data['error'])

    def test_timeout_and_invalid_schema(self):
        data = self._get('contract', side_effect=requests.exceptions.ReadTimeout())[0].json()
        self.assertEqual(data['status'], 'DOWN')
        data = self._get('contract', return_value=_resp(500, None, b'<html>'))[0].json()
        self.assertEqual((data['status'], data['endpoints']), ('UNKNOWN', []))
        self.assertIn('HTTP 500', data['error'])

    def test_unknown_service_404(self):
        res, fake = self._get('payment', return_value=_resp(200, {}))
        self.assertEqual(res.status_code, 404)
        fake.assert_not_called()


class ServiceEndpointsAdminGuardTests(SimpleTestCase):
    """W5: danh sách endpoint nội bộ chỉ dành cho ADMIN (role xác minh qua Identity /api/auth/me/)."""
    URL = '/api/system/services/identity/endpoints/'

    def _call(self, me_resp=None, side_effect=None, token='Bearer t'):
        def fake_get(url, headers=None, timeout=None):
            if url.endswith('/api/auth/me/'):
                if side_effect:
                    raise side_effect
                return me_resp
            return _resp(200, {'paths': {}})
        headers = {'HTTP_AUTHORIZATION': token} if token else {}
        with mock.patch('gateway.client.get_json', side_effect=fake_get) as fake:
            return self.client.get(self.URL, **headers), fake

    def test_anonymous_401_without_calling_services(self):
        res, fake = self._call(token=None)
        self.assertEqual(res.status_code, 401)
        fake.assert_not_called()

    def test_invalid_token_401(self):
        self.assertEqual(self._call(_resp(401, {'detail': 'x'}))[0].status_code, 401)

    def test_landlord_tenant_staff_forbidden(self):
        for role in ('LANDLORD', 'TENANT', 'STAFF'):
            res, fake = self._call(_resp(200, {'id': 2, 'role': role}))
            self.assertEqual(res.status_code, 403, role)
            # Không đọc schema của service khi không đủ quyền.
            self.assertEqual(fake.call_count, 1)

    def test_admin_allowed(self):
        res, fake = self._call(_resp(200, {'id': 1, 'role': 'ADMIN'}))
        self.assertEqual(res.status_code, 200)
        self.assertEqual(fake.call_args_list[0].args[0], 'http://127.0.0.1:8001/api/auth/me/')
        self.assertEqual(fake.call_args_list[0].kwargs['headers'], {'Authorization': 'Bearer t'})

    def test_identity_down_fails_closed_503(self):
        res, _ = self._call(side_effect=requests.exceptions.ConnectionError())
        self.assertEqual(res.status_code, 503)

    def test_health_stays_public(self):
        with mock.patch('gateway.client.get_json', return_value=_resp(200, {'status': 'UP'})):
            self.assertEqual(self.client.get('/api/system/health/').status_code, 200)
