@echo off
chcp 65001 >nul
echo ============================================================================
echo 🚀 KHOI DONG TOAN BO HE THONG SOA MICROSERVICES (PORT 8000 den 8005)
echo ============================================================================
"%~dp0backend\venv\Scripts\python.exe" "%~dp0backend\run_all_services.py" %*

