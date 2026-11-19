# 🏢 HỆ THỐNG QUẢN LÝ NHÀ TRỌ (SOA — API GATEWAY + 5 SERVICES)

- **Frontend**: Flutter Web (Provider, go_router, Material 3, giao diện SaaS) — chỉ giao tiếp với **API Gateway :8000**
- **Backend**: Django REST Framework + SimpleJWT — 1 Gateway + 5 service, **mỗi service 1 process, 1 port, 1 database**
- **Database**: Microsoft SQL Server (mssql-django) hoặc SQLite (`DB_ENGINE=sqlite`)

---

## 🏛️ KIẾN TRÚC

```
Flutter Web
     │  (chỉ gọi :8000)
     ▼
API Gateway :8000  ── /api/system/health/      (kiểm tra /health/ của 5 service)
     │             ── /api/dashboard/summary/  (tổng hợp số liệu Dashboard)
     │
     ├── /api/auth/*, /api/users/*                               ─► Identity Service        :8001  nhatro_identity_db
     ├── /api/properties/*, /api/rooms/*, /api/maintenance/*,
     │   /api/maintenance-history/*                               ─► Property & Maintenance  :8002  nhatro_property_db
     ├── /api/tenants/*                                          ─► Tenant Service          :8003  nhatro_tenant_db
     ├── /api/contracts/*                                        ─► Contract Service        :8004  nhatro_contract_db
     └── /api/billing/*, /api/notifications/*                    ─► Billing & Notification  :8005  nhatro_billing_db
```

| Service | Port | Trách nhiệm (owner dữ liệu) |
| :--- | :--- | :--- |
| **Identity** | 8001 | Đăng ký, đăng nhập, JWT access/refresh, đăng xuất (blacklist), đổi mật khẩu, tài khoản, role |
| **Property & Maintenance** | 8002 | Nhà trọ (mã, khu vực, trạng thái ACTIVE/INACTIVE/DELETED), phòng (loại, giá, diện tích, số người tối đa/hiện tại, trạng thái), tìm kiếm/lọc/sắp xếp, bảo trì & lịch sử bảo trì |
| **Tenant** | 8003 | Hồ sơ người thuê, liên hệ, lịch sử thuê (**không** quản lý mật khẩu) |
| **Contract** | 8004 | Hợp đồng: tạo, cập nhật, kích hoạt, gia hạn, kết thúc, lịch sử |
| **Billing & Notification** | 8005 | Hóa đơn (phòng/điện/nước/dịch vụ), thanh toán, công nợ, thông báo |

**Nguyên tắc SOA đang áp dụng**
- Mỗi service chạy với settings riêng (`backend/config/service_settings/<service>.py`): chỉ cài app của nó và chỉ có database của nó → không thể truy vấn model của service khác.
- Liên kết giữa service bằng **ID** (`owner_id`, `room_id`, `tenant_id`, `contract_id`, `user_id`), không có Foreign Key chéo.
- Xác thực **stateless**: Identity ký JWT có claim `role`, `username`, `full_name`, `is_superuser`; các service khác chỉ xác minh chữ ký (cùng `JWT_SIGNING_KEY`), không đọc DB Identity.
- CORS chỉ bật ở Gateway → trình duyệt không gọi trực tiếp được 8001–8005.
- Gateway xử lý service lỗi: không kết nối được → `503`, quá thời gian → `504` (timeout cấu hình bằng `GATEWAY_CONNECT_TIMEOUT` / `GATEWAY_READ_TIMEOUT`).
- `backend/common/` là thư viện hạ tầng dùng chung (health check, đọc role từ JWT) — không chứa model nghiệp vụ.

**Phân quyền (kiểm tra ở backend)**
- `ADMIN` / `STAFF`: toàn bộ dữ liệu. `LANDLORD`: chỉ nhà trọ/phòng/bảo trì/hợp đồng/hóa đơn của mình. `TENANT`: chỉ xem phòng còn hoạt động (ẩn thông tin cá nhân người đang thuê), báo bảo trì và xem/hủy yêu cầu do mình tạo.
- Đăng ký công khai chỉ được chọn `LANDLORD` hoặc `TENANT`. Người dùng không thể tự đổi `role`, `is_active`, `username` qua `/api/auth/me/`.
- `/api/users/`: chỉ `ADMIN` được đổi `role`/`is_active` và xóa tài khoản; `LANDLORD` chỉ được tạo tài khoản `TENANT`.

---

## 🚀 KHỞI CHẠY

### 1. Backend

