import uuid

from django.db import IntegrityError, transaction
from django.test import TestCase
from django.utils import timezone

from accounts.models import User
from emergency.models import EmergencySession
from locations.models import LocationPoint

PHONE = "+989121234567"


class LocationPointConstraintTests(TestCase):
    def setUp(self):
        user = User.objects.create_user(PHONE)
        self.session = EmergencySession.objects.create(
            user=user, status=EmergencySession.Status.ACTIVE, trigger_type=EmergencySession.TriggerType.IN_APP_SOS
        )
        self.base = dict(
            session=self.session,
            latitude=35.7,
            longitude=51.4,
            source=LocationPoint.Source.FGS_GPS,
        )

    def _point(self, client_uuid, captured_at=None, **overrides):
        payload = {
            **self.base,
            "client_uuid": client_uuid,
            "captured_at": captured_at or timezone.now(),
            **overrides,
        }
        return LocationPoint.objects.create(**payload)

    def test_duplicate_client_uuid_rejected_c02(self):
        fixed = uuid.UUID(int=42)
        self._point(fixed)
        with transaction.atomic():
            with self.assertRaises(IntegrityError):
                self._point(fixed)
        # a different uuid on the same session is fine
        self._point(uuid.UUID(int=43))

    def test_latitude_range_enforced(self):
        with transaction.atomic():
            with self.assertRaises(IntegrityError):
                self._point(uuid.uuid4(), latitude=91.0)

    def test_longitude_range_enforced(self):
        with transaction.atomic():
            with self.assertRaises(IntegrityError):
                self._point(uuid.uuid4(), longitude=-180.5)

    def test_ordering_by_captured_at_supports_timeline_c03(self):
        now = timezone.now()
        self._point(uuid.uuid4(), captured_at=now - timezone.timedelta(minutes=2))
        self._point(uuid.uuid4(), captured_at=now - timezone.timedelta(minutes=1))
        points = list(LocationPoint.objects.filter(session=self.session).order_by("captured_at"))
        self.assertEqual(len(points), 2)
        self.assertLess(points[0].captured_at, points[1].captured_at)
