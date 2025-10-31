# Controller Node - Horizon 대시보드 설정
# Django 기반 OpenStack 공식 웹 UI
# 접속 주소: http://192.168.0.10/horizon

OPENSTACK_HOST = "10.0.0.10"

# Memcached 세션 백엔드
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.memcached.PyMemcacheCache',
        'LOCATION': '10.0.0.10:11211',
    }
}

OPENSTACK_KEYSTONE_URL = "http://%s:5000/identity/v3" % OPENSTACK_HOST

# 멀티도메인 지원 활성화
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True

OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 3,
}

OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "Default"
OPENSTACK_KEYSTONE_DEFAULT_ROLE = "member"

TIME_ZONE = "Asia/Seoul"
COMPRESS_OFFLINE = False
