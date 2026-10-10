"""LocationPoint ingestion schema (docs/data-model.md §3)."""
import uuid

from django.db import models


class LocationPoint(models.Model):
    class Source(models.TextChoices):
        FGS_GPS = "FGS_GPS"
        FGS_NETWORK = "FGS_NETWORK"
        QUEUED_OFFLINE = "QUEUED_OFFLINE"
        MANUAL = "MANUAL"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey("emergency.EmergencySession", on_delete=models.CASCADE, related_name="locations")
    # client-generated dedupe key — the idempotency base for uploads (C-02)
    client_uuid = models.UUIDField()
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    accuracy_m = models.FloatField(null=True, blank=True)
    altitude_m = models.FloatField(null=True, blank=True)
    speed_mps = models.FloatField(null=True, blank=True)
    heading_deg = models.FloatField(null=True, blank=True)
    # captured_at = device time; received_at = server time — always separate
    captured_at = models.DateTimeField()
    received_at = models.DateTimeField(auto_now_add=True)
    source = models.CharField(max_length=24, choices=Source.choices)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["session", "client_uuid"], name="uniq_location_client_uuid"),  # C-02
            models.CheckConstraint(condition=models.Q(latitude__gte=-90, latitude__lte=90), name="chk_latitude_range"),
            models.CheckConstraint(condition=models.Q(longitude__gte=-180, longitude__lte=180), name="chk_longitude_range"),
        ]
        indexes = [models.Index(fields=["session", "captured_at"])]  # C-03
