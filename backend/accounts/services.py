"""OTP issue/verify service (Phase 2 dev mode — no SMS gateway yet, Q-01)."""
import hashlib
import secrets
from datetime import timedelta

import hmac as hmac_lib

from django.conf import settings
from django.core.exceptions import ValidationError
from django.utils import timezone

from .models import OtpCode, User
from .phone import normalize_phone

CODE_LENGTH = 6


def _hash_code(phone: str, code: str) -> str:
    salt = settings.SECRET_KEY
    return hashlib.sha256(f"{phone}:{code}:{salt}".encode()).hexdigest()


class OtpError(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def issue_otp(raw_phone: str) -> tuple[str, str | None]:
    """Create a fresh OTP for the phone. Returns (phone, debug_code|None).

    Rate limit: OTP_ISSUE_LIMIT per phone per OTP_ISSUE_WINDOW_SECONDS.
    The raw code is returned only when OTP_DEV_MODE is on; production must
    deliver it through an SMS provider (Phase 7 provider pattern).
    """
    phone = normalize_phone(raw_phone)
    window_start = timezone.now() - timedelta(seconds=settings.OTP_ISSUE_WINDOW_SECONDS)
    recent = OtpCode.objects.filter(phone=phone, created_at__gte=window_start).count()
    if recent >= settings.OTP_ISSUE_LIMIT:
        raise OtpError("otp_rate_limited")

    code = f"{secrets.randbelow(10 ** CODE_LENGTH):0{CODE_LENGTH}d}"
    OtpCode.objects.create(
        phone=phone,
        code_hash=_hash_code(phone, code),
        expires_at=timezone.now() + timedelta(seconds=settings.OTP_CODE_TTL_SECONDS),
    )
    debug_code = code if settings.OTP_DEV_MODE else None
    return phone, debug_code


def verify_otp(raw_phone: str, raw_code: str) -> User:
    """Verify the latest unconsumed OTP and return (creating if needed) the user."""
    phone = normalize_phone(raw_phone)
    code = str(raw_code or "").strip()

    # TEST-ONLY bypass for the hosted smoke test (docs/deploy-render.md):
    # no SMS provider exists yet, so a fixed env-var code lets the owner log in.
    # MUST be disabled (OTP_TEST_MODE unset) before any real use — Phase 7
    # replaces this with the real SMS provider.
    if (
        getattr(settings, "OTP_TEST_MODE", False)
        and settings.OTP_TEST_CODE
        and hmac_lib.compare_digest(str(settings.OTP_TEST_CODE), code)
    ):
        user, _created = User.objects.get_or_create(phone=phone, defaults={"display_name": ""})
        if user.status != User.Status.ACTIVE:
            raise OtpError("user_inactive")
        return user

    otp = (
        OtpCode.objects.filter(phone=phone, consumed=False)
        .order_by("-created_at")
        .first()
    )
    if otp is None:
        raise OtpError("otp_not_found")
    if otp.is_expired():
        raise OtpError("otp_expired")
    if otp.attempts >= settings.OTP_MAX_ATTEMPTS:
        raise OtpError("otp_locked")

    otp.attempts += 1
    otp.save(update_fields=["attempts"])

    if not hmac_lib.compare_digest(otp.code_hash, _hash_code(phone, code)):
        raise OtpError("otp_invalid")

    otp.consumed = True
    otp.save(update_fields=["consumed"])

    user, _created = User.objects.get_or_create(phone=phone, defaults={"display_name": ""})
    if user.status != User.Status.ACTIVE:
        raise OtpError("user_inactive")
    return user
