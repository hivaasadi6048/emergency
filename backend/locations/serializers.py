from datetime import timedelta

from django.conf import settings
from rest_framework import serializers

from .models import LocationPoint

BATCH_MAX = 200  # offline queue cap (docs/failure-model.md §4)


class LocationPointInSerializer(serializers.Serializer):
    """Per-point validation — the view collects invalid points instead of
    failing the whole batch (docs/api-contract.md §2 Locations)."""

    client_uuid = serializers.UUIDField()
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-90, max_value=90)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6, min_value=-180, max_value=180)
    accuracy_m = serializers.FloatField(required=False, allow_null=True, min_value=0)
    altitude_m = serializers.FloatField(required=False, allow_null=True)
    speed_mps = serializers.FloatField(required=False, allow_null=True, min_value=0)
    heading_deg = serializers.FloatField(required=False, allow_null=True, min_value=0, max_value=360)
    captured_at = serializers.DateTimeField()
    source = serializers.ChoiceField(choices=LocationPoint.Source.choices)

    def validate_captured_at(self, value):
        # clock-skew policy (docs/failure-model.md #19) — configurable bounds
        from django.utils import timezone

        past = getattr(settings, "LOCATION_CAPTURED_AT_PAST_SECONDS", 300)
        future = getattr(settings, "LOCATION_CAPTURED_AT_FUTURE_SECONDS", 600)
        now = timezone.now()
        if value < now - timedelta(seconds=past) or value > now + timedelta(seconds=future):
            raise serializers.ValidationError("clock_skew")
        return value


class LocationBatchSerializer(serializers.Serializer):
    """Envelope validation only — per-point value checks happen per point."""

    session_id = serializers.UUIDField()
    points = serializers.ListField(child=serializers.DictField(), allow_empty=False, max_length=BATCH_MAX)
