from django.utils import timezone

from .models import Device, device_hash


def register_device(*, user, platform: str, raw_identifier: str, app_version: str = "", push_token: str = ""):
    """Upsert by (user, device_hash); refreshing last_seen. Returns (device, created)."""
    return Device.objects.update_or_create(
        user=user,
        device_hash=device_hash(raw_identifier),
        defaults={
            "platform": platform,
            "app_version": app_version,
            "push_token": push_token,
            "status": Device.Status.ACTIVE,
            "last_seen_at": timezone.now(),
        },
    )
