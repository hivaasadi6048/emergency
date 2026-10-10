from rest_framework import serializers

from accounts.phone import normalize_phone

from .models import TrustedContact


class TrustedContactSerializer(serializers.ModelSerializer):
    class Meta:
        model = TrustedContact
        fields = ["id", "name", "phone", "relationship", "priority", "is_active", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate_phone(self, value: str) -> str:
        try:
            return normalize_phone(value)
        except Exception:
            raise serializers.ValidationError("phone_invalid")


class TrustedContactWriteSerializer(TrustedContactSerializer):
    def validate(self, attrs):
        user = self.context["request"].user
        phone = attrs.get("phone")
        qs = TrustedContact.objects.filter(user=user, phone=phone, is_active=True)
        if self.instance is not None:
            qs = qs.exclude(pk=self.instance.pk)
        if phone and qs.exists():
            raise serializers.ValidationError({"phone": ["contact_duplicate_active"]})
        return attrs