```bash
cd backend
.\venv\Scripts\Activate.ps1          # hoặc: source venv/bin/activate
pip install -r requirements.txt

# Cấu hình: sao chép .env.example -> .env, đặt SECRET_KEY; khi phát triển đặt DEBUG=True
# (mặc định DEBUG=False; thiếu SECRET_KEY khi DEBUG=False thì service không khởi động)

# (SQL Server) tạo 5 database nếu chưa có
python create_db.py

# Migrate DB của từng service + chạy Gateway và 5 service
python run_all_services.py --migrate

# (cửa sổ khác) nạp dữ liệu mẫu
python seed_data.py
```

Các lần sau chỉ cần `python run_all_services.py` (tùy chọn: `--only identity property`, `--reload`, `--host 0.0.0.0`).
Từ thư mục gốc cũng có thể chạy `python run_all.py` hoặc `.\run_all.bat` (gọi `backend/run_all_services.py`, nhận cùng tham số).

Chạy riêng 1 service (ví dụ để debug):

```bash
python manage.py runserver 8002 --settings=config.service_settings.property
cd api_gateway && python manage.py runserver 8000
```

> **Nâng cấp database đang có**: chạy `python run_all_services.py --migrate` một lần. Migration
> `property_service/0002_merge_soa_maintenance_fields` chỉ **thêm cột** (`reported_by_id`, `previous_room_status`,
> `started_at` cho bảo trì; `initial_electric_reading`, `initial_water_reading` cho phòng) và trạng thái phòng `RESERVED`,
> không xóa dữ liệu. Người dùng cần **đăng nhập lại** để nhận JWT có claim `role`.

### 2. Kiểm tra

```bash
cd backend
DB_ENGINE=sqlite python run_tests.py   # test từng service với settings riêng + test Gateway
```

- Trạng thái hệ thống: `http://127.0.0.1:8000/api/system/health/`
- Swagger của từng service: `http://127.0.0.1:800X/api/docs/`

### 3. Frontend

```bash
cd frontend
flutter pub get
flutter run -d chrome
# Gateway ở địa chỉ khác:
flutter run -d chrome --dart-define=API_GATEWAY_URL=http://192.168.1.10:8000
flutter analyze && flutter test
```

Ứng dụng yêu cầu **đăng nhập** (JWT qua Gateway, tự làm mới access token bằng refresh token). Khi không kết nối được
Gateway, giao diện hiển thị **dữ liệu mẫu** kèm cảnh báo rõ ràng.

---

## 🔌 ENDPOINT CHÍNH (qua Gateway :8000)

| Nhóm | Endpoint |
| :--- | :--- |
| Hệ thống | `GET /api/system/health/` · `GET /api/dashboard/summary/` (cần token) |
| Auth | `POST /api/auth/login/` · `refresh/` · `register/` · `logout/` · `change-password/` · `GET/PATCH /api/auth/me/` · `/api/users/` |
| Nhà trọ | `/api/properties/?search=&status=&district=&ward=` · `{id}/rooms/` · `{id}/stats/` · `{id}/room_matrix/` · `POST {id}/update_status/` · `summary/` · `DELETE` = xóa mềm nếu còn phòng |
| Phòng | `/api/rooms/?property_id=&status=&min_price=&max_price=&min_area=&max_area=&max_occupants=&floor=&district=&search=&sort=price_asc\|price_desc\|area_asc\|area_desc\|name_asc\|created_desc` · `GET/PATCH {id}/status/` · `{id}/check_rentable/` · `available/` · `occupied/` · `maintenance/` |
| Bảo trì | `/api/maintenance/?status=&priority=&room_id=&property_id=&search=` · `POST {id}/update_status/` · `{id}/start/` · `{id}/record_cost/` · `{id}/complete/` · `{id}/cancel/` · `GET {id}/history/` · `/api/maintenance-history/` |
| Người thuê | `/api/tenants/?search=&status=&room_id=` · `GET/POST {id}/history/` · `summary/` |
| Hợp đồng | `/api/contracts/?status=&room_id=&tenant_id=` · `POST {id}/activate/` · `{id}/extend/` · `{id}/terminate/` · `GET {id}/history/` · `summary/` |
| Hóa đơn | `/api/billing/invoices/?status=UNPAID\|PAID\|OVERDUE\|DEBT` · `POST {id}/pay/` · `{id}/cancel/` · `GET debt/` · `summary/` |
| Thông báo | `/api/notifications/?unread=1&category=` · `POST {id}/read/` · `POST read-all/` |

