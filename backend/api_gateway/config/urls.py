from django.urls import path, re_path

from gateway import views

urlpatterns = [
    path('', views.index, name='gateway-index'),
    path('health/', views.gateway_health, name='gateway-health'),

    # Endpoint do chính Gateway xử lý (đặt trước catch-all proxy)
    path('api/system/health/', views.system_health, name='system-health'),
    path('api/dashboard/summary/', views.dashboard_summary, name='dashboard-summary'),
    path('api/system/services/<str:key>/endpoints/', views.service_endpoints, name='service-endpoints'),

    # Tương thích ngược với client cũ dùng /api/v1/...
    re_path(r'^api/v1/(?P<path>.+)$', views.legacy_v1_proxy, name='legacy-v1-proxy'),

    # Routing tới service sở hữu prefix
    re_path(r'^api/(?P<path>.+)$', views.proxy, name='proxy'),
]
