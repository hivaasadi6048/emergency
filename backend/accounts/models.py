import uuid

from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.contrib.auth.models import PermissionsMixin
from django.db import models
from django.utils import timezone


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, phone, display_name="", **extra_fields):
        if not phone:
            raise ValueError("phone_required")
        user = self.model(phone=phone, display_name=display_name, **extra_fields)
        user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_superuser(self, phone, display_name="", password=None, **extra_fields):
        user = self.create_user(phone, display_name, **extra_fields)
        user.is_staff = True
        user.is_superuser = True
        user.save(using=self._db)
        return user


class User(AbstractBaseUser, PermissionsMixin):
    class Status(models.TextChoices):
        ACTIVE = "ACTIVE"
        SUSPENDED = "SUSPENDED"
        DELETED = "DELETED"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # E.164 normalized by accounts.phone.normalize_phone before save.
    phone = models.CharField(max_length=16, unique=True, db_index=True)
    display_name = models.CharField(max_length=120, blank=True, default="")
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.ACTIVE)

    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = "phone"
    REQUIRED_FIELDS: list[str] = []

    def __str__(self) -> str:
        # never print raw phone in logs; expose a masked form
        return f"User<{self.phone[:5]}****{self.phone[-2:] if len(self.phone) > 7 else ''}>"


class OtpCode(models.Model):
    """Hashed OTP with expiry and attempt limiting (docs/api-contract.md §2).

    The raw code is never stored; only SHA-256(code + server salt).
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    phone = models.CharField(max_length=16, db_index=True)
    code_hash = models.CharField(max_length=64)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    consumed = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["phone", "created_at"])]

    def is_expired(self) -> bool:
        return timezone.now() >= self.expires_at
