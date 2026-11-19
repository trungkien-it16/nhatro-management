"""
URL của TOOLBOX settings — chỉ Django admin tổng hợp để debug.
API thực tế được phục vụ bởi từng service process và truy cập qua API Gateway (:8000).
"""
from django.contrib import admin
from django.urls import path

urlpatterns = [
    path('admin/', admin.site.urls),
]
