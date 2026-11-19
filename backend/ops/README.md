# Tài liệu vận hành (ops)

Ghi lại các thao tác sửa trực tiếp trên database mà Django migration không tự làm được.
Mỗi script nằm trong `sql/`, tên dạng `<ngày>_<db>_<mô tả>.sql`.

---

## 2026-11-15 — Identity: `token_blacklist` kẹt ở migration 0007

**DB:** `nhatro_identity_db` (SQL Server Express `.\SQLEXPRESS`)
**Script:** [`sql/2026-11-15_identity_token_blacklist_bigint.sql`](sql/2026-11-15_identity_token_blacklist_bigint.sql)
(tên gốc lúc chạy: `step2_identity_fix_PROPOSED.sql`,
sha256 `91220ed6d9706ef44a79616c9076d4ad9f38f28cfbc05637ea2f41415db5814a`; nội dung giữ nguyên,
dòng "NOT EXECUTED" trong header là ghi chú lúc soạn — script **đã được chạy** trên DB thật).

### Sự cố
Migration `token_blacklist.0008_migrate_to_bigautofield` của SimpleJWT 5.5.1 (đổi `id` int → bigint)
lỗi trên `mssql-django`: không gỡ ràng buộc UNIQUE(`token_id`) của OneToOne trước khi đổi kiểu cột.
Các migration 0008, 0010–0013 vì vậy không chạy được.

### Cách xử lý
1. Backup cả 5 DB (`*_20261115_230118.bak` trong thư mục Backup của SQL Server), `RESTORE VERIFYONLY` hợp lệ.
2. Chạy thử script trên bản sao `nhatro_identity_db_fixtest` (đạt; bản sao đã xoá ngày 2026-11-16).
3. Chạy script trên DB thật (1 transaction, `XACT_ABORT ON`, có guard trước/sau):
   gỡ FK/UQ/PK → đổi `id`, `token_id` sang `bigint` (giữ IDENTITY) → tạo lại PK/UQ/FK.
4. `python manage.py migrate token_blacklist 0013 --fake` (settings `config.service_settings.identity`).
5. Hậu kiểm 27/27 đạt; E5 (login → refresh → logout qua Gateway :8000) đạt ngày 2026-11-16.

### Khi nào dùng lại script
Chỉ cho một DB Identity đang ở **đúng** trạng thái: `token_blacklist` đã áp dụng 0001–0007, cột `int`,
hai bảng token **trống**. Script tự dừng (THROW) nếu trạng thái khác. DB tạo mới bằng `migrate`
thông thường không cần script này nếu migration 0008 chạy được trên phiên bản mssql-django đang dùng.

Lệnh chạy:

```bash
sqlcmd -S .\SQLEXPRESS -E -C -b -d nhatro_identity_db -i ops/sql/2026-11-15_identity_token_blacklist_bigint.sql
```

---

## 2026-11-16 — Service 2–5: bản ghi `auth`/`contenttypes` không có bảng

DB của Property, Tenant, Contract, Billing ghi nhận migration `auth`, `contenttypes` là đã áp dụng
(dấu vết thời monolith dùng `ServiceDatabaseRouter`) nhưng không có bảng `auth_*` / `django_content_type`.
Hậu quả: `migrate` của các service này lỗi ở bước `post_migrate` ("Invalid object name 'django_content_type'").

Sửa bằng code, không đụng DB: `config.db_router.StatelessServiceRouter` (khai báo trong
`config/service_settings/{property,tenant,contract,billing}.py`) chặn migrate cho `auth`, `contenttypes`.
Các bản ghi thừa trong `django_migrations` vô hại và được giữ nguyên.
