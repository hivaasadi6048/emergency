from rest_framework import serializers

from .models import Device


class DeviceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Device
        fields = ["id", "platform", "device_hash", "app_version", "push_token", "last_seen_at", "status"]
        read_only_fields = ["id", "device_hash", "last_seen_at", "status"]

    push_token = serializers.CharField(write_only=True, required=False, allow_blank=True)
