from django.db import IntegrityError
from django.test import TestCase

from accounts.models import User
from emergency.models import EmergencySession

PHONE = "+989121234567"


class SessionConstraintTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(PHONE)

    def _create(self, status=EmergencySession.Status.ACTIVE, trigger=EmergencySession.TriggerType.IN_APP_SOS):
        return EmergencySession.objects.create(user=self.user, status=status, trigger_type=trigger)

    def test_only_one_active_session_per_user_c01(self):
        from django.db import transaction

        self._create()
        with transaction.atomic():
            with self.assertRaises(IntegrityError):
                self._create()

    def test_final_status_allows_new_session(self):
        from django.db import transaction

        first = self._create()
        with transaction.atomic():
            with self.assertRaises(IntegrityError):
                self._create()  # duplicate while first is still active
        first.status = EmergencySession.Status.RESOLVED
        first.save()
        second = self._create()  # allowed after a final status
        self.assertNotEqual(first.id, second.id)

    def test_distinct_users_independent(self):
        from accounts.models import User

        other = User.objects.create_user("+989122222222")
        self._create()
        EmergencySession.objects.create(user=other, status=EmergencySession.Status.ACTIVE, trigger_type=EmergencySession.TriggerType.IN_APP_SOS)
        self.assertEqual(EmergencySession.objects.count(), 2)
