from datetime import timedelta

from unittest import mock

import requests
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework import status

from common.testing import fake_http_response, jwt_client, patch_tenant_links, tenant_link
from services.contract_service.models import Contract, ContractStatus


# Kiểm thử source nghiệp vụ được GIỮ LẠI cho Sprint sau (tạo/gia hạn/kết thúc) với khóa D3 tắt.
@override_settings(SPRINT_FEATURE_LOCK=False)
class ContractServiceTests(TestCase):
    def setUp(self):
        self.client = jwt_client(10, 'LANDLORD')
        self.today = timezone.localdate()

    def _payload(self, **kw):
        data = {'room_id': 1, 'tenant_id': 5, 'start_date': str(self.today),
                'end_date': str(self.today + timedelta(days=180)), 'rental_price': '3000000'}
        data.update(kw)
        return data

    def test_create_extend_terminate_history(self):
        res = self.client.post('/api/contracts/', self._payload(), format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        cid = res.data['id']
        self.assertTrue(res.data['contract_number'].startswith('HD'))
        self.assertEqual(res.data['landlord_id'], 10)

        dup = self.client.post('/api/contracts/', self._payload(), format='json')
        self.assertEqual(dup.status_code, status.HTTP_400_BAD_REQUEST)

        new_end = str(self.today + timedelta(days=365))
        res = self.client.post(f'/api/contracts/{cid}/extend/', {'new_end_date': new_end}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        self.assertEqual(res.data['status'], ContractStatus.EXTENDED)
        self.assertEqual(res.data['end_date'], new_end)

        self.assertEqual(self.client.get('/api/contracts/summary/').data['active_contracts'], 1)

        res = self.client.post(f'/api/contracts/{cid}/terminate/', {'reason': 'Chuyển đi'}, format='json')
        self.assertEqual(res.data['status'], ContractStatus.TERMINATED)
        events = self.client.get(f'/api/contracts/{cid}/history/').data
        self.assertEqual([e['event_type'] for e in events], ['TERMINATED', 'EXTENDED', 'CREATED'])
        self.assertEqual(self.client.get('/api/contracts/summary/').data['active_contracts'], 0)

    def test_validation_and_status_guard(self):
        res = self.client.post('/api/contracts/', self._payload(end_date=str(self.today)), format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        res = self.client.post('/api/contracts/', self._payload(status='DRAFT'), format='json')
        cid = res.data['id']
        res = self.client.patch(f'/api/contracts/{cid}/', {'status': 'TERMINATED'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        res = self.client.post(f'/api/contracts/{cid}/activate/')
        self.assertEqual(res.data['status'], ContractStatus.ACTIVE)

    def test_scope(self):
        Contract.objects.create(contract_number='X1', room_id=9, tenant_id=1, landlord_id=99,
                                start_date=self.today, end_date=self.today + timedelta(days=10),
                                rental_price=1)
        self.assertEqual(len(self.client.get('/api/contracts/').data), 0)
        self.assertEqual(jwt_client(1, 'ADMIN').get('/api/contracts/summary/').data['active_contracts'], 1)
        # TENANT không có hồ sơ người thuê -> không thấy hợp đồng nào (trước đây: 403).
        with patch_tenant_links({}):
            self.assertEqual(jwt_client(2, 'TENANT').get('/api/contracts/').data, [])



class ContractRoleScopeAndLockTests(TestCase):
    """E1: TENANT xem hợp đồng của mình qua tenant_id; D3: API nghiệp vụ bị khóa ở backend."""

    def setUp(self):
        today = timezone.localdate()
        base = dict(start_date=today, end_date=today + timedelta(days=90), rental_price=1)
        self.mine = Contract.objects.create(contract_number='C-MINE', room_id=1, tenant_id=5, landlord_id=10, **base)
        self.same_landlord = Contract.objects.create(contract_number='C-L10', room_id=2, tenant_id=6, landlord_id=10,
                                                     **base)
        self.foreign = Contract.objects.create(contract_number='C-L99', room_id=9, tenant_id=7, landlord_id=99, **base)
        # user_id 50 (Identity) <-> tenant_id 5 (Tenant Service). user_id != tenant_id.
        self.links = {50: [tenant_link(5, 50, room_id=1, landlord_id=10)]}

    def numbers(self, res):
        self.assertEqual(res.status_code, status.HTTP_200_OK, getattr(res, 'data', None))
        return sorted(c['contract_number'] for c in res.data)

    def test_admin_sees_all_landlord_sees_own(self):
        self.assertEqual(self.numbers(jwt_client(1, 'ADMIN').get('/api/contracts/')), ['C-L10', 'C-L99', 'C-MINE'])
        landlord = jwt_client(10, 'LANDLORD')
        self.assertEqual(self.numbers(landlord.get('/api/contracts/')), ['C-L10', 'C-MINE'])
        self.assertEqual(landlord.get(f'/api/contracts/{self.foreign.id}/').status_code, status.HTTP_404_NOT_FOUND)

    def test_tenant_sees_only_own_contracts(self):
        tenant = jwt_client(50, 'TENANT')
        with patch_tenant_links(self.links):
            self.assertEqual(self.numbers(tenant.get('/api/contracts/')), ['C-MINE'])
            self.assertEqual(tenant.get(f'/api/contracts/{self.mine.id}/').status_code, status.HTTP_200_OK)
            self.assertEqual(tenant.get(f'/api/contracts/{self.mine.id}/history/').status_code, status.HTTP_200_OK)
            for other in (self.same_landlord, self.foreign):
                self.assertEqual(tenant.get(f'/api/contracts/{other.id}/').status_code, status.HTTP_404_NOT_FOUND)
            # Không mở rộng phạm vi bằng tham số lọc.
            self.assertEqual(self.numbers(tenant.get('/api/contracts/?tenant_id=6')), [])
            self.assertEqual(tenant.get('/api/contracts/summary/').data['total_contracts'], 1)
        # Tài khoản trùng số với tenant_id nhưng không có liên kết: không thấy gì (không nhầm user_id với tenant_id).
        with patch_tenant_links(self.links):
            self.assertEqual(self.numbers(jwt_client(5, 'TENANT').get('/api/contracts/')), [])

    def test_tenant_lookup_real_http_path_and_fail_closed(self):
        tenant = jwt_client(50, 'TENANT')
        with mock.patch('common.service_client.requests.get',
                        return_value=fake_http_response(200, self.links[50])) as fake:
            self.assertEqual(self.numbers(tenant.get('/api/contracts/')), ['C-MINE'])
        self.assertEqual(fake.call_args.args[0], 'http://127.0.0.1:8003/api/tenants/links/')
        with mock.patch('common.service_client.requests.get', side_effect=requests.exceptions.Timeout()):
            self.assertEqual(tenant.get('/api/contracts/').status_code, status.HTTP_503_SERVICE_UNAVAILABLE)

    def test_staff_is_not_admin(self):
        with patch_tenant_links({}):
            staff = jwt_client(300, 'STAFF')
            self.assertEqual(self.numbers(staff.get('/api/contracts/')), [])
            self.assertEqual(staff.get(f'/api/contracts/{self.mine.id}/').status_code, status.HTTP_404_NOT_FOUND)

    def test_business_endpoints_locked(self):
        landlord = jwt_client(10, 'LANDLORD')
        today = timezone.localdate()
        payload = {'room_id': 3, 'tenant_id': 8, 'start_date': str(today),
                   'end_date': str(today + timedelta(days=30)), 'rental_price': '1'}
        calls = [
            ('post', '/api/contracts/', payload),
            ('patch', f'/api/contracts/{self.mine.id}/', {'rental_price': '2'}),
            ('put', f'/api/contracts/{self.mine.id}/', payload),
            ('delete', f'/api/contracts/{self.mine.id}/', None),
            ('post', f'/api/contracts/{self.mine.id}/activate/', {}),
            ('post', f'/api/contracts/{self.mine.id}/extend/', {'new_end_date': str(today + timedelta(days=400))}),
            ('post', f'/api/contracts/{self.mine.id}/terminate/', {}),
        ]
        for client in (landlord, jwt_client(1, 'ADMIN')):
            for method, url, data in calls:
                res = getattr(client, method)(url, data, format='json')
                self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN, (method, url))
        self.assertEqual(Contract.objects.count(), 3)
        self.mine.refresh_from_db()
        self.assertEqual((self.mine.status, float(self.mine.rental_price)), (ContractStatus.ACTIVE, 1.0))
        from rest_framework.test import APIClient
        self.assertEqual(APIClient().post('/api/contracts/', payload, format='json').status_code,
                         status.HTTP_401_UNAUTHORIZED)
