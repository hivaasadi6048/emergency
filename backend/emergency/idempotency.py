"""Idempotency service (docs/api-contract.md §1, docs/data-model.md IdempotencyKey).

Contract for endpoints requiring an Idempotency-Key:
- first call with a key: executes and stores the response snapshot;
- replay (same key + same request hash): returns the stored response with
  `Idempotency-Replayed: true`;
- same key with a DIFFERENT body: 409 IDEMPOTENCY_KEY_REUSED;
- same key while a previous identical request is still in progress: 409
  IDEMPOTENCY_IN_PROGRESS.
"""
import hashlib
import json

from django.utils import timezone
from rest_framework.exceptions import APIException

from .models import IdempotencyKey


class IdempotencyKeyReused(APIException):
    status_code = 409
    default_code = "IDEMPOTENCY_KEY_REUSED"
    default_detail = "idempotency key already used with a different request body"


class IdempotencyInProgress(APIException):
    status_code = 409
    default_code = "IDEMPOTENCY_IN_PROGRESS"
    default_detail = "an identical request with this key is still in progress"


def request_hash(payload) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(raw.encode()).hexdigest()


def begin(user, endpoint: str, key: str, payload) -> IdempotencyKey:
    """Create-or-attach to the idempotency record. Caller runs inside a transaction
    and must call `complete()` (or discard) afterwards."""
    payload_hash = request_hash(payload)
    obj, created = IdempotencyKey.objects.get_or_create(
        user=user,
        endpoint=endpoint,
        key=key,
        defaults={
            "request_hash": payload_hash,
            "status": IdempotencyKey.Status.IN_PROGRESS,
            "expires_at": timezone.now() + timezone.timedelta(hours=24),
        },
    )
    if not created:
        if obj.request_hash != payload_hash:
            raise IdempotencyKeyReused()
        if obj.status == IdempotencyKey.Status.COMPLETED:
            raise Replay(obj)
        if obj.status == IdempotencyKey.Status.IN_PROGRESS:
            raise IdempotencyInProgress()
    return obj


class Replay(Exception):
    """Raised when a completed key is replayed — the view returns the stored response."""

    def __init__(self, record: IdempotencyKey):
        self.record = record
        super().__init__("replay")


def complete(record: IdempotencyKey, status_code: int, data) -> None:
    record.status = IdempotencyKey.Status.COMPLETED
    record.response_code = status_code
    record.response_body = data
    record.save(update_fields=["status", "response_code", "response_body"])


def discard(record: IdempotencyKey) -> None:
    """On handler failure the key stays IN_PROGRESS and expires; delete it so the
    client can retry immediately with the same key."""
    record.delete()
