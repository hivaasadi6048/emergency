"""Local development settings. Never used in production (Phase 11 adds prod)."""
import secrets

from .base import *  # noqa: F401,F403

DEBUG = True
ALLOWED_HOSTS = ["*"]

# Dev-only fallback so the local cluster runs without env setup. In production
# settings this fallback must not exist (Phase 11).
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-only-" + secrets.token_hex(32))  # noqa: F405

OTP_DEV_MODE = True  # noqa: F405
