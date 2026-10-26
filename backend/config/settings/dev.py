"""Local development settings. Never used in production (Phase 11 adds prod)."""
from .base import *  # noqa: F401,F403

DEBUG = True
ALLOWED_HOSTS = ["*"]

# C-020: the fallback used to be "dev-only-" + secrets.token_hex(32) — a brand-new
# random key on EVERY server boot. Every PC/server restart therefore invalidated ALL
# previously issued JWTs (access AND refresh): the app hammered 401s (token_not_valid)
# with no recovery path until a manual re-login (owner hit this in device test 3:
# 29-min outage + PC restart → refresh loop + stuck UI). Dev must stay env-free
# (see base.py) but the key must be STABLE within the machine. deploy.py still
# REQUIRES DJANGO_SECRET_KEY from the environment, so this fallback never ships.
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-only-fixed-insecure-key-c020-not-for-production")  # noqa: F405

OTP_DEV_MODE = True  # noqa: F405

# C-021 (DEV-ONLY test aid): shorten the access-token lifetime so the refresh
# path (single-flight lock) is exercised on the real device every 5 minutes
# instead of every 15 — one restart boundary lands mid-test without waiting.
# deploy.py never imports this file, and base.py keeps the 15-minute default.
import datetime  # noqa: E402

SIMPLE_JWT["ACCESS_TOKEN_LIFETIME"] = datetime.timedelta(minutes=5)  # noqa: F405
