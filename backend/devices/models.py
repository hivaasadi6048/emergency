import hashlib
import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone


def device_hash(raw_identifier: str) -> str:
    """Raw device identifiers are PII-adjacent — only their SHA-256 is stored
    (docs/data-model.md §3 Device)."""
    return hashlib.sha256((settings.SECRET_KEY + raw_identifier).encode()).hexdigest()


class Device(models.Model):
    class Platform(models.TextChoices):
        ANDROID = "ANDROID"

    class Status(models.TextChoices):
        ACTIVE = "ACTIVE"
        INACTIVE = "INACTIVE"
        REVOKED = "REVOKED"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="devices")
    platform = models.CharField(max_length=16, choices=Platform.choices, default=Platform.ANDROID)
    # SHA-256 of the client-provided identifier; unique per user.
    device_hash = models.CharField(max_length=64)
    app_version = models.CharField(max_length=32, blank=True, default="")
    push_token = models.TextField(blank=True, default="")  # infra metadata only — never an emergency dependency
    last_seen_at = models.DateTimeField(default=timezone.now)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.ACTIVE)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "device_hash"], name="uniq_device_per_user"),
        ]
        indexes = [models.Index(fields=["user"])]

    def touch(self) -> None:
        self.last_seen_at = timezone.now()
        self.save(update_fields=["last_seen_at", "updated_at"])
