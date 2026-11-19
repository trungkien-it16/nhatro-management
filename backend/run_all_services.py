#!/usr/bin/env python
"""
Khởi chạy toàn bộ hệ thống SOA: API Gateway + 5 service, mỗi thành phần 1 process.

    python run_all_services.py              # chạy tất cả
    python run_all_services.py --migrate    # migrate DB của từng service rồi chạy
    python run_all_services.py --only identity property   # chỉ chạy một số service (+ gateway)
    python run_all_services.py --reload     # bật autoreload của Django (dev)

    Gateway   :8000  (Frontend chỉ gọi cổng này)
    Identity  :8001   Property :8002   Tenant :8003   Contract :8004   Billing :8005
"""
import argparse
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent

SERVICES = [
    # key, tên hiển thị, port, thư mục chứa manage.py, settings module
    ('identity', 'Identity', 8001, BACKEND_DIR, 'config.service_settings.identity'),
    ('property', 'Property', 8002, BACKEND_DIR, 'config.service_settings.property'),
    ('tenant', 'Tenant', 8003, BACKEND_DIR, 'config.service_settings.tenant'),
    ('contract', 'Contract', 8004, BACKEND_DIR, 'config.service_settings.contract'),
    ('billing', 'Billing', 8005, BACKEND_DIR, 'config.service_settings.billing'),
]
GATEWAY = ('gateway', 'Gateway', 8000, BACKEND_DIR / 'api_gateway', 'config.settings')


def manage(cwd, settings_module, *args, **popen_kwargs):
    env = {**os.environ, 'DJANGO_SETTINGS_MODULE': settings_module, 'PYTHONUNBUFFERED': '1'}
    return subprocess.Popen([sys.executable, 'manage.py', *args], cwd=cwd, env=env, **popen_kwargs)


def pipe_output(name, proc):
    for line in iter(proc.stdout.readline, ''):
        sys.stdout.write(f'[{name:<8}] {line}')
    proc.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--migrate', action='store_true', help='Chạy migrate cho DB của từng service trước')
    parser.add_argument('--reload', action='store_true', help='Bật autoreload (mặc định tắt để dễ quản lý process)')
    parser.add_argument('--only', nargs='+', choices=[s[0] for s in SERVICES], help='Chỉ chạy các service này')
    parser.add_argument('--host', default='127.0.0.1', help='Địa chỉ bind (0.0.0.0 để mở ra mạng LAN)')
    args = parser.parse_args()

    selected = [s for s in SERVICES if not args.only or s[0] in args.only]

    if args.migrate:
        for key, name, _port, cwd, settings_module in selected:
            print(f'==> migrate {name} ({settings_module})')
            code = manage(cwd, settings_module, 'migrate', '--noinput').wait()
            if code != 0:
                print(f'❌ migrate {name} thất bại (exit {code})')
                return code

    procs = []
    for key, name, port, cwd, settings_module in [*selected, GATEWAY]:
        cmd = ['runserver', f'{args.host}:{port}']
        if not args.reload:
            cmd.append('--noreload')
        proc = manage(cwd, settings_module, *cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        procs.append((name, port, proc))
        threading.Thread(target=pipe_output, args=(name, proc), daemon=True).start()

    print('\n' + '=' * 64)
    for name, port, _ in procs:
        print(f'  {name:<9} http://{args.host}:{port}/')
    print(f'  System health: http://{args.host}:8000/api/system/health/')
    print('  Ctrl+C để dừng toàn bộ')
    print('=' * 64 + '\n')

    stopping = False

    def shutdown(*_):
        nonlocal stopping
        if stopping:
            return
        stopping = True
        print('\nĐang dừng các service...')
        for _, _, proc in procs:
            if proc.poll() is None:
                proc.terminate()
        for _, _, proc in procs:
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    try:
        while not stopping:
            for name, port, proc in procs:
                if proc.poll() is not None and not stopping:
                    print(f'⚠️  {name} (:{port}) đã dừng với exit code {proc.returncode}. '
                          f'Gateway sẽ báo service này DOWN.')
                    procs.remove((name, port, proc))
                    break
            if not procs:
                break
            time.sleep(1)
    finally:
        shutdown()
    return 0


if __name__ == '__main__':
    sys.exit(main())
