from datetime import timedelta

from unittest import mock

import requests
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework import status

from common.testing import fake_http_response, jwt_client, patch_tenant_links, tenant_link
from services.billing_notification_service.models import Invoice, InvoiceStatus, Notification


# Kiểm thử source nghiệp vụ được GIỮ LẠI cho Sprint sau (tạo hóa đơn/thanh toán) với khóa D3 tắt.
@override_settings(SPRINT_FEATURE_LOCK=False)
class BillingServiceTests(TestCase):
    def setUp(self):
        self.client = jwt_client(10, 'LANDLORD')
        self.today = timezone.localdate()

    def _create(self, **kw):
        data = {'room_id': 1, 'tenant_id': 3, 'billing_month': 11, 'billing_year': 2026,
                'room_fee': '3000000', 'electricity_old_num': 100, 'electricity_new_num': 150,
                'electricity_unit_price': '3500', 'water_old_num': 10, 'water_new_num': 14,
                'water_unit_price': '20000', 'other_service_cost': '100000',
                'due_date': str(self.today + timedelta(days=5))}
        data.update(kw)
        return self.client.post('/api/billing/invoices/', data, format='json')

    def test_invoice_calculation_payment_and_summary(self):
        res = self._create(notify_user_id=77)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        # 3.000.000 + 50*3.500 + 4*20.000 + 100.000
        self.assertEqual(float(res.data['total_amount']), 3355000.0)
        inv_id = res.data['id']

        summary = self.client.get('/api/billing/invoices/summary/').data
        self.assertEqual(summary['unpaid_invoices'], 1)
        self.assertEqual(float(summary['unpaid_amount']), 3355000.0)

        res = self.client.post(f'/api/billing/invoices/{inv_id}/pay/')
        self.assertEqual(res.data['status'], InvoiceStatus.PAID)
        self.assertEqual(self.client.get('/api/billing/invoices/summary/').data['unpaid_invoices'], 0)
        self.assertEqual(self.client.patch(f'/api/billing/invoices/{inv_id}/', {'room_fee': 1}, format='json')
                         .status_code, status.HTTP_400_BAD_REQUEST)

        # thông báo hóa đơn gửi tới người thuê
        tenant = jwt_client(77, 'TENANT')
        notes = tenant.get('/api/notifications/').data
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0]['category'], 'INVOICE')
        tenant.post(f"/api/notifications/{notes[0]['id']}/read/")
        self.assertEqual(len(tenant.get('/api/notifications/?unread=1').data), 0)

    def test_overdue_and_debt(self):
        self._create(due_date=str(self.today - timedelta(days=1)))
        res = self.client.get('/api/billing/invoices/debt/')
        self.assertEqual(res.data[0]['invoice_count'], 1)
        self.assertEqual(Invoice.objects.get().status, InvoiceStatus.OVERDUE)
        self.assertEqual(self.client.get('/api/billing/invoices/summary/').data['overdue_invoices'], 1)

    def test_invalid_meter_and_scope(self):
        self.assertEqual(self._create(electricity_new_num=50).status_code, status.HTTP_400_BAD_REQUEST)
        self._create()
        self.assertEqual(len(jwt_client(11, 'LANDLORD').get('/api/billing/invoices/').data), 0)
        self.assertEqual(jwt_client(77, 'TENANT').post('/api/notifications/', {
            'user_id': 1, 'title': 'x', 'content': 'y'}, format='json').status_code, status.HTTP_403_FORBIDDEN)

    def test_health(self):
        from rest_framework.test import APIClient
        self.assertEqual(APIClient().get('/health/').data['port'], 8005)



