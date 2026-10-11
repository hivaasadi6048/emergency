"""
Render.com deployment settings (TEST PHASE) — secrets come ONLY from env vars.

Set in the Render dashboard:
  DJANGO_SECRET_KEY = <random 50+ chars>
  DATABASE_URL      = <Render PostgreSQL Internal Database URL>
  OTP_TEST_MODE     = 1
  OTP_TEST_CODE     = <your chosen 6-digit code>   # TEST ONLY — see services.py
"""
import os

import dj_database_url

from .base import *  # noqa: F401,F403

DEBUG = False

# REQUIRED — the process refuses to start without it (no fallback in deployment).
SECRET_KEY = os.environ["DJANGO_SECRET_KEY"]

# TEST PHASE: the service URL is public. Tightened + CORS/CSRF pinned in Phase 11.
ALLOWED_HOSTS = ["*"]

# REQUIRED — the Render PostgreSQL Internal Database URL. A missing URL means
# the env var was not linked; failing LOUDLY beats silently dialing localhost
# (that exact confusion cost a failed build, change-log B-021).
_DATABASE_URL = os.environ.get("DATABASE_URL")
if not _DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL env var is missing — create the Render PostgreSQL instance "
        "and link it to this Web Service (or paste its Internal Database URL "
        "into the DATABASE_URL environment variable), then redeploy."
    )

DATABASES = {
    "default": dj_database_url.config(
        default=_DATABASE_URL,
        conn_max_age=600,
    )
}

# OTP is NOT shown in responses on the deployed server (OTP_DEV_MODE stays False).
# For the hosted smoke test a FIXED test code is accepted instead (docs/deploy-render.md).
OTP_TEST_MODE = os.environ.get("OTP_TEST_MODE", "") == "1"
OTP_TEST_CODE = os.environ.get("OTP_TEST_CODE", "")
