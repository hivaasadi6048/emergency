from rest_framework import serializers

from .models import EmergencySession


class StrictSerializer(serializers.Serializer):
    """Reject unknown fields loudly — a client cannot smuggle e.g. `status`."""

    def to_internal_value(self, data):
        unknown = set(data) - set(self.fields)
        if unknown:
            raise serializers.ValidationError({k: ["unknown_field"] for k in unknown})
        return super().to_internal_value(data)


class CreateSessionSerializer(StrictSerializer):
    """Client sends ACTIONS and facts — never a status (docs/state-machine.md §4)."""

    trigger_type = serializers.ChoiceField(choices=EmergencySession.TriggerType.choices)
    device_id = serializers.UUIDField(required=False, allow_null=True)


class CapabilityReportSerializer(serializers.Serializer):
    location_capability = serializers.ChoiceField(choices=["ACTIVE", "DEGRADED", "FAILED"])
    network_ok = serializers.BooleanField()


class SessionSerializer(serializers.ModelSerializer):
    class Meta:
        model = EmergencySession
        fields = [
            "id",
            "status",
            "trigger_type",
            "started_at",
            "activated_at",
            "resolved_at",
            "last_location_at",
            "created_at",
        ]
        read_only_fields = fields


class SessionDetailSerializer(SessionSerializer):
    latest_location = serializers.SerializerMethodField()

    class Meta(SessionSerializer.Meta):
        fields = SessionSerializer.Meta.fields + ["latest_location"]

    def get_latest_location(self, obj):
        point = obj.locations.order_by("-captured_at").first()
        if point is None:
            return None
        return {
            "client_uuid": str(point.client_uuid),
            "latitude": str(point.latitude),
            "longitude": str(point.longitude),
            "accuracy_m": point.accuracy_m,
            "captured_at": point.captured_at,
            "source": point.source,
        }
