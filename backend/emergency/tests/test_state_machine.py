"""State machine table-driven tests (docs/state-machine.md §2-3, §6)."""
from django.test import TestCase

from accounts.models import User
from emergency.models import EmergencySession
from emergency.state_machine import InvalidTransition, apply_transition, can_transition

PHONE = "+989121234567"

# every transition listed as allowed in docs/state-machine.md §2
VALID = [
    ("TRIGGERED", "STARTING"),
    ("TRIGGERED", "CANCELLED"),
    ("STARTING", "ACTIVE"),
    ("STARTING", "DEGRADED"),
    ("STARTING", "FAILED"),
    ("ACTIVE", "DEGRADED"),
    ("DEGRADED", "ACTIVE"),
    ("ACTIVE", "RESOLVING"),
    ("DEGRADED", "RESOLVING"),
    ("RESOLVING", "RESOLVED"),
]

# everything else must be rejected — sampled exhaustively below
ALL_STATUSES = ["TRIGGERED", "STARTING", "ACTIVE", "DEGRADED", "RESOLVING", "RESOLVED", "CANCELLED", "FAILED"]


class StateMachineTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(PHONE)

    def _session(self, status):
        # subTests share one transaction — C-01 would (correctly) reject a second
        # active session for the same user, so clear between cases
        EmergencySession.objects.all().delete()
        return EmergencySession.objects.create(
            user=self.user, status=status, trigger_type=EmergencySession.TriggerType.IN_APP_SOS
        )

    def test_all_documented_valid_transitions_pass(self):
        for from_status, to_status in VALID:
            with self.subTest(f"{from_status}->{to_status}"):
                self.assertTrue(can_transition(from_status, to_status))
                session = self._session(from_status)
                apply_transition(session, to_status, actor="TEST")
                session.refresh_from_db()
                self.assertEqual(session.status, to_status)

    def test_every_undocumented_transition_is_rejected(self):
        for from_status in ALL_STATUSES:
            for to_status in ALL_STATUSES:
                if (from_status, to_status) in VALID:
                    continue
                with self.subTest(f"{from_status}->!{to_status}"):
                    self.assertFalse(can_transition(from_status, to_status))

    def test_terminal_states_have_no_exit(self):
        for terminal in ["RESOLVED", "CANCELLED", "FAILED"]:
            session = self._session(terminal)
            for to_status in ALL_STATUSES:
                if to_status == terminal:
                    continue
                with self.subTest(f"{terminal}->!{to_status}"):
                    with self.assertRaises(InvalidTransition):
                        apply_transition(session, to_status, actor="TEST")

    def test_each_transition_writes_exactly_one_state_changed_event(self):
        session = self._session("ACTIVE")
        before = session.events.count()
        apply_transition(session, "RESOLVING", actor="TEST", reason="r")
        self.assertEqual(session.events.count(), before + 1)
        event = session.events.latest("created_at")
        self.assertEqual(event.event_type, "STATE_CHANGED")
        self.assertEqual(event.payload["from"], "ACTIVE")
        self.assertEqual(event.payload["to"], "RESOLVING")
        self.assertEqual(event.payload["actor"], "TEST")

    def test_resolve_sets_resolved_at_once(self):
        session = self._session("ACTIVE")
        apply_transition(session, "RESOLVING", actor="TEST")
        self.assertIsNone(session.resolved_at)
        apply_transition(session, "RESOLVED", actor="TEST")
        self.assertIsNotNone(session.resolved_at)
        first = session.resolved_at
        # RESOLVED is terminal — re-resolving must be rejected and resolved_at frozen
        with self.assertRaises(InvalidTransition):
            apply_transition(session, "RESOLVED", actor="TEST")
        session.refresh_from_db()
        self.assertEqual(session.resolved_at, first)
