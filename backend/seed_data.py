"""
Nạp dữ liệu mẫu vào database RIÊNG của từng service (môi trường DEV).

Script dùng TOOLBOX settings (config.settings) để ghi lần lượt vào 5 database
qua ServiceDatabaseRouter. Liên kết giữa các service chỉ là ID (owner_id, room_id,
tenant_id...), không có Foreign Key chéo. Runtime KHÔNG dùng cách truy cập này —
mỗi service chỉ đọc/ghi database của chính nó.

Chạy sau khi đã migrate: python run_all_services.py --migrate (hoặc migrate từng service).
Mật khẩu tài khoản mẫu chỉ dùng cho dev; có thể đổi bằng biến môi trường
SEED_ADMIN_PASSWORD / SEED_LANDLORD_PASSWORD / SEED_TENANT_PASSWORD.
"""
import os
import sys
import django
from datetime import timedelta

# Console Windows (cp1252) không in được emoji/tiếng Việt khi stdout bị chuyển hướng.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, 'reconfigure'):
        _stream.reconfigure(encoding='utf-8', errors='replace')

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth import get_user_model  # noqa: E402
from django.utils import timezone  # noqa: E402
from services.billing_notification_service.models import Invoice, InvoiceStatus, Notification  # noqa: E402
from services.contract_service.models import Contract, ContractEvent, ContractStatus  # noqa: E402
from services.identity_service.models import UserRole  # noqa: E402
from services.tenant_service.models import RentalHistory, TenantProfile, TenantStatus  # noqa: E402
from services.property_service.models import (  # noqa: E402
    Property,
    PropertyStatus,
    Room,
    RoomStatus,
    RoomType,
    MaintenanceRequest,
    MaintenanceStatus,
    MaintenancePriority,
    MaintenanceHistory,
)

User = get_user_model()

ADMIN_PASSWORD = os.getenv('SEED_ADMIN_PASSWORD', 'adminpassword123')
LANDLORD_PASSWORD = os.getenv('SEED_LANDLORD_PASSWORD', 'chutropassword123')
TENANT_PASSWORD = os.getenv('SEED_TENANT_PASSWORD', 'khachpassword123')


