import logging

from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from devices.services import register_device

from .serializers import RequestOtpSerializer, UserSerializer, VerifyOtpSerializer
from .services import OtpError, issue_otp, verify_otp

logger = logging.getLogger(__name__)


def _error(code: str, http: int, message: str) -> Response:
    return Response({"error": {"code": code, "message": message}}, status=http)


class RequestOtpView(APIView):
    """POST /api/v1/auth/request-otp — always 200 on success (no phone enumeration).

    Rate limiting is service-level (per-phone, DB-backed, docs/services.py) —
    cache-based DRF throttling is deliberately not used here so the limit
    survives process restarts and behaves identically across workers.
    """

    authentication_classes: list = []
    permission_classes: list = []

    def post(self, request):
        serializer = RequestOtpSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            _phone, debug_code = issue_otp(serializer.validated_data["phone"])
        except OtpError as exc:
            return _error(exc.code, status.HTTP_429_TOO_MANY_REQUESTS, "otp rate limited")
        payload: dict = {"detail": "otp_sent"}
        if debug_code is not None:
            # OTP_DEV_MODE only (dev/test). Never enabled in production.
            payload["debug_code"] = debug_code
        return Response(payload, status=status.HTTP_200_OK)


class VerifyOtpView(APIView):
    """POST /api/v1/auth/verify-otp — returns JWT pair (+ registers the device)."""

    authentication_classes: list = []
    permission_classes: list = []

    def post(self, request):
        serializer = VerifyOtpSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            user = verify_otp(data["phone"], data["code"])
        except OtpError as exc:
            http = status.HTTP_429_TOO_MANY_REQUESTS if exc.code == "otp_rate_limited" else status.HTTP_400_BAD_REQUEST
            return _error(exc.code, http, "otp verification failed")

        device = None
        if data.get("device_identifier") and data.get("device_platform"):
            device, _created = register_device(
                user=user,
                platform=data["device_platform"],
                raw_identifier=data["device_identifier"],
                app_version=data.get("app_version") or "",
            )
        refresh = RefreshToken.for_user(user)
        # no tokens or phone values in logs — enforced by the logging policy test
        logger.info("auth.otp_verified user=%s device=%s", user.id, getattr(device, "id", None))
        return Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "user": UserSerializer(user).data,
                "device": {"id": str(device.id)} if device else None,
            },
            status=status.HTTP_200_OK,
        )


class LogoutView(APIView):
    """POST /api/v1/auth/logout {refresh} — blacklists the refresh token.

    Possession of a valid refresh token is the proof of identity here, so the
    view is deliberately public; an invalid token gets a generic 400.
    """

    authentication_classes: list = []
    permission_classes: list = []

    def post(self, request):
        raw = request.data.get("refresh") or ""
        try:
            RefreshToken(raw).blacklist()
        except Exception:
            return _error("VALIDATION_ERROR", status.HTTP_400_BAD_REQUEST, "invalid refresh token")
        return Response(status=status.HTTP_204_NO_CONTENT)


class MeView(APIView):
    def get(self, request):
        return Response(UserSerializer(request.user).data)

    def patch(self, request):
        serializer = UserSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
