/* =====================================================================
   STEP 2 (PROPOSED — NOT EXECUTED) — nhatro_identity_db
   Sửa schema token_blacklist về trạng thái cuối của SimpleJWT 5.5.1
   (id: int -> bigint IDENTITY; blacklistedtoken.token_id: int -> bigint)
   thay cho token_blacklist.0008 bị lỗi trên mssql-django.

   Backup trước khi chạy (đã có, đã VERIFYONLY):
     C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\Backup\nhatro_identity_db_20261115_230118.bak

   Chạy:  sqlcmd -S .\SQLEXPRESS -E -C -b -d nhatro_identity_db -i step2_identity_fix_PROPOSED.sql
   Toàn bộ trong 1 transaction + XACT_ABORT: lỗi ở bất kỳ câu nào -> rollback hết.
   File này KHÔNG đụng django_migrations. Lịch sử migration xử lý riêng bằng
   `migrate token_blacklist 0013 --fake` SAU KHI script này COMMIT thành công.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
USE [nhatro_identity_db];
IF DB_NAME() <> N'nhatro_identity_db' THROW 50000, N'ABORT: not connected to nhatro_identity_db.', 1;
BEGIN TRANSACTION;

/* ---------- 0. Guard: dừng nếu trạng thái khác lúc Step 0 ---------- */
IF EXISTS (SELECT 1 FROM dbo.token_blacklist_outstandingtoken)
   OR EXISTS (SELECT 1 FROM dbo.token_blacklist_blacklistedtoken)
    THROW 50001, N'ABORT: bảng token_blacklist không còn trống.', 1;

IF (SELECT COUNT(*) FROM dbo.django_migrations WHERE app = N'token_blacklist') <> 7
   OR EXISTS (SELECT 1 FROM dbo.django_migrations WHERE app = N'token_blacklist'
              AND name NOT IN (N'0001_initial', N'0002_outstandingtoken_jti_hex',
                               N'0003_auto_20171017_2007', N'0004_auto_20171017_2013',
                               N'0005_remove_outstandingtoken_jti', N'0006_auto_20171017_2113',
                               N'0007_auto_20171017_2214'))
    THROW 50002, N'ABORT: lịch sử token_blacklist khác 0001..0007.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.token_blacklist_outstandingtoken')
               AND name = N'id' AND system_type_id = TYPE_ID(N'int') AND is_identity = 1)
   OR NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.token_blacklist_blacklistedtoken')
               AND name = N'id' AND system_type_id = TYPE_ID(N'int') AND is_identity = 1)
   OR NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.token_blacklist_blacklistedtoken')
               AND name = N'token_id' AND system_type_id = TYPE_ID(N'int'))
    THROW 50003, N'ABORT: kiểu cột không còn là int như lúc Step 0.', 1;

/* ---------- 1. Gỡ các ràng buộc phụ thuộc (thứ tự: FK -> UQ -> PK) ---------- */
ALTER TABLE dbo.token_blacklist_blacklistedtoken
    DROP CONSTRAINT [token_blacklist_blacklistedtoken_token_id_3cc7fe56_fk_token_blacklist_outstandingtoken_id];
ALTER TABLE dbo.token_blacklist_blacklistedtoken
    DROP CONSTRAINT [UQ__token_bl__CB3C9E16EF7E1827];          -- UNIQUE(token_id) của OneToOne — 0008 quên gỡ cái này
ALTER TABLE dbo.token_blacklist_blacklistedtoken
    DROP CONSTRAINT [PK__token_bl__3213E83F011BC854];
ALTER TABLE dbo.token_blacklist_outstandingtoken
    DROP CONSTRAINT [PK__token_bl__3213E83FA5E9A370];

/* ---------- 2. Đổi kiểu dữ liệu (IDENTITY được giữ khi int -> bigint) ---------- */
ALTER TABLE dbo.token_blacklist_outstandingtoken ALTER COLUMN [id]       bigint NOT NULL;
ALTER TABLE dbo.token_blacklist_blacklistedtoken ALTER COLUMN [id]       bigint NOT NULL;
ALTER TABLE dbo.token_blacklist_blacklistedtoken ALTER COLUMN [token_id] bigint NOT NULL;

/* ---------- 3. Tạo lại ràng buộc (thứ tự: PK -> UQ -> FK) ---------- */
-- Tên PK theo đúng tên mssql-django đã sinh trong sqlmigrate 0008.
ALTER TABLE dbo.token_blacklist_outstandingtoken
    ADD CONSTRAINT [token_blacklist_outstandingtoken_id_69982597_pk] PRIMARY KEY CLUSTERED ([id]);
ALTER TABLE dbo.token_blacklist_blacklistedtoken
    ADD CONSTRAINT [token_blacklist_blacklistedtoken_id_e1c86975_pk] PRIMARY KEY CLUSTERED ([id]);
ALTER TABLE dbo.token_blacklist_blacklistedtoken
    ADD CONSTRAINT [token_blacklist_blacklistedtoken_token_id_3cc7fe56_uniq] UNIQUE ([token_id]);
-- Giữ nguyên tên FK cũ; NO ACTION như cũ (Django tự xử lý CASCADE ở tầng ORM).
ALTER TABLE dbo.token_blacklist_blacklistedtoken WITH CHECK
    ADD CONSTRAINT [token_blacklist_blacklistedtoken_token_id_3cc7fe56_fk_token_blacklist_outstandingtoken_id]
    FOREIGN KEY ([token_id]) REFERENCES dbo.token_blacklist_outstandingtoken ([id]);

/* KHÔNG đụng tới (đã đúng với model cuối):
   - token_blacklist_outstandingtoken_jti_hex_d9bdf6f7_uniq   UNIQUE(jti)
   - token_blacklist_outstandingtoken_user_id_83bc629a        INDEX(user_id)   <- 0010 định DROP nhầm, ta GIỮ
   - token_blacklist_outstandingtoken_user_id_83bc629a_fk_identity_service_user_id  (user_id bigint NULL -> user.id bigint) */

/* ---------- 4. Hậu kiểm trong transaction ---------- */
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.token_blacklist_outstandingtoken')
               AND name = N'id' AND system_type_id = TYPE_ID(N'bigint') AND is_identity = 1)
   OR NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.token_blacklist_blacklistedtoken')
               AND name = N'id' AND system_type_id = TYPE_ID(N'bigint') AND is_identity = 1)
   OR NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.token_blacklist_blacklistedtoken')
               AND name = N'token_id' AND system_type_id = TYPE_ID(N'bigint') AND is_nullable = 0)
    THROW 50010, N'ABORT: hậu kiểm kiểu cột/IDENTITY thất bại.', 1;

IF (SELECT COUNT(*) FROM sys.key_constraints
    WHERE parent_object_id IN (OBJECT_ID(N'dbo.token_blacklist_outstandingtoken'),
                               OBJECT_ID(N'dbo.token_blacklist_blacklistedtoken'))) <> 4   -- 2 PK + UQ(jti) + UQ(token_id)
   OR (SELECT COUNT(*) FROM sys.foreign_keys
       WHERE parent_object_id IN (OBJECT_ID(N'dbo.token_blacklist_outstandingtoken'),
                                  OBJECT_ID(N'dbo.token_blacklist_blacklistedtoken'))
         AND is_disabled = 0 AND is_not_trusted = 0) <> 2
    THROW 50011, N'ABORT: hậu kiểm constraint thất bại.', 1;

COMMIT TRANSACTION;
PRINT N'OK: token_blacklist schema đã ở trạng thái cuối. Bước tiếp: migrate token_blacklist 0013 --fake';
