"""Emergency domain models (docs/data-model.md §3).

Phase 2 delivers the schema and DB-level guarantees; the APIs and the state
machine enforcement are Phase 3 (docs/state-machine.md).
"""
import uuid

from django.conf import settings
from django.db import models


# IDLE is conceptual (no row). These are the "active" statuses for C-01.
# Module-level: class-body names are not visible inside a nested Meta class.
ACTIVE_SESSION_STATUSES = [
    "TRIGGERED",
    "STARTING",
    "ACTIVE",
    "DEGRADED",
    "RESOLVING",
]


class EmergencySession(models.Model):
    class Status(models.TextChoices):
        TRIGGERED = "TRIGGERED"
        STARTING = "STARTING"
        ACTIVE = "ACTIVE"
        DEGRADED = "DEGRADED"
        RESOLVING = "RESOLVING"
        RESOLVED = "RESOLVED"
        CANCELLED = "CANCELLED"
        FAILED = "FAILED"

    class TriggerType(models.TextChoices):
        IN_APP_SOS = "IN_APP_SOS"  # core MVP
        VOLUME_SEQUENCE = "VOLUME_SEQUENCE"  # EXPERIMENTAL (D-13)
        SAFETY_TIMER = "SAFETY_TIMER"
        FUTURE_WEARABLE = "FUTURE_WEARABLE"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="sessions")
    device = models.ForeignKey("devices.Device", on_delete=models.SET_NULL, null=True, blank=True, related_name="sessions")
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.TRIGGERED)
    trigger_type = models.CharField(max_length=24, choices=TriggerType.choices)

    started_at = models.DateTimeField(auto_now_add=True)
    activated_at = models.DateTimeField(null=True, blank=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    last_location_at = models.DateTimeField(null=True, blank=True)
    last_contact_attempt_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            # C-01: at most ONE active session per user, enforced at DB level
            models.UniqueConstraint(
                fields=["user"],
                condition=models.Q(status__in=ACTIVE_SESSION_STATUSES),
                name="uniq_active_session_per_user",
            ),
        ]
        indexes = [
            models.Index(fields=["user", "created_at"]),
            models.Index(fields=["status"]),
        ]


class EmergencyEvent(models.Model):
    class EventType(models.TextChoices):
        SESSION_CREATED = "SESSION_CREATED"
        TRIGGER_RECEIVED = "TRIGGER_RECEIVED"
        TRIGGER_DUPLICATE_IGNORED = "TRIGGER_DUPLICATE_IGNORED"
        LOCATION_SERVICE_STARTED = "LOCATION_SERVICE_STARTED"
        FIRST_LOCATION_RECEIVED = "FIRST_LOCATION_RECEIVED"
        ALERT_ATTEMPTED = "ALERT_ATTEMPTED"
        ALERT_RESULT = "ALERT_RESULT"
        NETWORK_LOST = "NETWORK_LOST"
        NETWORK_RESTORED = "NETWORK_RESTORED"
        STATE_CHANGED = "STATE_CHANGED"
        SESSION_RESOLVED = "SESSION_RESOLVED"
        SESSION_CANCELLED = "SESSION_CANCELLED"
        SESSION_FAILED = "SESSION_FAILED"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(EmergencySession, on_delete=models.CASCADE, related_name="events")
    event_type = models.CharField(max_length=32, choices=EventType.choices)
    # closed schema, bounded size is enforced at the API layer (Phase 3)
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["session", "created_at"])]  # C-04


class AccessLink(models.Model):
    """Signed, short-lived, revocable viewer access (docs/data-model.md §3 [افزوده])."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(EmergencySession, on_delete=models.CASCADE, related_name="access_links")
    token_hash = models.CharField(max_length=64, unique=True)  # raw token shown once, never stored
    expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["session"])]


class IdempotencyKey(models.Model):
    """Idempotency store for session creation, location upload, resolve, alerts
    (docs/data-model.md §3 [افزوده]; docs/api-contract.md §1)."""

    class Status(models.TextChoices):
        IN_PROGRESS = "IN_PROGRESS"
        COMPLETED = "COMPLETED"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="idempotency_keys")
    endpoint = models.CharField(max_length=128)
    key = models.CharField(max_length=128)
    request_hash = models.CharField(max_length=64)
    response_code = models.PositiveSmallIntegerField(null=True, blank=True)
    response_body = models.JSONField(null=True, blank=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.IN_PROGRESS)
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "endpoint", "key"], name="uniq_idempotency_key"),
        ]
