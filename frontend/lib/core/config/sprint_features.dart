/// Chức năng ghi đã có source code nhưng CHƯA mở trong Sprint hiện tại.
///
/// Phản chiếu khóa ở backend (`SprintFeatureLock`, biến môi trường `SPRINT_FEATURE_LOCK`, mặc định bật):
/// backend trả 403 cho các API này với MỌI vai trò. Giao diện chỉ ẩn nút để người dùng không bấm vào
/// chức năng chắc chắn bị từ chối — đây KHÔNG phải lớp phân quyền; backend vẫn là nơi chặn cuối cùng.
///
/// Các hàm gọi API tương ứng trong repository được giữ nguyên cho Sprint sau. Khi backend mở khóa
/// (`SPRINT_FEATURE_LOCK=False`), build lại frontend với `--dart-define=SPRINT_FEATURE_LOCK=false`.
class SprintFeatures {
  SprintFeatures._();

  static const bool locked = bool.fromEnvironment('SPRINT_FEATURE_LOCK', defaultValue: true);

  /// Hợp đồng: tạo / sửa / xóa / kích hoạt / gia hạn / chấm dứt.
  static const bool contractWrite = !locked;

  /// Hóa đơn: tạo / sửa / xóa / thanh toán / hủy.
  static const bool invoiceWrite = !locked;

  /// Thông báo: tạo mới (đánh dấu đã đọc vẫn mở).
  static const bool notificationCreate = !locked;

  /// Lịch sử thuê của người thuê: thêm bản ghi (xem vẫn mở).
  static const bool tenantHistoryCreate = !locked;

  /// Bảo trì: mọi API ghi (trang Bảo trì cũng đang ẩn khỏi menu).
  static const bool maintenanceWrite = !locked;
}
