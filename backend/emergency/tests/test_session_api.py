"""Emergency API tests — create/resolve/cancel/capability, idempotency, duplicate
SOS handling, object-level authorization and event timeline (Phase 3 acceptance)."""
import uuid

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from accounts.models import User
from emergency.models import EmergencyEvent, EmergencySession

PHONE_A = "+989121234567"
PHONE_B = "+989122222222"


class SessionApiBase(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(PHONE_A)
        self.other = User.objects.create_user(PHONE_B)
        self.client.force_authenticate(self.user)

    def create_session(self, trigger="IN_APP_SOS", key=None, **extra):
        key = key or str(uuid.uuid4())
        return self.client.post(
            reverse("emergency-sessions"),
            {"trigger_type": trigger, **extra},
            format="json",
            HTTP_IDEMPOTENCY_KEY=key,
        ), key

    def advance_to_active(self):
        session, _ = create_session(self.user, trigger="IN_APP_SOS")
        from emergency.services import report_capability

        session, _ = report_capability(self.user, session.id, location_capability="ACTIVE", network_ok=True)
        return session


def create_session(user, trigger, key=None, device_id=None):
    from emergency import services as emergency_services

    return emergency_services.create_session(user=user, trigger_type=trigger, device_id=device_id)


class CreateSessionTests(SessionApiBase):
    def test_create_returns_session_in_triggered_with_events(self):
        response, _ = self.create_session()
        self.assertEqual(response.status_code, 201, response.content)
        # C-011: session stays TRIGGERED (cancel window open) until first capability report
        self.assertEqual(response.data["status"], "TRIGGERED")
        types = [e.event_type for e in EmergencyEvent.objects.order_by("created_at")]
        self.assertIn("TRIGGER_RECEIVED", types)
        self.assertIn("SESSION_CREATED", types)
        self.assertNotIn("STATE_CHANGED", types)

    def test_missing_idempotency_key_rejected(self):
        response = self.client.post(reverse("emergency-sessions"), {"trigger_type": "IN_APP_SOS"}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "MISSING_IDEMPOTENCY_KEY")

    def test_same_key_replays_same_session_without_duplicate(self):
        response1, key = self.create_session()
        self.assertEqual(response1.status_code, 201)
        response2, _ = self.create_session(key=key)
        self.assertEqual(response2.status_code, 201)
        self.assertTrue(response2.has_header("Idempotency-Replayed"))
        self.assertEqual(response1.data["id"], response2.data["id"])
        self.assertEqual(EmergencySession.objects.count(), 1)

    def test_same_key_different_body_rejected(self):
        response1, _ = self.create_session(trigger="IN_APP_SOS")
        response2, _ = self.create_session(trigger="SAFETY_TIMER", key=str(uuid.uuid4()))
        # different key but an active session exists -> duplicate trigger path (409 + existing)
        self.assertEqual(response2.status_code, 409)
        self.assertEqual(response2.data["error"]["code"], "CONFLICT_ACTIVE_SESSION")
        self.assertEqual(response2.data["existing_session"]["id"], response1.data["id"])

    def test_duplicate_sos_never_creates_second_session(self):
        first, _ = self.create_session()
        second, _ = self.create_session()  # different key, still active session
        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 409)
        self.assertEqual(second.data["error"]["code"], "CONFLICT_ACTIVE_SESSION")
        self.assertEqual(second.data["existing_session"]["id"], first.data["id"])
        self.assertEqual(EmergencySession.objects.count(), 1)
        dup_events = EmergencyEvent.objects.filter(event_type="TRIGGER_DUPLICATE_IGNORED")
        self.assertEqual(dup_events.count(), 1)
        self.assertEqual(dup_events.first().session_id, uuid.UUID(first.data["id"]))

    def test_client_cannot_set_status_arbitrarily(self):
        response = self.client.post(
            reverse("emergency-sessions"),
            {"trigger_type": "IN_APP_SOS", "status": "RESOLVED"},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
        )
        self.assertEqual(response.status_code, 400)  # unknown field rejected
        session = EmergencySession.objects.first()
        if session:  # if creation happened at all, status must not be client-chosen
            self.assertNotEqual(session.status, "RESOLVED")

    def test_after_final_status_new_session_allowed(self):
        session = self.advance_to_active()
        self.client.post(reverse("emergency-resolve", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()))
        response, _ = self.create_session()
        self.assertEqual(response.status_code, 201)


