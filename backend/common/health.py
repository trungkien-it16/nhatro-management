from django.conf import settings
from django.db import connections
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView


def check_database(alias='default'):
    """Ping database thật bằng SELECT 1. Trả về (status, error)."""
    try:
        with connections[alias].cursor() as cursor:
            cursor.execute('SELECT 1')
            row = cursor.fetchone()
        return ('UP' if row and row[0] == 1 else 'DOWN'), None
    except Exception as exc:  # noqa: BLE001 - health check phải bắt mọi lỗi kết nối
        return 'DOWN', str(exc)


class HealthCheckView(APIView):
    """
    GET /health/ — trạng thái thực tế của service đang chạy.
    200 + status=UP khi service và database của nó hoạt động, 503 + status=DOWN nếu DB lỗi.
    """
    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        db_status, db_error = check_database()
        db_settings = settings.DATABASES['default']
        body = {
            'service': getattr(settings, 'SERVICE_NAME', 'unknown'),
            'key': getattr(settings, 'SERVICE_KEY', 'unknown'),
            'port': getattr(settings, 'SERVICE_PORT', None),
            'status': 'UP' if db_status == 'UP' else 'DOWN',
            'database': {
                'status': db_status,
                'engine': db_settings.get('ENGINE', '').split('.')[-1],
                'name': str(db_settings.get('NAME', '')).split('/')[-1].split('\\')[-1],
            },
            'checked_at': timezone.now().isoformat(),
        }
        if db_error:
            body['database']['error'] = db_error
        code = status.HTTP_200_OK if body['status'] == 'UP' else status.HTTP_503_SERVICE_UNAVAILABLE
        return Response(body, status=code)
