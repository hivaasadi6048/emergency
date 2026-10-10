"""Unified error envelope: {"error": {"code", "message", "details"}} — docs/api-contract.md §1."""
from rest_framework.views import exception_handler as drf_exception_handler

CODE_MAP = {
    "Http404": "NOT_FOUND",
    "NotFound": "NOT_FOUND",
    "NotAuthenticated": "UNAUTHORIZED",
    "AuthenticationFailed": "UNAUTHORIZED",
    "PermissionDenied": "FORBIDDEN",
    "MethodNotAllowed": "VALIDATION_ERROR",
    "ParseError": "VALIDATION_ERROR",
    "ValidationError": "VALIDATION_ERROR",
    "Throttled": "RATE_LIMITED",
}


def error_handler(exc, response):
    """Wrap DRF's default body in the stable error envelope."""
    response = drf_exception_handler(exc, response)
    if response is None:
        return None
    # known DRF exception types map to contract codes first; our custom
    # APIException subclasses carry their own stable default_code
    code = CODE_MAP.get(type(exc).__name__) or getattr(exc, "default_code", None) or "INTERNAL_ERROR"
    if isinstance(response.data, dict) and set(response.data.keys()) == {"error"}:
        return response  # already enveloped
    details = response.data if isinstance(response.data, dict) else {"non_field": response.data}
    response.data = {"error": {"code": code, "message": _message(code), "details": details}}
    return response


def _message(code: str) -> str:
    return {
        "VALIDATION_ERROR": "request validation failed",
        "UNAUTHORIZED": "authentication required",
        "FORBIDDEN": "access denied",
        "NOT_FOUND": "resource not found",
        "RATE_LIMITED": "too many requests",
        "INTERNAL_ERROR": "internal error",
    }.get(code, "error")