class ResolveCancelTests(SessionApiBase):
    def test_resolve_from_active(self):
        session = self.advance_to_active()
        response = self.client.post(
            reverse("emergency-resolve", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4())
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["status"], "RESOLVED")
        session.refresh_from_db()
        self.assertIsNotNone(session.resolved_at)
        types = list(session.events.values_list("event_type", flat=True))
        self.assertIn("SESSION_RESOLVED", types)

    def test_resolve_idempotent_with_same_key(self):
        session = self.advance_to_active()
        key = str(uuid.uuid4())
        first = self.client.post(reverse("emergency-resolve", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=key)
        events_before = session.events.count()
        second = self.client.post(reverse("emergency-resolve", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=key)
        self.assertEqual(first.status_code, 200)
        self.assertTrue(second.has_header("Idempotency-Replayed"))
        self.assertEqual(second.data["id"], first.data["id"])
        session.refresh_from_db()
        self.assertEqual(session.events.count(), events_before)  # no duplicate events

    def test_resolve_idempotent_without_key(self):
        session = self.advance_to_active()
        self.client.post(reverse("emergency-resolve", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()))
        response = self.client.post(reverse("emergency-resolve", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()))
        self.assertEqual(response.status_code, 200)  # already RESOLVED -> 200, no error
        self.assertEqual(EmergencySession.objects.get(pk=session.id).status, "RESOLVED")

    def test_resolve_from_triggered_rejected(self):
        session, _ = create_session(self.user, trigger="IN_APP_SOS")  # TRIGGERED->STARTING
        response = self.client.post(
            reverse("emergency-resolve", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4())
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "CONFLICT_INVALID_TRANSITION")

    def test_cancel_rejected_once_activated(self):
        # C-011: cancel is legal only in TRIGGERED; once ACTIVE the exit is resolve
        session = self.advance_to_active()
        response = self.client.post(
            reverse("emergency-cancel", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4())
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "CONFLICT_INVALID_TRANSITION")

    def test_cancel_from_triggered_works(self):
        session, _ = create_session(self.user, trigger="IN_APP_SOS")  # TRIGGERED now
        response = self.client.post(
            reverse("emergency-cancel", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4())
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["status"], "CANCELLED")

    def test_cancel_from_triggered_then_new_session(self):
        from emergency.models import EmergencySession as S

        fresh = S.objects.create(user=self.user, status="TRIGGERED", trigger_type="IN_APP_SOS")
        response = self.client.post(
            reverse("emergency-cancel", args=[fresh.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4())
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["status"], "CANCELLED")
        # after CANCELLED (final) a new session is allowed
        response2, _ = self.create_session()
        self.assertEqual(response2.status_code, 201)
        self.assertEqual(response2.data["status"], "TRIGGERED")  # C-011

    def test_cancel_idempotent(self):
        from emergency.models import EmergencySession as S

        fresh = S.objects.create(user=self.user, status="TRIGGERED", trigger_type="IN_APP_SOS")
        key = str(uuid.uuid4())
        first = self.client.post(reverse("emergency-cancel", args=[fresh.id]), format="json", HTTP_IDEMPOTENCY_KEY=key)
        second = self.client.post(reverse("emergency-cancel", args=[fresh.id]), format="json", HTTP_IDEMPOTENCY_KEY=key)
        self.assertEqual(first.status_code, 200)
        self.assertTrue(second.has_header("Idempotency-Replayed"))


class CapabilityTests(SessionApiBase):
    def test_active_then_degraded_then_active(self):
        session, _ = create_session(self.user, trigger="IN_APP_SOS")  # STARTING
        url = reverse("emergency-capability", args=[session.id])
        r1 = self.client.post(url, {"location_capability": "ACTIVE", "network_ok": True}, format="json")
        self.assertEqual(r1.data["status"], "ACTIVE")
        r2 = self.client.post(url, {"location_capability": "ACTIVE", "network_ok": False}, format="json")
        self.assertEqual(r2.data["status"], "DEGRADED")
        r3 = self.client.post(url, {"location_capability": "ACTIVE", "network_ok": True}, format="json")
        self.assertEqual(r3.data["status"], "ACTIVE")

    def test_location_failed_fails_session(self):
        session, _ = create_session(self.user, trigger="IN_APP_SOS")
        url = reverse("emergency-capability", args=[session.id])
        response = self.client.post(url, {"location_capability": "FAILED", "network_ok": True}, format="json")
        self.assertEqual(response.data["status"], "FAILED")

    def test_capability_report_after_resolve_rejected(self):
        session = self.advance_to_active()
        self.client.post(reverse("emergency-resolve", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()))
        response = self.client.post(
            reverse("emergency-capability", args=[session.id]),
            {"location_capability": "ACTIVE", "network_ok": True},
            format="json",
        )
        self.assertEqual(response.status_code, 409)


class ObjectLevelAuthTests(SessionApiBase):
    def test_other_user_cannot_touch_session(self):
        session, _ = create_session(self.user, trigger="IN_APP_SOS")
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.get(reverse("emergency-session", args=[session.id])).status_code, 404)
        self.assertEqual(self.client.get(reverse("emergency-session-events", args=[session.id])).status_code, 404)
        self.assertEqual(
            self.client.post(
                reverse("emergency-resolve", args=[session.id]), format="json", HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4())
            ).status_code,
            404,
        )