`/api/v1/...` vẫn được Gateway chấp nhận (alias của `/api/...`) để tương thích client cũ.

---

## 🔑 TÀI KHOẢN MẪU (chỉ môi trường DEV — seed_data.py)

| Vai trò | Username | Password |
| :--- | :--- | :--- |
| **Chủ trọ (LANDLORD)** | `chutro1` | `chutropassword123` |
| **Quản trị viên (ADMIN)** | `admin` | `adminpassword123` |
| **Khách thuê (TENANT)** | `khach1` | `khachpassword123` |

Đổi mật khẩu mẫu bằng `SEED_ADMIN_PASSWORD`, `SEED_LANDLORD_PASSWORD`, `SEED_TENANT_PASSWORD` khi chạy seed.
`GET /api/auth/test-users/` chỉ hoạt động khi `DEBUG=True` và không bao giờ trả về tài khoản ADMIN.

---

## 📁 CẤU TRÚC THƯ MỤC

```
nhatro_management/
├── run_all.py / run_all.bat         # Lối tắt chạy backend/run_all_services.py
├── backend/
│   ├── api_gateway/                 # API GATEWAY :8000 (Django project riêng, không DB)
│   │   ├── config/                  #   settings (SERVICE_REGISTRY, CORS, timeout), urls
│   │   ├── gateway/                 #   proxy, system health, dashboard aggregation, tests
│   │   └── manage.py
│   ├── common/                      # Hạ tầng dùng chung: /health/, phân quyền theo JWT claims
│   ├── config/
│   │   ├── common.py                # Cấu hình chung (JWT, DRF, DB per service, DEBUG/SECRET_KEY)
│   │   ├── service_settings/        # Settings riêng của 5 service (identity/property/tenant/contract/billing)
│   │   ├── settings.py              # TOOLBOX settings: seed/migrate thủ công (không chạy runtime)
│   │   └── db_router.py             # Router 5 DB cho toolbox settings
│   ├── services/
│   │   ├── identity_service/        # SERVICE 1 :8001
│   │   ├── property_service/        # SERVICE 2 :8002 (Property, Room, Status, Maintenance, History)
│   │   ├── tenant_service/          # SERVICE 3 :8003
│   │   ├── contract_service/        # SERVICE 4 :8004
│   │   └── billing_notification_service/ # SERVICE 5 :8005
│   ├── templates/                   # portal.html / api_docs.html cũ (không còn được định tuyến, xem bên dưới)
│   ├── create_db.py
│   ├── run_all_services.py          # Chạy Gateway + 5 service
│   ├── run_tests.py                 # Test từng service độc lập + Gateway
│   └── seed_data.py                 # Dữ liệu mẫu cho cả 5 service
└── frontend/lib/
    ├── core/                        # constants (api_constants = chỉ Gateway URL, soa_services), theme, widgets
    ├── features/                    # auth (đăng nhập), dashboard, property, room, maintenance, tenant,
    │                                #   contract, billing, notification/settings
    ├── models/                      # system_health_model, dashboard_summary_model
    ├── providers/auth_provider.dart # Phiên đăng nhập (login / logout thu hồi refresh token)
    ├── shared/                      # layouts, models, services (api_client, app_data_repository)
    └── main.dart                    # go_router + chặn truy cập khi chưa đăng nhập
```

## 🧭 LỘ TRÌNH / HẠN CHẾ HIỆN TẠI

- **Sprint 1 — Tenant / Contract / Billing / Notification**: hoàn thiện ở mức backend (service độc lập, database riêng,
  URL/port riêng, API, health check, định tuyến qua API Gateway). Frontend của các service này sẽ được triển khai và
  hoàn thiện trong Sprint tiếp theo. Dashboard đã lấy số liệu thật của các service này qua `/api/dashboard/summary/`.
- `backend/templates/portal.html` & `api_docs.html` (giao diện web tổng hợp cũ trên :8000) gọi thẳng các port 8001–8005
  nên không còn được phục vụ sau khi :8000 chuyển thành API Gateway.
- Thông tin CCCD/địa chỉ hiện vẫn nằm trên `User` (Identity) và đồng thời có trong `TenantProfile`; sẽ chuyển hẳn sang Tenant Service.
- Đồng bộ giữa service (vd. ký hợp đồng → phòng OCCUPIED, gửi thông báo hợp đồng/bảo trì) hiện làm thủ công qua API; bước sau: event/message bus hoặc gọi API nội bộ có xác thực service-to-service.
