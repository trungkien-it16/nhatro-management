from unittest import mock

import requests
from django.test import TestCase, override_settings
from rest_framework import status
from rest_framework.test import APIClient

from common.testing import fake_http_response, jwt_client, patch_tenant_links, tenant_link
from services.property_service.models import (
    MaintenanceHistory, MaintenanceRequest, MaintenanceStatus, Property, PropertyStatus, Room, RoomStatus,
)

LANDLORD_ID = 101


class PropertyServiceTests(TestCase):
    """
    Service chạy độc lập: KHÔNG import model User của Identity Service.
    Xác thực bằng JWT có claims (user_id, role) như Identity Service phát hành.
    """

    def setUp(self):
        self.client = jwt_client(LANDLORD_ID, 'LANDLORD')
        self.property = Property.objects.create(
            code='NT100',
            owner_id=LANDLORD_ID,
            name='Nhà trọ Thử Nghiệm',
            address='123 Đường Nguyễn Gia Trí',
            ward='Phường 25',
            district='Bình Thạnh',
            city='TP. Hồ Chí Minh',
            total_floors=2,
            status=PropertyStatus.ACTIVE,
        )
        self.room = Room.objects.create(
            code='NT100-A01',
            property=self.property,
            room_number='101',
            floor=1,
            area=20.0,
            rent_price=3000000,
            deposit_amount=3000000,
            max_occupants=2,
            status=RoomStatus.AVAILABLE,
        )

    # ------------------------------------------------------------------ PROPERTY
    def test_view_property_list(self):
        response = self.client.get('/api/properties/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)

    def test_create_property_assigns_owner_and_code(self):
        response = self.client.post('/api/properties/', {
            'name': 'Nhà trọ Mới Tạo', 'address': '456 Phố Mới', 'district': 'Quận 7',
            'owner_id': 999,  # bị bỏ qua: owner lấy từ JWT
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        self.assertEqual(response.data['owner_id'], LANDLORD_ID)
        self.assertTrue(response.data['code'].startswith('NT'))

    def test_update_property(self):
        response = self.client.patch(f'/api/properties/{self.property.id}/',
                                     {'name': 'Nhà trọ Đã Sửa Tên', 'total_floors': 4}, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.property.refresh_from_db()
        self.assertEqual(self.property.name, 'Nhà trọ Đã Sửa Tên')

    def test_search_and_filter_property(self):
        res = self.client.get('/api/properties/?search=Thử Nghiệm&status=ACTIVE')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 1)
        res = self.client.get('/api/properties/?district=Quận 9')
        self.assertEqual(len(res.data), 0)

    def test_delete_property_hard_when_empty_soft_when_has_rooms(self):
        empty = Property.objects.create(owner_id=LANDLORD_ID, name='Nhà trọ Cần Xóa', address='789')
        res = self.client.delete(f'/api/properties/{empty.id}/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertFalse(res.data['soft_deleted'])
        self.assertFalse(Property.objects.filter(id=empty.id).exists())

        res = self.client.delete(f'/api/properties/{self.property.id}/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.data['soft_deleted'])
        self.property.refresh_from_db()
        self.assertEqual(self.property.status, PropertyStatus.DELETED)
        # Nhà trọ đã xóa mềm không hiện trong danh sách mặc định
        self.assertEqual(len(self.client.get('/api/properties/').data), 0)

    def test_cannot_delete_property_with_rented_rooms(self):
        self.room.status = RoomStatus.OCCUPIED
        self.room.current_occupants = 1
        self.room.save()
        res = self.client.delete(f'/api/properties/{self.property.id}/')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_property_update_status_and_stats(self):
        res = self.client.post(f'/api/properties/{self.property.id}/update_status/', {'status': 'INACTIVE'},
                               format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        res = self.client.get(f'/api/properties/{self.property.id}/stats/')
        self.assertEqual(res.data['total_rooms'], 1)
        self.assertEqual(res.data['available_rooms'], 1)
        res = self.client.get(f'/api/properties/{self.property.id}/room_matrix/')
        self.assertEqual(res.data['floors'][0]['floor_name'], 'Tầng 1')

    def test_landlord_cannot_see_or_edit_other_landlord_property(self):
        other = Property.objects.create(owner_id=999, name='Khác', address='Z')
        self.assertEqual(self.client.get(f'/api/properties/{other.id}/').status_code, status.HTTP_404_NOT_FOUND)
        res = self.client.patch(f'/api/properties/{other.id}/', {'name': 'Hack'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_tenant_cannot_create_or_delete_property(self):
        tenant = jwt_client(555, 'TENANT')
        res = tenant.post('/api/properties/', {'name': 'X', 'address': 'Y'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
        res = tenant.delete(f'/api/properties/{self.property.id}/')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    # ------------------------------------------------------------------ ROOM
    def test_view_room_list(self):
        response = self.client.get(f'/api/rooms/?property_id={self.property.id}')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['room_number'], '101')

    def test_create_and_update_room(self):
        res = self.client.post('/api/rooms/', {
            'property': self.property.id, 'room_number': '102', 'floor': 1, 'area': 22.0,
            'rent_price': 3500000, 'max_occupants': 2,
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        self.assertEqual(res.data['code'], 'NT100-102')
        res = self.client.patch(f'/api/rooms/{self.room.id}/', {'room_number': '101-VIP', 'area': 25}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.room.refresh_from_db()
        self.assertEqual(self.room.room_number, '101-VIP')

    def test_landlord_cannot_add_room_to_other_property(self):
        other = Property.objects.create(owner_id=999, name='Khác', address='Z')
        res = self.client.post('/api/rooms/', {
            'property': other.id, 'room_number': 'X1', 'rent_price': 1000000}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_room_status_check_rentable_and_lists(self):
        res = self.client.get(f'/api/rooms/{self.room.id}/check_rentable/')
        self.assertTrue(res.data['can_rent'])

        res = self.client.patch(f'/api/rooms/{self.room.id}/status/', {'status': 'OCCUPIED'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.room.refresh_from_db()
        self.assertEqual(self.room.status, RoomStatus.OCCUPIED)
        self.assertEqual(self.room.current_occupants, 1)

        res = self.client.post(f'/api/rooms/{self.room.id}/status/', {'status': 'OCCUPIED', 'current_occupants': 2},
                               format='json')
        self.room.refresh_from_db()
        self.assertEqual(self.room.status, RoomStatus.FULL)
        self.assertEqual(len(self.client.get('/api/rooms/occupied/').data), 1)
        self.assertEqual(len(self.client.get('/api/rooms/available/').data), 0)

        res = self.client.post(f'/api/rooms/{self.room.id}/status/', {'status': 'OCCUPIED', 'current_occupants': 9},
                               format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        res = self.client.post(f'/api/rooms/{self.room.id}/status/', {'status': 'BOGUS'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_room_search_filter_sort(self):
        Room.objects.create(property=self.property, room_number='201', floor=2, area=30, rent_price=5000000)
        res = self.client.get('/api/rooms/?min_price=4000000')
        self.assertEqual([r['room_number'] for r in res.data], ['201'])
        res = self.client.get('/api/rooms/?max_price=3500000')
        self.assertEqual([r['room_number'] for r in res.data], ['101'])
        res = self.client.get('/api/rooms/?min_area=25&max_area=35')
        self.assertEqual([r['room_number'] for r in res.data], ['201'])
        res = self.client.get('/api/rooms/?sort=price_desc')
        self.assertEqual([r['room_number'] for r in res.data], ['201', '101'])
        res = self.client.get('/api/rooms/?search=Thử Nghiệm&max_occupants=2')
        self.assertEqual(len(res.data), 2)
        self.assertEqual(self.client.get('/api/rooms/?min_price=abc').status_code, status.HTTP_400_BAD_REQUEST)

    def test_occupants_validation(self):
        res = self.client.patch(f'/api/rooms/{self.room.id}/', {'current_occupants': 5}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_delete_room_hard_and_soft(self):
        res = self.client.delete(f'/api/rooms/{self.room.id}/')
        self.assertFalse(res.data['soft_deleted'])
        room = Room.objects.create(property=self.property, room_number='202', rent_price=1)
        MaintenanceRequest.objects.create(room=room, title='t')
        res = self.client.delete(f'/api/rooms/{room.id}/')
        self.assertTrue(res.data['soft_deleted'])
        room.refresh_from_db()
        self.assertEqual(room.status, RoomStatus.INACTIVE)

    def test_tenant_does_not_see_occupant_personal_info(self):
        self.room.tenant_name = 'Nguyễn Văn A'
        self.room.tenant_phone = '0900000000'
        self.room.save()
        # TENANT 555 đang thuê phòng này (liên kết lấy từ Tenant Service).
        with patch_tenant_links({555: [tenant_link(1, 555, room_id=self.room.id, landlord_id=LANDLORD_ID)]}):
            res = jwt_client(555, 'TENANT').get(f'/api/rooms/{self.room.id}/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertNotIn('tenant_phone', res.data)
        self.assertNotIn('tenant_name', res.data)
        res = self.client.get(f'/api/rooms/{self.room.id}/')
        self.assertEqual(res.data['tenant_phone'], '0900000000')

    # ------------------------------------------------------------------ MAINTENANCE
    @override_settings(SPRINT_FEATURE_LOCK=False)  # source nghiệp vụ bảo trì giữ cho Sprint sau
    def test_maintenance_workflow_and_history(self):
        res = self.client.post('/api/maintenance/', {
            'room': self.room.id, 'title': 'Phòng 101 hỏng điều hòa', 'estimated_cost': 500000,
            'priority': 'HIGH',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        maint_id = res.data['id']
        self.assertEqual(res.data['reported_by_id'], LANDLORD_ID)
        self.room.refresh_from_db()
        self.assertEqual(self.room.status, RoomStatus.MAINTENANCE)

        res = self.client.post(f'/api/maintenance/{maint_id}/update_status/', {'status': 'IN_PROGRESS'},
                               format='json')
        self.assertEqual(res.data['maintenance_request']['status'], MaintenanceStatus.IN_PROGRESS)

        res = self.client.post(f'/api/maintenance/{maint_id}/record_cost/',
                               {'estimated_cost': 500000, 'actual_cost': 450000}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        res = self.client.post(f'/api/maintenance/{maint_id}/complete/',
                               {'repair_info': 'Đã sửa xong điều hòa'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['maintenance_request']['status'], MaintenanceStatus.COMPLETED)
        self.room.refresh_from_db()
        self.assertEqual(self.room.status, RoomStatus.AVAILABLE)  # khôi phục trạng thái trước bảo trì

        # Không thể hủy yêu cầu đã hoàn thành
        res = self.client.post(f'/api/maintenance/{maint_id}/cancel/')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

        res = self.client.get('/api/maintenance-history/')
        self.assertGreaterEqual(len(res.data), 4)
        res = self.client.get(f'/api/maintenance/{maint_id}/history/')
        self.assertGreaterEqual(len(res.data), 4)

    @override_settings(SPRINT_FEATURE_LOCK=False)  # source nghiệp vụ bảo trì giữ cho Sprint sau
    def test_maintenance_start_complete_restores_previous_status(self):
        self.room.status = RoomStatus.OCCUPIED
        self.room.current_occupants = 1
        self.room.save()
        res = self.client.post('/api/maintenance/', {
            'room': self.room.id, 'title': 'Hỏng máy lạnh', 'mark_room_maintenance': True}, format='json')
        req_id = res.data['id']
        self.room.refresh_from_db()
        self.assertEqual(self.room.status, RoomStatus.MAINTENANCE)
        res = self.client.post(f'/api/maintenance/{req_id}/start/', {'assigned_to': 'Thợ A'}, format='json')
        self.assertEqual(res.data['maintenance_request']['technician_name'], 'Thợ A')
        res = self.client.post(f'/api/maintenance/{req_id}/complete/', {'cost': '350000'}, format='json')
        self.assertEqual(res.data['maintenance_request']['actual_cost'], '350000')
        self.room.refresh_from_db()
        self.assertEqual(self.room.status, RoomStatus.OCCUPIED)

    @override_settings(SPRINT_FEATURE_LOCK=False)  # source nghiệp vụ bảo trì giữ cho Sprint sau
    def test_create_maintenance_without_locking_room(self):
        res = self.client.post('/api/maintenance/', {
            'room': self.room.id, 'title': 'Thay bóng đèn', 'set_room_maintenance': False}, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.room.refresh_from_db()
        self.assertEqual(self.room.status, RoomStatus.AVAILABLE)

    @override_settings(SPRINT_FEATURE_LOCK=False)  # source nghiệp vụ bảo trì giữ cho Sprint sau
    def test_tenant_can_report_but_not_manage_maintenance(self):
        patcher = patch_tenant_links({777: [tenant_link(1, 777, room_id=self.room.id, landlord_id=LANDLORD_ID)]})
        patcher.start()
        self.addCleanup(patcher.stop)
        tenant = jwt_client(777, 'TENANT')
        res = tenant.post('/api/maintenance/', {'room': self.room.id, 'title': 'Rò nước'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        req_id = res.data['id']
        self.room.refresh_from_db()
        self.assertEqual(self.room.status, RoomStatus.AVAILABLE)  # TENANT không khóa được phòng
        for path in ('complete', 'start', 'record_cost', 'update_status'):
            res = tenant.post(f'/api/maintenance/{req_id}/{path}/', {'status': 'COMPLETED'}, format='json')
            self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN, path)
        self.assertEqual(len(tenant.get('/api/maintenance/').data), 1)
        self.assertEqual(len(jwt_client(778, 'TENANT').get('/api/maintenance/').data), 0)
        self.assertEqual(len(jwt_client(778, 'TENANT').get('/api/maintenance-history/').data), 0)
        res = tenant.post(f'/api/maintenance/{req_id}/cancel/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)

    @override_settings(SPRINT_FEATURE_LOCK=False)  # source nghiệp vụ bảo trì giữ cho Sprint sau
    def test_landlord_cannot_see_other_landlord_maintenance(self):
        other = Property.objects.create(owner_id=999, name='Khác', address='Z')
        other_room = Room.objects.create(property=other, room_number='1', rent_price=1)
        req = MaintenanceRequest.objects.create(room=other_room, title='x')
        MaintenanceHistory.objects.create(maintenance_request=req, room=other_room, action='a')
        self.assertEqual(len(self.client.get('/api/maintenance/').data), 0)
        self.assertEqual(len(self.client.get('/api/maintenance-history/').data), 0)
        res = self.client.post('/api/maintenance/', {'room': other_room.id, 'title': 'x'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    # ------------------------------------------------------------------ SUMMARY / HEALTH
    def test_summary_is_scoped_to_landlord(self):
        other = Property.objects.create(owner_id=999, name='Khác', address='Z')
        Room.objects.create(property=other, room_number='1', rent_price=1, status=RoomStatus.OCCUPIED)
        Room.objects.create(property=self.property, room_number='102', rent_price=1, status=RoomStatus.OCCUPIED)
        Room.objects.create(property=self.property, room_number='103', rent_price=1, status=RoomStatus.FULL)
        MaintenanceRequest.objects.create(room=self.room, title='t')
        res = self.client.get('/api/properties/summary/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['total_properties'], 1)
        self.assertEqual(res.data['total_rooms'], 3)
        self.assertEqual(res.data['occupied_rooms'], 2)
        self.assertEqual(res.data['full_rooms'], 1)
        self.assertEqual(res.data['available_rooms'], 1)
        self.assertEqual(res.data['open_maintenance_requests'], 1)

    def test_unauthenticated_rejected_and_health_public(self):
        anon = APIClient()
        self.assertEqual(anon.get('/api/properties/').status_code, status.HTTP_401_UNAUTHORIZED)
        res = anon.get('/health/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['port'], 8002)


class PropertyRoleScopeTests(TestCase):
    """W3: TENANT chỉ xem phòng mình đang thuê; ADMIN toàn hệ thống; LANDLORD chỉ dữ liệu của mình; STAFF hẹp nhất."""
    LANDLORD_A, LANDLORD_B, TENANT_ID = 101, 202, 555

    def setUp(self):
        self.p1 = Property.objects.create(code='PA', owner_id=self.LANDLORD_A, name='Nhà A', address='A')
        self.p2 = Property.objects.create(code='PB', owner_id=self.LANDLORD_B, name='Nhà B', address='B')
        self.r1 = Room.objects.create(code='PA-1', property=self.p1, room_number='1', rent_price=1000,
                                      status=RoomStatus.OCCUPIED, current_occupants=1, max_occupants=2)
        self.r2 = Room.objects.create(code='PA-2', property=self.p1, room_number='2', rent_price=1000,
                                      status=RoomStatus.AVAILABLE)
        self.r3 = Room.objects.create(code='PB-1', property=self.p2, room_number='1', rent_price=1000,
                                      status=RoomStatus.AVAILABLE)
        self.links = {self.TENANT_ID: [tenant_link(7, self.TENANT_ID, room_id=self.r1.id,
                                                   landlord_id=self.LANDLORD_A)]}

    def ids(self, res):
        self.assertEqual(res.status_code, status.HTTP_200_OK, getattr(res, 'data', None))
        return sorted(item['id'] for item in res.data)

    def test_admin_sees_whole_system(self):
        admin = jwt_client(1, 'ADMIN')
        self.assertEqual(self.ids(admin.get('/api/properties/')), sorted([self.p1.id, self.p2.id]))
        self.assertEqual(self.ids(admin.get('/api/rooms/')), sorted([self.r1.id, self.r2.id, self.r3.id]))

    def test_landlord_isolated_from_other_landlord(self):
        a = jwt_client(self.LANDLORD_A, 'LANDLORD')
        self.assertEqual(self.ids(a.get('/api/properties/')), [self.p1.id])
        self.assertEqual(self.ids(a.get('/api/rooms/')), sorted([self.r1.id, self.r2.id]))
        self.assertEqual(a.get(f'/api/properties/{self.p2.id}/').status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(a.get(f'/api/rooms/{self.r3.id}/').status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(a.patch(f'/api/rooms/{self.r3.id}/', {'rent_price': 1}, format='json').status_code,
                         status.HTTP_404_NOT_FOUND)
        self.assertEqual(a.delete(f'/api/properties/{self.p2.id}/').status_code, status.HTTP_404_NOT_FOUND)
        res = a.post('/api/rooms/', {'property': self.p2.id, 'room_number': '9', 'rent_price': 1}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.ids(a.get(f'/api/rooms/?property_id={self.p2.id}')), [])

    def test_tenant_sees_only_rented_room(self):
        tenant = jwt_client(self.TENANT_ID, 'TENANT')
        with patch_tenant_links(self.links):
            self.assertEqual(self.ids(tenant.get('/api/rooms/')), [self.r1.id])
            self.assertEqual(self.ids(tenant.get('/api/properties/')), [self.p1.id])
            self.assertEqual(tenant.get(f'/api/rooms/{self.r1.id}/').status_code, status.HTTP_200_OK)
            # Phòng khác cùng nhà / nhà khác: không lộ, kể cả khi đổi ID trên URL hoặc tham số lọc.
            for room in (self.r2, self.r3):
                self.assertEqual(tenant.get(f'/api/rooms/{room.id}/').status_code, status.HTTP_404_NOT_FOUND)
            self.assertEqual(tenant.get(f'/api/properties/{self.p2.id}/').status_code, status.HTTP_404_NOT_FOUND)
            self.assertEqual(self.ids(tenant.get(f'/api/rooms/?property_id={self.p2.id}')), [])
            self.assertEqual(self.ids(tenant.get('/api/rooms/available/')), [])
            summary = tenant.get('/api/properties/summary/').data
            self.assertEqual((summary['total_properties'], summary['total_rooms']), (1, 1))
            self.assertNotIn('estimated_monthly_revenue', summary)
            # Thống kê doanh thu nhà trọ chỉ dành cho quản lý.
            self.assertEqual(tenant.get(f'/api/properties/{self.p1.id}/stats/').status_code,
                             status.HTTP_403_FORBIDDEN)

    def test_tenant_cannot_write_property_or_room(self):
        tenant = jwt_client(self.TENANT_ID, 'TENANT')
        with patch_tenant_links(self.links):
            self.assertEqual(tenant.post('/api/properties/', {'name': 'X', 'address': 'Y'}, format='json')
                             .status_code, status.HTTP_403_FORBIDDEN)
            self.assertEqual(tenant.post('/api/rooms/', {'property': self.p1.id, 'room_number': 'X'}, format='json')
                             .status_code, status.HTTP_403_FORBIDDEN)
            self.assertEqual(tenant.patch(f'/api/rooms/{self.r1.id}/', {'rent_price': 1}, format='json')
                             .status_code, status.HTTP_403_FORBIDDEN)
            self.assertEqual(tenant.delete(f'/api/rooms/{self.r1.id}/').status_code, status.HTTP_403_FORBIDDEN)
            self.assertEqual(tenant.patch(f'/api/rooms/{self.r1.id}/status/', {'status': 'AVAILABLE'}, format='json')
                             .status_code, status.HTTP_403_FORBIDDEN)
        self.r1.refresh_from_db()
        self.assertEqual(self.r1.status, RoomStatus.OCCUPIED)

    def test_tenant_without_active_link_sees_nothing(self):
        moved = {self.TENANT_ID: [tenant_link(7, self.TENANT_ID, room_id=self.r1.id, status='MOVED_OUT')]}
        tenant = jwt_client(self.TENANT_ID, 'TENANT')
        for links in (moved, {}):
            with patch_tenant_links(links):
                self.assertEqual(self.ids(tenant.get('/api/rooms/')), [])
                self.assertEqual(self.ids(tenant.get('/api/properties/')), [])
                self.assertEqual(tenant.get(f'/api/rooms/{self.r1.id}/').status_code, status.HTTP_404_NOT_FOUND)

    def test_staff_is_not_admin(self):
        staff = jwt_client(300, 'STAFF')
        with patch_tenant_links({}):
            self.assertEqual(self.ids(staff.get('/api/properties/')), [])
            self.assertEqual(self.ids(staff.get('/api/rooms/')), [])
            self.assertEqual(staff.post('/api/properties/', {'name': 'X', 'address': 'Y'}, format='json')
                             .status_code, status.HTTP_403_FORBIDDEN)
            self.assertEqual(staff.get(f'/api/properties/{self.p1.id}/stats/').status_code,
                             status.HTTP_403_FORBIDDEN)

    def test_tenant_lookup_uses_tenant_service_with_own_jwt(self):
        tenant = jwt_client(self.TENANT_ID, 'TENANT')
        body = self.links[self.TENANT_ID]
        with mock.patch('common.service_client.requests.get', return_value=fake_http_response(200, body)) as fake:
            self.assertEqual(self.ids(tenant.get('/api/rooms/')), [self.r1.id])
        self.assertEqual(fake.call_count, 1)
        self.assertEqual(fake.call_args.args[0], 'http://127.0.0.1:8003/api/tenants/links/')
        self.assertTrue(fake.call_args.kwargs['headers']['Authorization'].startswith('Bearer '))

    def test_tenant_service_down_fails_closed(self):
        tenant = jwt_client(self.TENANT_ID, 'TENANT')
        with mock.patch('common.service_client.requests.get', side_effect=requests.exceptions.ConnectionError()):
            self.assertEqual(tenant.get('/api/rooms/').status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        with mock.patch('common.service_client.requests.get', return_value=fake_http_response(200, {'bad': 1})):
            self.assertEqual(tenant.get('/api/properties/').status_code, status.HTTP_503_SERVICE_UNAVAILABLE)



class MaintenanceSprintLockTests(TestCase):
    """D2: API ghi nghiệp vụ bảo trì bị khóa ở backend; GET vẫn hoạt động theo phạm vi."""

    def setUp(self):
        self.prop = Property.objects.create(code='PM', owner_id=LANDLORD_ID, name='Nhà M', address='M')
        self.room = Room.objects.create(code='PM-1', property=self.prop, room_number='1', rent_price=1,
                                        status=RoomStatus.AVAILABLE)
        self.req = MaintenanceRequest.objects.create(room=self.room, title='Hỏng đèn', reported_by_id=555)

    def test_write_endpoints_locked_for_every_role(self):
        landlord, admin = jwt_client(LANDLORD_ID, 'LANDLORD'), jwt_client(1, 'ADMIN')
        tenant = jwt_client(555, 'TENANT')
        rid = self.req.id
        calls = [
            ('post', '/api/maintenance/', {'room': self.room.id, 'title': 'x'}),
            ('patch', f'/api/maintenance/{rid}/', {'title': 'y'}),
            ('put', f'/api/maintenance/{rid}/', {'room': self.room.id, 'title': 'y'}),
            ('delete', f'/api/maintenance/{rid}/', None),
            ('post', f'/api/maintenance/{rid}/update_status/', {'status': 'IN_PROGRESS'}),
            ('post', f'/api/maintenance/{rid}/start/', {}),
            ('post', f'/api/maintenance/{rid}/record_cost/', {'actual_cost': '1'}),
            ('post', f'/api/maintenance/{rid}/complete/', {}),
            ('post', f'/api/maintenance/{rid}/cancel/', {}),
        ]
        with patch_tenant_links({555: [tenant_link(1, 555, room_id=self.room.id, landlord_id=LANDLORD_ID)]}):
            for client in (landlord, admin, tenant):
                for method, url, data in calls:
                    res = getattr(client, method)(url, data, format='json')
                    self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN, (method, url))
        self.req.refresh_from_db()
        self.assertEqual(self.req.status, MaintenanceStatus.PENDING)
        self.assertEqual(MaintenanceRequest.objects.count(), 1)
        self.room.refresh_from_db()
        self.assertEqual(self.room.status, RoomStatus.AVAILABLE)
        self.assertEqual(APIClient().post('/api/maintenance/', {}, format='json').status_code,
                         status.HTTP_401_UNAUTHORIZED)

    def test_read_endpoints_still_work_and_are_scoped(self):
        landlord = jwt_client(LANDLORD_ID, 'LANDLORD')
        self.assertEqual(len(landlord.get('/api/maintenance/').data), 1)
        self.assertEqual(landlord.get(f'/api/maintenance/{self.req.id}/').status_code, status.HTTP_200_OK)
        self.assertEqual(landlord.get(f'/api/maintenance/{self.req.id}/history/').status_code, status.HTTP_200_OK)
        self.assertEqual(landlord.get('/api/maintenance-history/').status_code, status.HTTP_200_OK)
        other = jwt_client(999, 'LANDLORD')
        self.assertEqual(other.get(f'/api/maintenance/{self.req.id}/').status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(len(jwt_client(555, 'TENANT').get('/api/maintenance/').data), 1)
        self.assertEqual(len(jwt_client(556, 'TENANT').get('/api/maintenance/').data), 0)

    def test_room_status_management_is_not_locked(self):
        # Quản lý trạng thái phòng là chức năng Sprint 1 — không bị khóa cùng bảo trì.
        res = jwt_client(LANDLORD_ID, 'LANDLORD').patch(f'/api/rooms/{self.room.id}/status/',
                                                        {'status': 'MAINTENANCE'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
