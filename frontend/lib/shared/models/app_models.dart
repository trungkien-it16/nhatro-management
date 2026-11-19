class PropertyItem {
  final int id;
  final String code;
  final String name;
  /// Địa chỉ chi tiết (số nhà, tên đường) = trường `address` của Property Service. Là trường được ghi.
  final String address;
  final String district;
  final String ward;
  final String city;
  /// Địa chỉ đã ghép (`full_address`, chỉ đọc) = address, ward, district, city. Chỉ dùng để hiển thị,
  /// không bao giờ gửi ngược lên backend.
  final String fullAddress;
  final int totalRooms;
  final int occupiedRooms;
  final int availableRooms;
  final int maintenanceRooms;
  final String status; // ACTIVE, INACTIVE
  final String description;

  const PropertyItem({
    required this.id,
    required this.code,
    required this.name,
    required this.address,
    required this.district,
    this.ward = '',
    this.city = '',
    this.fullAddress = '',
    required this.totalRooms,
    required this.occupiedRooms,
    required this.availableRooms,
    this.maintenanceRooms = 0,
    required this.status,
    this.description = '',
  });

  /// Địa chỉ để hiển thị: địa chỉ đầy đủ do backend ghép, nếu không có thì dùng địa chỉ chi tiết.
  String get displayAddress => fullAddress.isNotEmpty ? fullAddress : address;

  PropertyItem copyWith({
    String? code,
    String? name,
    String? address,
    String? district,
    String? ward,
    String? city,
    String? fullAddress,
    int? totalRooms,
    int? occupiedRooms,
    int? availableRooms,
    int? maintenanceRooms,
    String? status,
    String? description,
  }) {
    return PropertyItem(
      id: id,
      code: code ?? this.code,
      name: name ?? this.name,
      address: address ?? this.address,
      district: district ?? this.district,
      ward: ward ?? this.ward,
      city: city ?? this.city,
      fullAddress: fullAddress ?? this.fullAddress,
      totalRooms: totalRooms ?? this.totalRooms,
      occupiedRooms: occupiedRooms ?? this.occupiedRooms,
      availableRooms: availableRooms ?? this.availableRooms,
      maintenanceRooms: maintenanceRooms ?? this.maintenanceRooms,
      status: status ?? this.status,
      description: description ?? this.description,
    );
  }
}

class RoomItem {
  final int id;
  final String code;
  final String name;
  final int propertyId;
  final String propertyName;
  final int floor;
  final double rentPrice;
  final double area;
  final int currentOccupants;
  final int maxOccupants;
  final String status; // AVAILABLE, OCCUPIED, FULL, RESERVED, MAINTENANCE, INACTIVE
  final String description;
  final bool isRentable;
  final String rentabilityReason;

  const RoomItem({
    required this.id,
    required this.code,
    required this.name,
    required this.propertyId,
    required this.propertyName,
    this.floor = 1,
    required this.rentPrice,
    required this.area,
    required this.currentOccupants,
    required this.maxOccupants,
    required this.status,
    this.description = '',
    this.isRentable = true,
    this.rentabilityReason = '',
  });

  RoomItem copyWith({
    String? code,
    String? name,
    int? propertyId,
    String? propertyName,
    int? floor,
    double? rentPrice,
    double? area,
    int? currentOccupants,
    int? maxOccupants,
    String? status,
    String? description,
    bool? isRentable,
    String? rentabilityReason,
  }) {
    return RoomItem(
      id: id,
      code: code ?? this.code,
      name: name ?? this.name,
      propertyId: propertyId ?? this.propertyId,
      propertyName: propertyName ?? this.propertyName,
      floor: floor ?? this.floor,
      rentPrice: rentPrice ?? this.rentPrice,
      area: area ?? this.area,
      currentOccupants: currentOccupants ?? this.currentOccupants,
      maxOccupants: maxOccupants ?? this.maxOccupants,
      status: status ?? this.status,
      description: description ?? this.description,
      isRentable: isRentable ?? this.isRentable,
      rentabilityReason: rentabilityReason ?? this.rentabilityReason,
    );
  }
}

class TenantItem {
  final int id;
  final int? roomId;

  /// Tài khoản đăng nhập (Identity user id, vai trò TENANT) gắn với hồ sơ; null = chưa liên kết.
  final int? userId;

  /// Chủ trọ sở hữu hồ sơ (do backend gán từ JWT, chỉ đọc).
  final int? landlordId;
  final String fullName;
  final String phone;
  final String email;
  final String idCard;
  final String currentRoom;
  final String propertyName;
  final String startDate;
  final String status; // ACTIVE, INACTIVE, MOVED_OUT (Tenant Service)
  final String permanentAddress;
  final String birthDate;
  final String gender;
  final String occupation;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final bool temporaryResidenceRegistered;
  final String notes;

  const TenantItem({
    required this.id,
    this.roomId,
    this.userId,
    this.landlordId,
    required this.fullName,
    required this.phone,
    required this.email,
    this.idCard = '',
    required this.currentRoom,
    required this.propertyName,
    required this.startDate,
    required this.status,
    this.permanentAddress = '',
    this.birthDate = '',
    this.gender = '',
    this.occupation = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.temporaryResidenceRegistered = false,
    this.notes = '',
  });

