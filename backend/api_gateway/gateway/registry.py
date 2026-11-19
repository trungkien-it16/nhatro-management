from django.conf import settings


def services():
    return settings.SERVICE_REGISTRY


def service_for_path(path):
    """'rooms/12/status/' -> ('property', config) theo prefix đầu tiên của path."""
    prefix = path.strip('/').split('/', 1)[0]
    for key, conf in settings.SERVICE_REGISTRY.items():
        if prefix in conf['prefixes']:
            return key, conf
    return None, None


def route_table():
    return {
        f'/api/{prefix}/': {'service': conf['name'], 'port': conf['port']}
        for conf in settings.SERVICE_REGISTRY.values()
        for prefix in conf['prefixes']
    }
