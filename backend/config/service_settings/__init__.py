"""
Settings riêng cho từng service (mỗi service = 1 process, 1 port, 1 database).

    identity  -> :8001  (config.service_settings.identity)
    property  -> :8002  (config.service_settings.property)
    tenant    -> :8003  (config.service_settings.tenant)
    contract  -> :8004  (config.service_settings.contract)
    billing   -> :8005  (config.service_settings.billing)

Mỗi file chỉ cài app nghiệp vụ của chính service đó và chỉ có 1 database
(`default`) trỏ tới database riêng của service -> không thể import/truy vấn
model của service khác tại runtime.
"""
