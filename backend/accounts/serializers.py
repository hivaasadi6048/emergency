import re

from rest_framework import serializers

from .models import User
from .phone import normalize_phone

RAW_PHONE_RE = re.compile(r"^[\d\s()+\-.]+$")


class RequestOtpSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=32)

    def validate_phone(self, value: str) -> str:
        # generic feedback only — never leak whether a phone exists
        if not RAW_PHONE_RE.match(value or ""):
            raise serializers.ValidationError("phone_invalid")
        try:
            return normalize_phone(value)
        except Exception:
            raise serializers.ValidationError("phone_invalid")


class VerifyOtpSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=32)
    code = serializers.CharField(max_length=8)
    device_platform = serializers.ChoiceField(choices=[("ANDROID", "ANDROID")], required=False, allow_null=True)
    device_identifier = serializers.CharField(max_length=255, required=False, allow_blank=True, allow_null=True)
    app_version = serializers.CharField(max_length=32, required=False, allow_blank=True, allow_null=True)

    def validate_phone(self, value: str) -> str:
        try:
            return normalize_phone(value)
        except Exception:
            raise serializers.ValidationError("phone_invalid")


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "phone", "display_name", "status", "created_at"]
        read_only_fields = ["id", "phone", "status", "created_at"]