def seed():
    print("=" * 65)
    print("🚀 SEEDING DATA SOA — 5 SERVICES")
    print("=" * 65)

    # 1. Identity Service (nhatro_identity_db)
    print("\n[1/5] Seeding Identity Service (nhatro_identity_db)...")
    admin_user, _ = User.objects.using('default').get_or_create(
        username='admin',
        defaults={
            'email': 'admin@nhatro.vn',
            'first_name': 'Hệ Thống',
            'last_name': 'Admin',
            'role': UserRole.ADMIN,
            'is_staff': True,
            'is_superuser': True,
            'phone_number': '0900000001',
            'identity_card': '079090000001',
            'address': 'Quận 1, TP. Hồ Chí Minh',
        },
    )
    admin_user.set_password(ADMIN_PASSWORD)
    admin_user.save(using='default')

    landlord, _ = User.objects.using('default').get_or_create(
        username='chutro1',
        defaults={
            'email': 'chutro1@nhatro.vn',
            'first_name': 'Nguyễn Văn',
            'last_name': 'An',
            'role': UserRole.LANDLORD,
            'phone_number': '0901234567',
            'identity_card': '079092001122',
            'address': '123 Đường D2, P. 25, Q. Bình Thạnh, TP.HCM',
        },
    )
    landlord.set_password(LANDLORD_PASSWORD)
    landlord.save(using='default')

    tenant, _ = User.objects.using('default').get_or_create(
        username='khach1',
        defaults={
            'email': 'khach1@gmail.com',
            'first_name': 'Trần Thị',
            'last_name': 'Mai',
            'role': UserRole.TENANT,
            'phone_number': '0912345678',
            'identity_card': '079198003344',
            'address': 'Tiền Giang',
        },
    )
    tenant.set_password(TENANT_PASSWORD)
    tenant.save(using='default')

    # 2. Property & Maintenance Service (nhatro_property_db)
    print("\n[2/5] Seeding Property & Maintenance Service (nhatro_property_db)...")
    prop1, _ = Property.objects.using('property_db').update_or_create(
        code='NT001',
        defaults={
            'name': 'Nhà trọ Hoa Mai - Bình Thạnh',
            'owner_id': landlord.id,
            'address': '45/12 Đường Nguyễn Gia Trí',
            'ward': 'Phường 25',
            'district': 'Bình Thạnh',
            'city': 'TP. Hồ Chí Minh',
            'total_floors': 3,
            'electricity_rate': 3800,
            'water_rate': 25000,
            'internet_rate': 100000,
            'status': PropertyStatus.ACTIVE,
            'description': 'Nhà trọ sinh viên & nhân viên văn phòng gần ĐH Hutech, Ngoại Thương, khóa vân tay, camera 24/7.',
            'rules': '- Không tụ tập ồn ào sau 23h\n- Giữ gìn vệ sinh khu vực chung',
        },
    )

    prop2, _ = Property.objects.using('property_db').update_or_create(
        code='NT002',
        defaults={
            'name': 'Căn hộ Mini Happy House - Quận 7',
            'owner_id': landlord.id,
            'address': '88 Đường số 7, KDC Tân Quy Đông',
            'ward': 'Tân Phong',
            'district': 'Quận 7',
            'city': 'TP. Hồ Chí Minh',
            'total_floors': 4,
            'electricity_rate': 4000,
            'water_rate': 30000,
            'internet_rate': 120000,
            'status': PropertyStatus.ACTIVE,
            'description': 'Căn hộ mini cao cấp full nội thất, thang máy, hầm để xe rộng rãi.',
            'rules': '- Để xe đúng vị trí quy định\n- Báo trước khi có khách ở qua đêm',
        },
    )

    prop3, _ = Property.objects.using('property_db').update_or_create(
        code='NT003',
        defaults={
            'name': 'Khu trọ Ánh Dương - Thủ Đức',
            'owner_id': landlord.id,
            'address': '19 Đường Hoàng Diệu 2',
            'ward': 'Linh Chiểu',
            'district': 'TP. Thủ Đức',
            'city': 'TP. Hồ Chí Minh',
            'total_floors': 2,
            'electricity_rate': 3500,
            'water_rate': 20000,
            'internet_rate': 80000,
            'status': PropertyStatus.INACTIVE,
            'description': 'Khu nhà trọ đang tạm ngưng nhận khách mới để nâng cấp hệ thống PCCC.',
            'rules': '- Tuân thủ quy định PCCC',
        },
    )

    rooms_seed = [
        # Nhà trọ NT001
        {
            'code': 'NT001-A01', 'property': prop1, 'room_number': 'Phòng A01', 'floor': 1,
            'room_type': RoomType.MEZZANINE, 'area': 24.0, 'rent_price': 3800000, 'deposit_amount': 3800000,
            'max_occupants': 3, 'current_occupants': 2, 'status': RoomStatus.OCCUPIED,
            'tenant_name': 'Trần Văn Hùng', 'tenant_phone': '0988112233',
            'amenities': 'Gác lửng, Máy lạnh Inverter, Kệ bếp, WC riêng',
            'description': 'Phòng tầng 1 thoáng mát, đang có 2/3 người ở.',
        },
        {
            'code': 'NT001-A02', 'property': prop1, 'room_number': 'Phòng A02', 'floor': 1,
            'room_type': RoomType.SINGLE, 'area': 18.0, 'rent_price': 2800000, 'deposit_amount': 2800000,
            'max_occupants': 2, 'current_occupants': 0, 'status': RoomStatus.AVAILABLE,
            'amenities': 'Quạt trần, Kệ bếp, WC riêng, Cửa sổ lớn',
            'description': 'Phòng trống đã vệ sinh sạch sẽ, có thể dọn vào ở ngay.',
        },
        {
            'code': 'NT001-B01', 'property': prop1, 'room_number': 'Phòng B01', 'floor': 2,
            'room_type': RoomType.MEZZANINE, 'area': 26.0, 'rent_price': 4200000, 'deposit_amount': 4200000,
            'max_occupants': 3, 'current_occupants': 3, 'status': RoomStatus.FULL,
            'tenant_name': 'Lê Minh Tuấn', 'tenant_phone': '0977223344',
            'amenities': 'Ban công, Máy lạnh, Tủ lạnh, Bình nóng lạnh',
            'description': 'Phòng đã đủ 3/3 người ở tối đa.',
        },
        {
            'code': 'NT001-B02', 'property': prop1, 'room_number': 'Phòng B02', 'floor': 2,
            'room_type': RoomType.MEZZANINE, 'area': 22.0, 'rent_price': 3500000, 'deposit_amount': 3500000,
            'max_occupants': 2, 'current_occupants': 0, 'status': RoomStatus.MAINTENANCE,
            'amenities': 'Gác lửng, Máy lạnh, Bình nóng lạnh',
            'description': 'Đang bảo trì sửa điều hòa và chống thấm tường.',
        },
        {
            'code': 'NT001-C01', 'property': prop1, 'room_number': 'Phòng C01', 'floor': 3,
            'room_type': RoomType.SINGLE, 'area': 20.0, 'rent_price': 3200000, 'deposit_amount': 3200000,
            'max_occupants': 2, 'current_occupants': 0, 'status': RoomStatus.AVAILABLE,
            'amenities': 'Máy lạnh Daikin, Kệ bếp đá hoa cương, Ban công',
            'description': 'Phòng tầng 3 yên tĩnh, nhiều ánh sáng tự nhiên.',
        },
        {
            'code': 'NT001-C02', 'property': prop1, 'room_number': 'Phòng C02', 'floor': 3,
            'room_type': RoomType.SINGLE, 'area': 16.0, 'rent_price': 2500000, 'deposit_amount': 2500000,
            'max_occupants': 1, 'current_occupants': 0, 'status': RoomStatus.INACTIVE,
            'amenities': 'Quạt treo tường, WC riêng',
            'description': 'Phòng tạm ngừng sử dụng để làm kho vật tư tòa nhà.',
        },
        # Nhà trọ NT002
        {
            'code': 'NT002-101', 'property': prop2, 'room_number': 'Căn 101', 'floor': 1,
            'room_type': RoomType.STUDIO, 'area': 32.0, 'rent_price': 5800000, 'deposit_amount': 5800000,
            'max_occupants': 2, 'current_occupants': 2, 'status': RoomStatus.FULL,
            'tenant_name': 'Hoàng Nam', 'tenant_phone': '0909988776',
            'amenities': 'Full nội thất, Sofa, Máy giặt riêng, Smart TV, Tủ lạnh',
            'description': 'Căn hộ Studio cao cấp tầng 1.',
        },
        {
            'code': 'NT002-201', 'property': prop2, 'room_number': 'Căn 201', 'floor': 2,
            'room_type': RoomType.ONE_BED, 'area': 40.0, 'rent_price': 6800000, 'deposit_amount': 6800000,
            'max_occupants': 4, 'current_occupants': 0, 'status': RoomStatus.AVAILABLE,
            'amenities': 'Căn hộ 1PN riêng biệt, Bếp từ âm, Hút mùi, Giường nệm cao su',
            'description': 'Căn hộ 1 phòng ngủ rộng rãi, phù hợp gia đình nhỏ hoặc nhóm 3-4 người.',
        },
        {
            'code': 'NT002-301', 'property': prop2, 'room_number': 'Căn 301', 'floor': 3,
            'room_type': RoomType.STUDIO, 'area': 28.0, 'rent_price': 5200000, 'deposit_amount': 5200000,
            'max_occupants': 2, 'current_occupants': 1, 'status': RoomStatus.OCCUPIED,
            'tenant_name': 'Trần Thị Mai', 'tenant_phone': '0912345678',
            'amenities': 'Full nội thất, Ban công hướng Nam',
            'description': 'Đang có 1 khách thuê, còn trống 1 chỗ ở ghép.',
        },
    ]

    room_objs = {}
    for r_data in rooms_seed:
        r_obj, _ = Room.objects.using('property_db').update_or_create(code=r_data['code'], defaults=r_data)
        room_objs[r_obj.code] = r_obj

    # 3. Maintenance Requests & History
    today = timezone.localdate()
    m1, created1 = MaintenanceRequest.objects.using('property_db').update_or_create(
        code='BT0001',
        defaults={
            'reported_by_id': landlord.id,
            'room': room_objs['NT001-B02'],
            'title': 'Phòng B02 bị hỏng điều hòa & thấm tường cạnh cửa sổ',
            'description': 'Máy lạnh không lạnh (nghi xì gas dàn lạnh) và vết thấm nước mưa góc cửa sổ.',
            'repair_info': 'Đã nạp lại gas R32 và đang quét keo chống thấm Sika 2 lớp.',
            'priority': MaintenancePriority.HIGH,
            'status': MaintenanceStatus.IN_PROGRESS,
            'estimated_cost': 650000,
            'actual_cost': 0,
            'reported_by': 'Quản lý tòa nhà',
            'technician_name': 'Anh Minh Điện Lạnh (0908.111.222)',
            'requested_date': today - timedelta(days=2),
        },
    )
    if created1 or not m1.histories.exists():
        MaintenanceHistory.objects.create(
            maintenance_request=m1,
            room=m1.room,
            action='Tạo yêu cầu bảo trì',
            previous_status='',
            new_status=MaintenanceStatus.PENDING,
            cost=650000,
            repair_content='Ghi nhận sự cố hỏng điều hòa và thấm tường Phòng B02.',
            performed_by='Nguyễn Văn An',
        )
        MaintenanceHistory.objects.create(
            maintenance_request=m1,
            room=m1.room,
            action='Bắt đầu tiến hành sửa chữa',
            previous_status=MaintenanceStatus.PENDING,
            new_status=MaintenanceStatus.IN_PROGRESS,
            cost=650000,
            repair_content='Thợ Minh Điện Lạnh đã kiểm tra, nạp gas và xử lý chống thấm.',
            performed_by='Nguyễn Văn An',
        )

    m2, created2 = MaintenanceRequest.objects.using('property_db').update_or_create(
        code='BT0002',
        defaults={
            'reported_by_id': landlord.id,
            'room': room_objs['NT001-A01'],
            'title': 'Phòng A01 bị hỏng điều hòa (kêu to và yếu lạnh)',
            'description': 'Khách thuê báo máy lạnh kêu to khi chạy ban đêm.',
            'repair_info': 'Đã vệ sinh lồng sóc, thay bạc đạn quạt dàn lạnh và bảo dưỡng tổng thể.',
            'priority': MaintenancePriority.MEDIUM,
            'status': MaintenanceStatus.COMPLETED,
            'estimated_cost': 500000,
            'actual_cost': 450000,
            'reported_by': 'Trần Văn Hùng (Khách thuê)',
            'technician_name': 'Điện lạnh Bách Khoa',
            'requested_date': today - timedelta(days=10),
            'completed_date': today - timedelta(days=8),
        },
    )
    if created2 or not m2.histories.exists():
        MaintenanceHistory.objects.create(
            maintenance_request=m2,
            room=m2.room,
            action='Hoàn thành bảo trì & Ghi nhận chi phí',
            previous_status=MaintenanceStatus.IN_PROGRESS,
            new_status=MaintenanceStatus.COMPLETED,
            cost=450000,
            repair_content='Đã thay bạc đạn quạt và vệ sinh máy lạnh. Chi phí dự kiến 500.000đ -> Chi phí thực tế 450.000đ.',
            performed_by='Nguyễn Văn An',
        )

    m3, created3 = MaintenanceRequest.objects.using('property_db').update_or_create(
        code='BT0003',
        defaults={
            'reported_by_id': landlord.id,
            'room': room_objs['NT002-101'],
            'title': 'Thay khóa vân tay cửa chính Căn 101',
            'description': 'Cảm biến vân tay nhạy kém khi tay ẩm.',
            'repair_info': 'Chờ kỹ thuật viên hãng khóa qua kiểm tra bảo hành.',
            'priority': MaintenancePriority.LOW,
            'status': MaintenanceStatus.PENDING,
            'estimated_cost': 300000,
            'actual_cost': 0,
            'reported_by': 'Hoàng Nam (Khách thuê)',
            'technician_name': 'Bảo hành Khóa thông minh',
            'requested_date': today - timedelta(days=1),
        },
    )
    if created3 or not m3.histories.exists():
        MaintenanceHistory.objects.create(
            maintenance_request=m3,
            room=m3.room,
            action='Tạo yêu cầu bảo trì mới',
            previous_status='',
            new_status=MaintenanceStatus.PENDING,
            cost=300000,
            repair_content='Khách báo cảm biến vân tay căn 101 cần kiểm tra.',
            performed_by='Nguyễn Văn An',
        )

    landlord_id = landlord.id
    room_a01 = room_objs['NT001-A01']
    room_301 = room_objs['NT002-301']

    # 3. Tenant Service (nhatro_tenant_db)
    print("\n[3/5] Seeding Tenant Service (nhatro_tenant_db)...")
    tenant_profiles = []
    for data in [
        {'full_name': 'Trần Văn Hùng', 'user_id': None, 'phone_number': '0988112233',
         'identity_card': '079090112233', 'hometown': 'Đà Nẵng', 'occupation': 'Kỹ sư phần mềm',
         'room_id': room_a01.id},
        {'full_name': 'Trần Thị Mai', 'user_id': tenant.id, 'phone_number': '0912345678',
         'identity_card': '079198003344', 'hometown': 'Tiền Giang', 'occupation': 'Sinh viên',
         'room_id': room_301.id},
    ]:
        profile, created = TenantProfile.objects.using('tenant_db').get_or_create(
            full_name=data['full_name'], landlord_id=landlord_id,
            defaults={**data, 'status': TenantStatus.ACTIVE})
        tenant_profiles.append(profile)
        RentalHistory.objects.using('tenant_db').get_or_create(
            tenant=profile, room_id=data['room_id'],
            defaults={'move_in_date': today - timedelta(days=60)})
        print("  [%s] Tenant profile: %s (room_id=%s)" % ('+' if created else 'ok', profile.full_name, data['room_id']))

    # 4. Contract Service (nhatro_contract_db)
    print("\n[4/5] Seeding Contract Service (nhatro_contract_db)...")
    contracts = []
    for idx, (profile, room) in enumerate(zip(tenant_profiles, [room_a01, room_301]), start=1):
        contract, created = Contract.objects.using('contract_db').get_or_create(
            contract_number=f'HD-SEED-{idx:03d}',
            defaults={'room_id': room.id, 'tenant_id': profile.id, 'landlord_id': landlord_id,
                      'start_date': today - timedelta(days=60), 'end_date': today + timedelta(days=300),
                      'rental_price': room.rent_price, 'deposit_amount': room.deposit_amount,
                      'status': ContractStatus.ACTIVE})
        if created:
            ContractEvent.objects.using('contract_db').create(
                contract=contract, event_type='CREATED', actor_id=landlord_id, new_end_date=contract.end_date)
        contracts.append(contract)
        print("  [%s] Contract %s (room_id=%s, tenant_id=%s)" % (
            '+' if created else 'ok', contract.contract_number, contract.room_id, contract.tenant_id))

    # 5. Billing & Notification Service (nhatro_billing_db)
    print("\n[5/5] Seeding Billing & Notification Service (nhatro_billing_db)...")
    for idx, (contract, room, prop) in enumerate(zip(contracts, [room_a01, room_301], [prop1, prop2]), start=1):
        code = f'HDN-SEED-{idx:03d}'
        if Invoice.objects.using('billing_db').filter(invoice_code=code).exists():
            print("  [ok] Invoice %s already exists." % code)
            continue
        invoice = Invoice(
            invoice_code=code, room_id=room.id, contract_id=contract.id,
            tenant_id=contract.tenant_id, landlord_id=landlord_id,
            billing_month=today.month, billing_year=today.year, room_fee=room.rent_price,
            electricity_old_num=room.initial_electric_reading,
            electricity_new_num=room.initial_electric_reading + 80, electricity_unit_price=prop.electricity_rate,
            water_old_num=room.initial_water_reading, water_new_num=room.initial_water_reading + 5,
            water_unit_price=prop.water_rate, other_service_cost=prop.internet_rate,
            status=InvoiceStatus.UNPAID if idx == 1 else InvoiceStatus.PAID,
            paid_at=None if idx == 1 else timezone.now(), due_date=today + timedelta(days=5))
        invoice.calculate()
        invoice.save(using='billing_db')
        print("  [+] Invoice %s: %s VNĐ (%s)" % (invoice.invoice_code, invoice.total_amount, invoice.status))
    Notification.objects.using('billing_db').get_or_create(
        user_id=tenant.id, title='Hóa đơn tháng %s/%s' % (today.month, today.year),
        defaults={'content': 'Bạn có hóa đơn cần thanh toán trước hạn.',
                  'category': 'INVOICE', 'created_by_id': landlord_id})

    print("\n✅ SEEDING COMPLETED SUCCESSFULLY cho cả 5 service!")


if __name__ == '__main__':
    seed()
