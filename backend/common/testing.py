"""Helper cho test của các service stateless: tạo JWT giống Identity Service phát hành."""
from unittest import mock

from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import AccessToken


def make_access_token(user_id, role, username=None, is_superuser=False):
    token = AccessToken()
    token['user_id'] = user_id
    token['username'] = username or f'user{user_id}'
    token['role'] = role
    token['is_superuser'] = is_superuser
    return str(token)


def jwt_client(user_id, role, **kwargs):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f'Bearer {make_access_token(user_id, role, **kwargs)}')
    return client


def tenant_link(tenant_id, user_id, room_id=None, landlord_id=None, status='ACTIVE'):
    """Một dòng của Tenant Service GET /api/tenants/links/."""
    return {'tenant_id': tenant_id, 'user_id': user_id, 'room_id': room_id,
            'landlord_id': landlord_id, 'status': status}


def patch_tenant_links(links_by_user_id):
    """
    Giả lập Tenant Service cho service 2/4/5: user_id (claim JWT) -> danh sách liên kết của người đó.
    User không có trong mapping -> [] (không có hồ sơ người thuê).
    """
    def fake(user):
        return list(links_by_user_id.get(int(user.id), []))
    return mock.patch('common.service_client.tenant_links_for_user', side_effect=fake)


def fake_http_response(status_code=200, json_body=None):
    resp = mock.Mock()
    resp.status_code = status_code
    if json_body is None:
        resp.json.side_effect = ValueError('no json')
    else:
        resp.json.return_value = json_body
    return resp
