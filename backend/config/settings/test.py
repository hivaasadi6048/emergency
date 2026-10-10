"""Test settings: same engine, dedicated clean test database, fixed secret."""
from .base import *  # noqa: F401,F403

DEBUG = False
SECRET_KEY = "test-only-secret-key-not-for-production"
ALLOWED_HOSTS = ["*"]
OTP_DEV_MODE = True  # tests need the code to verify the flow end-to-end

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ.get("DJANGO_TEST_DB_NAME", "test_emergency_dev"),  # noqa: F405
        "USER": os.environ.get("DJANGO_DB_USER", "postgres"),  # noqa: F405
        "PASSWORD": os.environ.get("DJANGO_DB_PASSWORD", ""),  # noqa: F405
        "HOST": os.environ.get("DJANGO_DB_HOST", "127.0.0.1"),  # noqa: F405
        "PORT": os.environ.get("DJANGO_DB_PORT", "5433"),  # noqa: F405
        "TEST": {"NAME": os.environ.get("DJANGO_TEST_DB_NAME", "test_emergency_dev")},
    }
}

# deterministic throttling in tests
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "emergency-test-cache",
    }
}
