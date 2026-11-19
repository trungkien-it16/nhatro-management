#!/usr/bin/env python
"""
Chạy test của từng service với SETTINGS RIÊNG của service đó (đảm bảo mỗi service
độc lập: chỉ có app + database của chính nó), sau đó chạy test của API Gateway.

    DB_ENGINE=sqlite python run_tests.py
"""
import os
import subprocess
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent

SUITES = [
    ('Identity', BACKEND_DIR, 'config.service_settings.identity', 'services.identity_service'),
    ('Property', BACKEND_DIR, 'config.service_settings.property', 'services.property_service'),
    ('Tenant', BACKEND_DIR, 'config.service_settings.tenant', 'services.tenant_service'),
    ('Contract', BACKEND_DIR, 'config.service_settings.contract', 'services.contract_service'),
    ('Billing', BACKEND_DIR, 'config.service_settings.billing', 'services.billing_notification_service'),
    ('Gateway', BACKEND_DIR / 'api_gateway', 'config.settings', 'gateway'),
]


def main():
    failed = []
    for name, cwd, settings_module, label in SUITES:
        print(f'\n===== {name} ({settings_module}) =====', flush=True)
        env = {**os.environ, 'DJANGO_SETTINGS_MODULE': settings_module}
        code = subprocess.call([sys.executable, 'manage.py', 'test', label, '-v', '1'], cwd=cwd, env=env)
        if code != 0:
            failed.append(name)
    print('\n' + ('✅ Tất cả test đều pass.' if not failed else f'❌ Test lỗi: {", ".join(failed)}'))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
