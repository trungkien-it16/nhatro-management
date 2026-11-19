from unittest import mock

import requests
from django.test import TestCase
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient
from rest_framework import status
from rest_framework_simplejwt.tokens import AccessToken
from common.testing import fake_http_response, tenant_link
from services.identity_service.models import UserRole
from services.identity_service.serializers import CustomTokenObtainPairSerializer

User = get_user_model()

class IdentityServiceTests(TestCase):
    databases = {'default'}

    def setUp(self):
        self.client = APIClient()
        self.landlord = User.objects.create_user(
            username='testlandlord',
            password='testpassword123',
            email='landlord@test.com',
            role=UserRole.LANDLORD,
            first_name='An',
            last_name='Nguyen'
        )

    def test_login_success(self):
        """SPRINT 1: Test Login API & JWT Authentication"""
        response = self.client.post('/api/auth/login/', {
            'username': 'testlandlord',
            'password': 'testpassword123'
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)
        self.assertIn('user', response.data)
        self.assertEqual(response.data['user']['role'], UserRole.LANDLORD)

    def test_login_invalid_credentials(self):
        """SPRINT 1: Test Login thất bại khi sai mật khẩu"""
        response = self.client.post('/api/auth/login/', {
            'username': 'testlandlord',
            'password': 'wrongpassword'
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_role_authorization_and_me(self):
        """SPRINT 1: Test Role Authorization & Me endpoint"""
        self.client.force_authenticate(user=self.landlord)
        response = self.client.get('/api/auth/me/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['username'], 'testlandlord')
        self.assertEqual(response.data['role'], UserRole.LANDLORD)

    def _login(self):
        return self.client.post('/api/auth/login/', {
            'username': 'testlandlord', 'password': 'testpassword123'}, format='json').data

    def test_jwt_contains_role_claims_for_stateless_services(self):
        """Token phải mang role để service khác phân quyền không cần DB Identity"""
        token = AccessToken(self._login()['access'])
        self.assertEqual(token['role'], UserRole.LANDLORD)
        self.assertEqual(token['username'], 'testlandlord')
        self.assertFalse(token['is_superuser'])

    def test_logout_blacklists_refresh_token(self):
        data = self._login()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {data['access']}")
        res = self.client.post('/api/auth/logout/', {'refresh': data['refresh']}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        res = self.client.post('/api/auth/refresh/', {'refresh': data['refresh']}, format='json')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_change_password(self):
        self.client.force_authenticate(user=self.landlord)
        res = self.client.post('/api/auth/change-password/', {
            'old_password': 'wrong', 'new_password': 'newpass123'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        res = self.client.post('/api/auth/change-password/', {
            'old_password': 'testpassword123', 'new_password': 'newpass123'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.landlord.refresh_from_db()
        self.assertTrue(self.landlord.check_password('newpass123'))

    def test_public_register_cannot_create_admin(self):
        res = self.client.post('/api/auth/register/', {
            'username': 'hacker', 'password': 'abcdef12', 'role': UserRole.ADMIN}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_health(self):
        res = self.client.get('/health/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['status'], 'UP')
        self.assertEqual(res.data['port'], 8001)


class IdentityPermissionPolicyTests(TestCase):
    """Chống leo quyền: role / is_active chỉ ADMIN được thay đổi."""
    databases = {'default'}

    def setUp(self):
        self.admin = User.objects.create_user(username='admin_t', password='adminpass123', role=UserRole.ADMIN)
        self.landlord = User.objects.create_user(username='landlord_t', password='landlordpass123',
                                                 role=UserRole.LANDLORD)
        self.tenant = User.objects.create_user(username='tenant_t', password='tenantpass123', role=UserRole.TENANT)
        self.client = APIClient()
        # Tenant Service (giả lập): tenant_t là người thuê thuộc phạm vi của landlord_t.
        patcher = mock.patch('common.service_client.fetch_tenant_links',
                             return_value=[tenant_link(1, self.tenant.id, room_id=1, landlord_id=self.landlord.id)])
        patcher.start()
        self.addCleanup(patcher.stop)

    def as_user(self, user):
        self.client.force_authenticate(user=user)
        return self.client

    def test_user_cannot_escalate_own_role_or_activate_flag_via_me(self):
        client = self.as_user(self.tenant)
        res = client.patch('/api/auth/me/', {'role': UserRole.ADMIN, 'is_active': False,
                                             'username': 'renamed', 'phone_number': '0909'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.tenant.refresh_from_db()
        self.assertEqual(self.tenant.role, UserRole.TENANT)
        self.assertTrue(self.tenant.is_active)
        self.assertEqual(self.tenant.username, 'tenant_t')
        self.assertEqual(self.tenant.phone_number, '0909')

    def test_tenant_cannot_access_user_management(self):
        client = self.as_user(self.tenant)
        self.assertEqual(client.get('/api/users/').status_code, status.HTTP_403_FORBIDDEN)
        res = client.post('/api/users/', {'username': 'x', 'password': 'abcdef12', 'role': UserRole.ADMIN},
                          format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_landlord_can_only_create_tenant(self):
        client = self.as_user(self.landlord)
        res = client.post('/api/users/', {'username': 'evil', 'password': 'abcdef12', 'role': UserRole.ADMIN},
                          format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(User.objects.filter(username='evil').exists())
        res = client.post('/api/users/', {'username': 'newtenant', 'password': 'abcdef12'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        created = User.objects.get(username='newtenant')
        self.assertEqual(created.role, UserRole.TENANT)
        self.assertTrue(created.check_password('abcdef12'))
        self.assertNotIn('password', res.data)

    def test_landlord_cannot_change_role_or_deactivate(self):
        client = self.as_user(self.landlord)
        res = client.patch(f'/api/users/{self.tenant.id}/', {'role': UserRole.ADMIN}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        res = client.patch(f'/api/users/{self.tenant.id}/', {'is_active': False}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        res = client.patch(f'/api/users/{self.landlord.id}/', {'role': UserRole.ADMIN}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        # Không thấy / không sửa được tài khoản ADMIN
        res = client.patch(f'/api/users/{self.admin.id}/', {'first_name': 'x'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(client.delete(f'/api/users/{self.tenant.id}/').status_code, status.HTTP_403_FORBIDDEN)
        self.tenant.refresh_from_db()
        self.assertEqual(self.tenant.role, UserRole.TENANT)
        self.assertTrue(self.tenant.is_active)

    def test_admin_can_change_role_and_deactivate(self):
        client = self.as_user(self.admin)
        res = client.patch(f'/api/users/{self.tenant.id}/', {'role': UserRole.LANDLORD, 'is_active': False},
                           format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        self.tenant.refresh_from_db()
        self.assertEqual(self.tenant.role, UserRole.LANDLORD)
        self.assertFalse(self.tenant.is_active)
        self.assertEqual(client.delete(f'/api/users/{self.admin.id}/').status_code, status.HTTP_400_BAD_REQUEST)

    def test_public_register_cannot_create_staff_or_superuser(self):
        anon = APIClient()
        for role in (UserRole.ADMIN, UserRole.STAFF):
            res = anon.post('/api/auth/register/', {'username': f'r_{role}', 'password': 'abcdef12', 'role': role},
                            format='json')
            self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        res = anon.post('/api/auth/register/', {'username': 'r_ok', 'password': 'abcdef12',
                                                'is_superuser': True, 'is_staff': True}, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        user = User.objects.get(username='r_ok')
        self.assertFalse(user.is_superuser)
        self.assertFalse(user.is_staff)
        self.assertEqual(user.role, UserRole.LANDLORD)

    def test_test_accounts_endpoint_hidden_when_not_debug(self):
        from django.test import override_settings
        with override_settings(EXPOSE_TEST_ACCOUNTS=False):
            self.assertEqual(APIClient().get('/api/auth/test-users/').status_code, status.HTTP_404_NOT_FOUND)
        with override_settings(EXPOSE_TEST_ACCOUNTS=True):
            res = APIClient().get('/api/auth/test-users/')
            self.assertEqual(res.status_code, status.HTTP_200_OK)
            self.assertNotIn('ADMIN', [a['role'] for a in res.data['test_accounts']])


class PublicRegisterTests(TestCase):
    """Chặng 3 — Đăng ký công khai POST /api/auth/register/ (màn hình RegisterPage)."""
    databases = {'default'}
    URL = '/api/auth/register/'

    def setUp(self):
        self.client = APIClient()
        User.objects.create_user(username='dangco', password='abcdef12', email='dangco@test.vn')

    def _post(self, **data):
        return self.client.post(self.URL, data, format='json')

    def test_register_landlord_success_hashes_password(self):
        res = self._post(username='chumoi', password='abcdef12', email='chumoi@test.vn', first_name='Nguyễn Văn',
                         last_name='B', phone_number='0901234567', role=UserRole.LANDLORD)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        self.assertNotIn('password', res.data)
        user = User.objects.get(username='chumoi')
        self.assertEqual(user.role, UserRole.LANDLORD)
        self.assertNotEqual(user.password, 'abcdef12')
        self.assertTrue(user.check_password('abcdef12'))
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_superuser)
        self.assertEqual(user.phone_number, '0901234567')

    def test_register_tenant_success_and_can_login(self):
        res = self._post(username='khachmoi', password='abcdef12', role=UserRole.TENANT)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        self.assertEqual(User.objects.get(username='khachmoi').role, UserRole.TENANT)
        login = self.client.post('/api/auth/login/', {'username': 'khachmoi', 'password': 'abcdef12'}, format='json')
        self.assertEqual(login.status_code, status.HTTP_200_OK)
        self.assertEqual(login.data['user']['role'], UserRole.TENANT)

    def test_register_duplicate_username(self):
        res = self._post(username='dangco', password='abcdef12')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('username', res.data)
        self.assertEqual(User.objects.filter(username='dangco').count(), 1)

    def test_register_duplicate_email_case_insensitive(self):
        res = self._post(username='nguoikhac', password='abcdef12', email='DangCo@Test.vn')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('email', res.data)
        self.assertFalse(User.objects.filter(username='nguoikhac').exists())

    def test_register_without_email_allowed_multiple_times(self):
        for name in ('khongmail1', 'khongmail2'):
            self.assertEqual(self._post(username=name, password='abcdef12').status_code, status.HTTP_201_CREATED)

    def test_register_invalid_password_and_email(self):
        res = self._post(username='ngan', password='abc')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('password', res.data)
        res = self._post(username='saimail', password='abcdef12', email='khong-phai-email')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('email', res.data)
        self.assertFalse(User.objects.filter(username__in=['ngan', 'saimail']).exists())

    def test_register_admin_staff_rejected(self):
        for role in (UserRole.ADMIN, UserRole.STAFF):
            res = self._post(username=f'tu_{role.lower()}', password='abcdef12', role=role)
            self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
            self.assertIn('role', res.data)
        self.assertFalse(User.objects.filter(username__startswith='tu_').exists())


class IdentityRoleScopeTests(TestCase):
    """W1 (STAFF) + W2 (LANDLORD chỉ quản lý TENANT thuộc phạm vi nhà trọ của mình)."""
    databases = {'default'}

    def setUp(self):
        self.admin = User.objects.create_user(username='a1', password='adminpass123', role=UserRole.ADMIN)
        self.landlord = User.objects.create_user(username='l1', password='landlordpass1', role=UserRole.LANDLORD)
        self.other_landlord = User.objects.create_user(username='l2', password='landlordpass2', role=UserRole.LANDLORD)
        self.my_tenant = User.objects.create_user(username='t_mine', password='tenantpass1', role=UserRole.TENANT)
        self.other_tenant = User.objects.create_user(username='t_other', password='tenantpass2', role=UserRole.TENANT)
        self.moved_tenant = User.objects.create_user(username='t_moved', password='tenantpass3', role=UserRole.TENANT)
        self.staff = User.objects.create_user(username='s1', password='staffpass123', role=UserRole.STAFF)
        # Liên kết do Tenant Service trả về cho chủ trọ l1 (đã lọc theo landlord_id ở Tenant Service).
        self.links = [
            tenant_link(10, self.my_tenant.id, room_id=1, landlord_id=self.landlord.id),
            tenant_link(11, self.moved_tenant.id, room_id=2, landlord_id=self.landlord.id, status='MOVED_OUT'),
            # user_id trỏ tới LANDLORD khác: không bao giờ được coi là TENANT trong phạm vi.
            tenant_link(12, self.other_landlord.id, room_id=3, landlord_id=self.landlord.id),
        ]

    def bearer(self, user):
        client = APIClient()
        token = CustomTokenObtainPairSerializer.get_token(user).access_token
        client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        return client

    def test_landlord_lists_only_own_tenants_and_self(self):
        with mock.patch('common.service_client.requests.get',
                        return_value=fake_http_response(200, self.links)) as fake:
            res = self.bearer(self.landlord).get('/api/users/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(sorted(u['username'] for u in res.data), ['l1', 't_mine'])
        # Gọi đúng Tenant Service bằng JWT của chính chủ trọ (không dùng ID từ client).
        self.assertEqual(fake.call_args.args[0], 'http://127.0.0.1:8003/api/tenants/links/')
        self.assertTrue(fake.call_args.kwargs['headers']['Authorization'].startswith('Bearer '))

    def test_landlord_cannot_read_or_edit_tenant_out_of_scope(self):
        with mock.patch('common.service_client.requests.get', return_value=fake_http_response(200, self.links)):
            client = self.bearer(self.landlord)
            for user in (self.other_tenant, self.moved_tenant, self.other_landlord, self.admin, self.staff):
                self.assertEqual(client.get(f'/api/users/{user.id}/').status_code, status.HTTP_404_NOT_FOUND)
                res = client.patch(f'/api/users/{user.id}/', {'first_name': 'Hack'}, format='json')
                self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)
            res = client.patch(f'/api/users/{self.my_tenant.id}/', {'phone_number': '0911'}, format='json')
            self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        self.other_tenant.refresh_from_db()
        self.assertEqual(self.other_tenant.first_name, '')

    def test_tenant_service_down_fails_closed_503(self):
        with mock.patch('common.service_client.requests.get', side_effect=requests.exceptions.ConnectionError()):
            res = self.bearer(self.landlord).get('/api/users/')
        self.assertEqual(res.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        with mock.patch('common.service_client.requests.get', return_value=fake_http_response(500, None)):
            res = self.bearer(self.landlord).get(f'/api/users/{self.my_tenant.id}/')
        self.assertEqual(res.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)

    def test_admin_sees_whole_system_without_tenant_lookup(self):
        with mock.patch('common.service_client.requests.get') as fake:
            res = self.bearer(self.admin).get('/api/users/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), User.objects.count())
        fake.assert_not_called()

    def test_staff_has_no_admin_or_manager_rights(self):
        client = self.bearer(self.staff)
        self.assertEqual(client.get('/api/users/').status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(client.get(f'/api/users/{self.my_tenant.id}/').status_code, status.HTTP_403_FORBIDDEN)
        res = client.post('/api/users/', {'username': 'x', 'password': 'abcdef12', 'role': 'ADMIN'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(client.delete(f'/api/users/{self.my_tenant.id}/').status_code, status.HTTP_403_FORBIDDEN)
        # Không tự nâng quyền qua hồ sơ cá nhân.
        client.patch('/api/auth/me/', {'role': 'ADMIN', 'is_active': True}, format='json')
        self.staff.refresh_from_db()
        self.assertEqual(self.staff.role, UserRole.STAFF)

    def test_staff_role_cannot_be_newly_assigned(self):
        client = self.bearer(self.admin)
        res = client.post('/api/users/', {'username': 'new_s', 'password': 'abcdef12', 'role': 'STAFF'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        res = client.patch(f'/api/users/{self.my_tenant.id}/', {'role': 'STAFF'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        # Dữ liệu STAFF cũ vẫn giữ nguyên; ADMIN chuyển được STAFF sang vai trò chính thức.
        res = client.patch(f'/api/users/{self.staff.id}/', {'role': 'LANDLORD'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)

    def test_unauthenticated_401(self):
        self.assertEqual(APIClient().get('/api/users/').status_code, status.HTTP_401_UNAUTHORIZED)

    def test_tenant_link_eligibility_only_boolean_for_active_tenant(self):
        inactive = User.objects.create_user(username='t_off', password='tenantpass4', role=UserRole.TENANT,
                                            is_active=False)
        expected = {self.other_tenant.id: True, self.my_tenant.id: True, inactive.id: False,
                    self.admin.id: False, self.landlord.id: False, self.other_landlord.id: False,
                    self.staff.id: False, 999999: False}
        for caller in (self.admin, self.landlord):
            client = self.bearer(caller)
            with mock.patch('common.service_client.requests.get') as fake:
                for uid, ok in expected.items():
                    res = client.get(f'/api/users/{uid}/tenant-link-eligibility/')
                    self.assertEqual(res.status_code, status.HTTP_200_OK)
                    self.assertEqual(res.data, {'user_id': uid, 'eligible': ok})  # không lộ username/role
            fake.assert_not_called()
        for caller in (self.my_tenant, self.staff):
            res = self.bearer(caller).get(f'/api/users/{self.other_tenant.id}/tenant-link-eligibility/')
            self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
        res = APIClient().get(f'/api/users/{self.other_tenant.id}/tenant-link-eligibility/')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