class BillingRoleScopeAndLockTests(TestCase):
    """E1: TENANT xem hóa đơn của mình qua tenant_id; D3: tạo/thanh toán/hủy hóa đơn & gửi thông báo bị khóa."""

    def setUp(self):
        today = timezone.localdate()
        base = dict(billing_month=11, billing_year=2026, room_fee=1000, total_amount=1000,
                    due_date=today + timedelta(days=5))
        self.mine = Invoice.objects.create(invoice_code='I-MINE', room_id=1, tenant_id=5, landlord_id=10, **base)
        self.same_landlord = Invoice.objects.create(invoice_code='I-L10', room_id=2, tenant_id=6, landlord_id=10,
                                                    **base)
        self.foreign = Invoice.objects.create(invoice_code='I-L99', room_id=9, tenant_id=7, landlord_id=99, **base)
        self.links = {50: [tenant_link(5, 50, room_id=1, landlord_id=10)]}

    def codes(self, res):
        self.assertEqual(res.status_code, status.HTTP_200_OK, getattr(res, 'data', None))
        return sorted(i['invoice_code'] for i in res.data)

    def test_admin_all_landlord_own(self):
        self.assertEqual(self.codes(jwt_client(1, 'ADMIN').get('/api/billing/invoices/')),
                         ['I-L10', 'I-L99', 'I-MINE'])
        landlord = jwt_client(10, 'LANDLORD')
        self.assertEqual(self.codes(landlord.get('/api/billing/invoices/')), ['I-L10', 'I-MINE'])
        self.assertEqual(landlord.get(f'/api/billing/invoices/{self.foreign.id}/').status_code,
                         status.HTTP_404_NOT_FOUND)

    def test_tenant_sees_only_own_invoices(self):
        tenant = jwt_client(50, 'TENANT')
        with patch_tenant_links(self.links):
            self.assertEqual(self.codes(tenant.get('/api/billing/invoices/')), ['I-MINE'])
            self.assertEqual(tenant.get(f'/api/billing/invoices/{self.mine.id}/').status_code, status.HTTP_200_OK)
            for other in (self.same_landlord, self.foreign):
                self.assertEqual(tenant.get(f'/api/billing/invoices/{other.id}/').status_code,
                                 status.HTTP_404_NOT_FOUND)
            self.assertEqual(self.codes(tenant.get('/api/billing/invoices/?tenant_id=7')), [])
            self.assertEqual(tenant.get('/api/billing/invoices/summary/').data['unpaid_invoices'], 1)
            self.assertEqual(len(tenant.get('/api/billing/invoices/debt/').data), 1)
        with patch_tenant_links(self.links):
            self.assertEqual(self.codes(jwt_client(5, 'TENANT').get('/api/billing/invoices/')), [])

    def test_tenant_service_down_fails_closed(self):
        with mock.patch('common.service_client.requests.get', side_effect=requests.exceptions.ConnectionError()):
            res = jwt_client(50, 'TENANT').get('/api/billing/invoices/')
        self.assertEqual(res.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        with mock.patch('common.service_client.requests.get', return_value=fake_http_response(200, self.links[50])):
            self.assertEqual(self.codes(jwt_client(50, 'TENANT').get('/api/billing/invoices/')), ['I-MINE'])

    def test_staff_is_not_admin(self):
        with patch_tenant_links({}):
            self.assertEqual(self.codes(jwt_client(300, 'STAFF').get('/api/billing/invoices/')), [])

    def test_business_endpoints_locked(self):
        payload = {'room_id': 1, 'tenant_id': 5, 'billing_month': 12, 'billing_year': 2026, 'room_fee': '1',
                   'due_date': str(timezone.localdate() + timedelta(days=5))}
        calls = [
            ('post', '/api/billing/invoices/', payload),
            ('patch', f'/api/billing/invoices/{self.mine.id}/', {'room_fee': '2'}),
            ('put', f'/api/billing/invoices/{self.mine.id}/', payload),
            ('delete', f'/api/billing/invoices/{self.mine.id}/', None),
            ('post', f'/api/billing/invoices/{self.mine.id}/pay/', {}),
            ('post', f'/api/billing/invoices/{self.mine.id}/cancel/', {}),
            ('post', '/api/notifications/', {'user_id': 50, 'title': 'x', 'content': 'y'}),
        ]
        for client in (jwt_client(10, 'LANDLORD'), jwt_client(1, 'ADMIN')):
            for method, url, data in calls:
                res = getattr(client, method)(url, data, format='json')
                self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN, (method, url))
        self.assertEqual(Invoice.objects.count(), 3)
        self.mine.refresh_from_db()
        self.assertEqual(self.mine.status, InvoiceStatus.UNPAID)
        self.assertEqual(Notification.objects.count(), 0)

    def test_own_notifications_still_readable(self):
        note = Notification.objects.create(user_id=50, title='t', content='c')
        Notification.objects.create(user_id=51, title='khác', content='c')
        tenant = jwt_client(50, 'TENANT')
        self.assertEqual([n['id'] for n in tenant.get('/api/notifications/').data], [note.id])
        self.assertEqual(tenant.post(f'/api/notifications/{note.id}/read/').status_code, status.HTTP_200_OK)
        other = Notification.objects.get(user_id=51)
        self.assertEqual(tenant.post(f'/api/notifications/{other.id}/read/').status_code, status.HTTP_404_NOT_FOUND)
