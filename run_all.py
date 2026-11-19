"""
File khởi chạy toàn bộ hệ thống SOA Microservices (Port 8000 -> 8005).
Chạy lệnh:
    python run_all.py
hoặc:
    backend\\venv\\Scripts\\python.exe run_all.py
"""
import os
import subprocess
import sys

if __name__ == '__main__':
    root_dir = os.path.dirname(os.path.abspath(__file__))
    venv_python = os.path.join(root_dir, 'backend', 'venv', 'Scripts', 'python.exe')
    python_exe = venv_python if os.path.exists(venv_python) else sys.executable
    runner_script = os.path.join(root_dir, 'backend', 'run_all_services.py')
    sys.exit(subprocess.call([python_exe, runner_script] + sys.argv[1:]))