  TenantItem copyWith({
    int? roomId,
    int? userId,
    String? fullName,
    String? phone,
    String? email,
    String? idCard,
    String? currentRoom,
    String? propertyName,
    String? startDate,
    String? status,
    String? permanentAddress,
    String? birthDate,
    String? gender,
    String? occupation,
    String? emergencyContactName,
    String? emergencyContactPhone,
    bool? temporaryResidenceRegistered,
    String? notes,
  }) {
    return TenantItem(
      id: id,
      roomId: roomId ?? this.roomId,
      userId: userId ?? this.userId,
      landlordId: landlordId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      idCard: idCard ?? this.idCard,
      currentRoom: currentRoom ?? this.currentRoom,
      propertyName: propertyName ?? this.propertyName,
      startDate: startDate ?? this.startDate,
      status: status ?? this.status,
      permanentAddress: permanentAddress ?? this.permanentAddress,
      birthDate: birthDate ?? this.birthDate,
      gender: gender ?? this.gender,
      occupation: occupation ?? this.occupation,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone: emergencyContactPhone ?? this.emergencyContactPhone,
      temporaryResidenceRegistered:
          temporaryResidenceRegistered ?? this.temporaryResidenceRegistered,
      notes: notes ?? this.notes,
    );
  }
}

class TenantHistoryItem {
  final int id;
  final int? roomId;
  final int? contractId;
  final String moveInDate;
  final String moveOutDate;
  final String note;

  const TenantHistoryItem({
    required this.id,
    this.roomId,
    this.contractId,
    required this.moveInDate,
    this.moveOutDate = '',
    this.note = '',
  });
}

class ContractItem {
  final int id;
  final int? roomId;
  final int? tenantId;
  final String code;
  final String tenantName;
  final String roomName;
  final String propertyName;
  final String startDate;
  final String endDate;
  final double rentPrice;
  final double depositAmount;
  final int billingDayOfMonth;
  final String status; // DRAFT, ACTIVE, EXTENDED, EXPIRING, EXPIRED, TERMINATED, CANCELLED
  final String termsAndConditions;
  final String terminatedAt;
  final String terminationReason;

  const ContractItem({
    required this.id,
    this.roomId,
    this.tenantId,
    required this.code,
    required this.tenantName,
    required this.roomName,
    required this.propertyName,
    required this.startDate,
    required this.endDate,
    required this.rentPrice,
    required this.depositAmount,
    this.billingDayOfMonth = 5,
    required this.status,
    this.termsAndConditions = '',
    this.terminatedAt = '',
    this.terminationReason = '',
  });

  ContractItem copyWith({
    int? roomId,
    int? tenantId,
    String? code,
    String? tenantName,
    String? roomName,
    String? propertyName,
    String? startDate,
    String? endDate,
    double? rentPrice,
    double? depositAmount,
    int? billingDayOfMonth,
    String? status,
    String? termsAndConditions,
    String? terminatedAt,
    String? terminationReason,
  }) {
    return ContractItem(
      id: id,
      roomId: roomId ?? this.roomId,
      tenantId: tenantId ?? this.tenantId,
      code: code ?? this.code,
      tenantName: tenantName ?? this.tenantName,
      roomName: roomName ?? this.roomName,
      propertyName: propertyName ?? this.propertyName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      rentPrice: rentPrice ?? this.rentPrice,
      depositAmount: depositAmount ?? this.depositAmount,
      billingDayOfMonth: billingDayOfMonth ?? this.billingDayOfMonth,
      status: status ?? this.status,
      termsAndConditions: termsAndConditions ?? this.termsAndConditions,
      terminatedAt: terminatedAt ?? this.terminatedAt,
      terminationReason: terminationReason ?? this.terminationReason,
    );
  }
}

class ContractEventItem {
  final int id;
  final String eventType;
  final String eventTypeDisplay;
  final String oldEndDate;
  final String newEndDate;
  final String note;
  final String createdAt;

  const ContractEventItem({
    required this.id,
    required this.eventType,
    required this.eventTypeDisplay,
    this.oldEndDate = '',
    this.newEndDate = '',
    this.note = '',
    this.createdAt = '',
  });
}

class InvoiceItem {
  final int id;
  final int? roomId;
  final int? contractId;
  final int? tenantId;
  final String code;
  final String tenantName;
  final String roomName;
  final String propertyName;
  final int month;
  final int year;
  final String billingMonth;
  final double roomFee;
  final int electricityOld;
  final int electricityNew;
  final double electricityUnitPrice;
  final double electricityCost;
  final int waterOld;
  final int waterNew;
  final double waterUnitPrice;
  final double waterCost;
  final double otherServiceCost;
  final double totalAmount;
  final String dueDate;
  final String status; // PAID, UNPAID, OVERDUE, CANCELLED

