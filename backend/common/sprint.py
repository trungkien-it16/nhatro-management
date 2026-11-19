"""
Khóa tạm các API nghiệp vụ chưa thuộc phạm vi Sprint hiện tại (quyết định D3).

Source code nghiệp vụ được GIỮ NGUYÊN; chỉ chặn ở tầng permission của backend để không thể
gọi trực tiếp API (không chỉ ẩn nút trên giao diện). Mở lại ở Sprint sau bằng cách đặt
SPRINT_FEATURE_LOCK=False (biến môi trường) hoặc bỏ action khỏi `sprint_locked_actions`.

Khai báo trên ViewSet:
    sprint_locked_actions = ('create', 'pay', 'history:POST')
    -> 'action' khóa mọi method; 'action:METHOD' chỉ khóa method đó.
"""
from django.conf import settings
from rest_framework import permissions


class SprintFeatureLock(permissions.BasePermission):
    message = 'Chức năng này chưa được mở trong Sprint hiện tại (tạm khóa ở backend).'
    code = 'feature_locked'

    def has_permission(self, request, view):
        if not getattr(settings, 'SPRINT_FEATURE_LOCK', True):
            return True
        locked = getattr(view, 'sprint_locked_actions', ())
        action = getattr(view, 'action', None)
        return not (action in locked or f'{action}:{request.method}' in locked)
