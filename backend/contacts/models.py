import uuid

from django.conf import settings
from django.db import models


class TrustedContact(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="contacts")
    name = models.CharField(max_length=120)
    # E.164 normalized at the serializer boundary.
    phone = models.CharField(max_length=16)
    relationship = models.CharField(max_length=64, blank=True, default="")
    priority = models.SmallIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "phone"],
                condition=models.Q(is_active=True),
                name="uniq_active_contact_phone_per_user",
            ),
        ]
        indexes = [models.Index(fields=["user"]), models.Index(fields=["user", "priority"])]

    def __str__(self) -> str:
        return f"TrustedContact<{self.user_id}:{self.name}>"