  const InvoiceItem({
    required this.id,
    this.roomId,
    this.contractId,
    this.tenantId,
    required this.code,
    required this.tenantName,
    required this.roomName,
    required this.propertyName,
    this.month = 11,
    this.year = 2026,
    required this.billingMonth,
    this.roomFee = 0,
    this.electricityOld = 0,
    this.electricityNew = 0,
    this.electricityUnitPrice = 3500,
    this.electricityCost = 0,
    this.waterOld = 0,
    this.waterNew = 0,
    this.waterUnitPrice = 18000,
    this.waterCost = 0,
    this.otherServiceCost = 0,
    required this.totalAmount,
    required this.dueDate,
    required this.status,
  });

  InvoiceItem copyWith({
    int? roomId,
    int? contractId,
    int? tenantId,
    String? code,
    String? tenantName,
    String? roomName,
    String? propertyName,
    int? month,
    int? year,
    String? billingMonth,
    double? roomFee,
    int? electricityOld,
    int? electricityNew,
    double? electricityUnitPrice,
    double? electricityCost,
    int? waterOld,
    int? waterNew,
    double? waterUnitPrice,
    double? waterCost,
    double? otherServiceCost,
    double? totalAmount,
    String? dueDate,
    String? status,
  }) {
    return InvoiceItem(
      id: id,
      roomId: roomId ?? this.roomId,
      contractId: contractId ?? this.contractId,
      tenantId: tenantId ?? this.tenantId,
      code: code ?? this.code,
      tenantName: tenantName ?? this.tenantName,
      roomName: roomName ?? this.roomName,
      propertyName: propertyName ?? this.propertyName,
      month: month ?? this.month,
      year: year ?? this.year,
      billingMonth: billingMonth ?? this.billingMonth,
      roomFee: roomFee ?? this.roomFee,
      electricityOld: electricityOld ?? this.electricityOld,
      electricityNew: electricityNew ?? this.electricityNew,
      electricityUnitPrice: electricityUnitPrice ?? this.electricityUnitPrice,
      electricityCost: electricityCost ?? this.electricityCost,
      waterOld: waterOld ?? this.waterOld,
      waterNew: waterNew ?? this.waterNew,
      waterUnitPrice: waterUnitPrice ?? this.waterUnitPrice,
      waterCost: waterCost ?? this.waterCost,
      otherServiceCost: otherServiceCost ?? this.otherServiceCost,
      totalAmount: totalAmount ?? this.totalAmount,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
    );
  }
}

class MaintenanceItem {
  final int id;
  final String code;
  final int roomId;
  final String roomName;
  final String propertyName;
  final String title;
  final String description;
  final String repairInfo;
  final String technicianName;
  final String createdAt;
  final String priority; // LOW, MEDIUM, HIGH
  final String status; // PENDING, IN_PROGRESS, COMPLETED, CANCELLED
  final double estimatedCost;
  final double actualCost;

  const MaintenanceItem({
    required this.id,
    required this.code,
    required this.roomId,
    required this.roomName,
    required this.propertyName,
    required this.title,
    this.description = '',
    this.repairInfo = '',
    this.technicianName = '',
    required this.createdAt,
    required this.priority,
    required this.status,
    this.estimatedCost = 0,
    this.actualCost = 0,
  });

  MaintenanceItem copyWith({
    String? code,
    int? roomId,
    String? roomName,
    String? propertyName,
    String? title,
    String? description,
    String? repairInfo,
    String? technicianName,
    String? createdAt,
    String? priority,
    String? status,
    double? estimatedCost,
    double? actualCost,
  }) {
    return MaintenanceItem(
      id: id,
      code: code ?? this.code,
      roomId: roomId ?? this.roomId,
      roomName: roomName ?? this.roomName,
      propertyName: propertyName ?? this.propertyName,
      title: title ?? this.title,
      description: description ?? this.description,
      repairInfo: repairInfo ?? this.repairInfo,
      technicianName: technicianName ?? this.technicianName,
      createdAt: createdAt ?? this.createdAt,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      actualCost: actualCost ?? this.actualCost,
    );
  }
}

class MaintenanceHistoryItem {
  final int id;
  final String requestCode;
  final String roomNumber;
  final String propertyName;
  final String action;
  final String previousStatus;
  final String newStatus;
  final double cost;
  final String repairContent;
  final String performedBy;
  final String repairDate;

  const MaintenanceHistoryItem({
    required this.id,
    required this.requestCode,
    required this.roomNumber,
    required this.propertyName,
    required this.action,
    this.previousStatus = '',
    this.newStatus = '',
    this.cost = 0,
    this.repairContent = '',
    this.performedBy = '',
    this.repairDate = '',
  });
}

class NotificationItem {
  final int id;
  final String title;
  final String message;
  final String createdAt;
  final String category; // BILLING, CONTRACT, MAINTENANCE, SYSTEM
  final bool isRead;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.category,
    this.isRead = false,
  });

  NotificationItem copyWith({bool? isRead}) {
    return NotificationItem(
      id: id,
      title: title,
      message: message,
      createdAt: createdAt,
      category: category,
      isRead: isRead ?? this.isRead,
    );
  }
}

class MonthlyRevenuePoint {
  final String monthLabel;
  final double amountInMillions;

  const MonthlyRevenuePoint({
    required this.monthLabel,
    required this.amountInMillions,
  });
}

