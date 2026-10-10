"""DeliveryAttempt — SENT never implies DELIVERED (docs/failure-model.md §1)."""
import uuid

from django.db import models


class DeliveryAttempt(models.Model):
    class Provider(models.TextChoices):
        WEB = "WEB"
        SMS_GATEWAY = "SMS_GATEWAY"
        FCM = "FCM"
        FUTURE = "FUTURE"

    class Status(models.TextChoices):
        PENDING = "PENDING"
        SENT = "SENT"
        DELIVERED = "DELIVERED"
        FAILED = "FAILED"
        CANCELLED = "CANCELLED"
        EXPIRED = "EXPIRED"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey("emergency.EmergencySession", on_delete=models.CASCADE, related_name="delivery_attempts")
    trusted_contact = models.ForeignKey(
        "contacts.TrustedContact", on_delete=models.SET_NULL, null=True, blank=True, related_name="delivery_attempts"
    )
    provider = models.CharField(max_length=16, choices=Provider.choices)
    channel = models.CharField(max_length=32)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)
    attempt_no = models.PositiveSmallIntegerField(default=1)
    attempted_at = models.DateTimeField()
    delivered_at = models.DateTimeField(null=True, blank=True)
    failed_at = models.DateTimeField(null=True, blank=True)
    provider_message_id = models.CharField(max_length=255, null=True, blank=True)
    error_code = models.CharField(max_length=64, null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            # C-05: idempotent attempts — a retry reuses the same (attempt_no) row
            models.UniqueConstraint(
                fields=["session", "trusted_contact", "provider", "channel", "attempt_no"],
                name="uniq_delivery_attempt_per_target",
            ),
        ]
        indexes = [models.Index(fields=["session"])]
