"""
Thư viện hạ tầng dùng chung (KHÔNG chứa model hay business logic nghiệp vụ).

- health.py      : endpoint /health/ chuẩn cho mọi service
- auth.py        : đọc role/user từ JWT claims (stateless) + permission classes
- service_urls.py: helper dựng ROOT_URLCONF cho từng service
"""
