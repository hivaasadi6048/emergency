"""POST /api/v1/locations — batch ingestion tests (Phase 3 acceptance)."""
import uuid
from datetime import timedelta

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User
from emergency.models import EmergencyEvent, EmergencySession
from emergency.services import create_session, report_capability
from locations.models import LocationPoint

PHONE_A = "+989121234567"
PHONE_B = "+989122222222"


def point(client_uuid=None, captured_at=None, lat="35.700000", lng="51.400000"):
    return {
        "client_uuid": str(client_uuid or uuid.uuid4()),
        "latitude": lat,
        "longitude": lng,
        "accuracy_m": 12.0,
        "captured_at": (captured_at or timezone.now()).isoformat(),
        "source": "FGS_GPS",
    }


class LocationUploadTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(PHONE_A)
        self.other = User.objects.create_user(PHONE_B)
        self.client.force_authenticate(self.user)
        session, _ = create_session(user=self.user, trigger_type="IN_APP_SOS")
        self.session = report_capability(self.user, session.id, location_capability="ACTIVE", network_ok=True)[0]

    def upload(self, points, session_id=None, key=None):
        return self.client.post(
            reverse("locations-upload"),
            {"session_id": str(session_id or self.session.id), "points": points},
            format="json",
            HTTP_IDEMPOTENCY_KEY=key or str(uuid.uuid4()),
        )

    def test_batch_accepted_and_first_location_event(self):
        response = self.upload([point(), point()])
        self.assertEqual(response.status_code, 202, response.content)
        self.assertEqual(len(response.data["accepted"]), 2)
        self.session.refresh_from_db()
        self.assertIsNotNone(self.session.last_location_at)
        self.assertTrue(
            EmergencyEvent.objects.filter(session=self.session, event_type="FIRST_LOCATION_RECEIVED").exists()
        )

    def test_first_location_event_only_once(self):
        self.upload([point()])
        self.upload([point()])
        self.assertEqual(
            EmergencyEvent.objects.filter(session=self.session, event_type="FIRST_LOCATION_RECEIVED").count(), 1
        )

    def test_duplicate_client_uuid_reported_not_created(self):
        fixed = uuid.uuid4()
        self.upload([point(fixed)])
        response = self.upload([point(fixed)], key=str(uuid.uuid4()))
        self.assertEqual(response.status_code, 202)
        self.assertEqual(response.data["duplicates"], [str(fixed)])
        self.assertEqual(response.data["accepted"], [])
        self.assertEqual(LocationPoint.objects.filter(session=self.session).count(), 1)

    def test_same_idempotency_key_replays_without_new_rows(self):
        key = str(uuid.uuid4())
        body = [point()]
        first = self.upload(body, key=key)
        second = self.upload(body, key=key)  # SAME body + SAME key -> replay
        self.assertTrue(second.has_header("Idempotency-Replayed"))
        self.assertEqual(second.data, first.data)
        self.assertEqual(LocationPoint.objects.filter(session=self.session).count(), 1)

    def test_clock_skew_rejected(self):
        stale = point(captured_at=timezone.now() - timedelta(minutes=30))
        future = point(captured_at=timezone.now() + timedelta(hours=2))
        fresh = point()
        response = self.upload([stale, future, fresh])
        self.assertEqual(response.status_code, 202)
        rejected = {r["client_uuid"]: r["reason"] for r in response.data["rejected"]}
        self.assertEqual(rejected[stale["client_uuid"]], "clock_skew")
        self.assertEqual(rejected[future["client_uuid"]], "clock_skew")
        self.assertEqual(len(response.data["accepted"]), 1)

    def test_invalid_coordinates_rejected_per_point(self):
        bad = point(lat="95.0")
        good = point()
        response = self.upload([bad, good])
        self.assertEqual(response.status_code, 202)
        rejected_uuids = {r["client_uuid"] for r in response.data["rejected"]}
        self.assertIn(bad["client_uuid"], rejected_uuids)
        self.assertIn(good["client_uuid"], response.data["accepted"])

    def test_upload_to_resolved_session_rejected(self):
        self.client.post(
            reverse("emergency-resolve", args=[self.session.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4())
        )
        response = self.upload([point()])
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "CONFLICT_INVALID_TRANSITION")

    def test_other_users_session_is_404(self):
        session_b, _ = create_session(user=self.other, trigger_type="IN_APP_SOS")
        response = self.upload([point()], session_id=session_b.id)
        self.assertEqual(response.status_code, 404)

    def test_missing_idempotency_key_rejected(self):
        response = self.client.post(
            reverse("locations-upload"),
            {"session_id": str(self.session.id), "points": [point()]},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "MISSING_IDEMPOTENCY_KEY")
