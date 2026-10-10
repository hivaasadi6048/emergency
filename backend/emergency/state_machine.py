"""EmergencySession state machine — enforced ONLY here (docs/state-machine.md).

Rules:
- the allowed-transition table below is the single source of truth;
- callers must hold a row lock (`select_for_update`) on the session row so
  concurrent requests serialize;
- every applied transition writes one STATE_CHANGED event in the same
  transaction — timeline and status are always consistent;
- RESOLVED / CANCELLED / FAILED are terminal (no exits).
"""
from django.db import models
from django.utils import timezone

from .models import EmergencyEvent, EmergencySession

ALLOWED_TRANSITIONS: dict[str, set[str]] = {
    EmergencySession.Status.TRIGGERED: {"STARTING", "CANCELLED"},
    EmergencySession.Status.STARTING: {"ACTIVE", "DEGRADED", "FAILED"},
    EmergencySession.Status.ACTIVE: {"DEGRADED", "RESOLVING"},
    EmergencySession.Status.DEGRADED: {"ACTIVE", "RESOLVING"},
    EmergencySession.Status.RESOLVING: {"RESOLVED"},
    # RESOLVED / CANCELLED / FAILED: terminal — no exits
}


class InvalidTransition(Exception):
    def __init__(self, from_status: str, to_status: str):
        self.from_status = from_status
        self.to_status = to_status
        super().__init__(f"invalid transition {from_status} -> {to_status}")


def can_transition(from_status: str, to_status: str) -> bool:
    return to_status in ALLOWED_TRANSITIONS.get(from_status, set())


def apply_transition(session: EmergencySession, to_status: str, *, actor: str, reason: str = "") -> EmergencySession:
    """Validate + apply a transition and record the event. Caller holds the row lock
    and an active transaction."""
    from_status = session.status
    if not can_transition(from_status, to_status):
        raise InvalidTransition(from_status, to_status)

    session.status = to_status
    if to_status == EmergencySession.Status.ACTIVE and session.activated_at is None:
        session.activated_at = timezone.now()
    if to_status == EmergencySession.Status.RESOLVED and session.resolved_at is None:
        session.resolved_at = timezone.now()
    session.save(update_fields=["status", "activated_at", "resolved_at", "updated_at"])

    EmergencyEvent.objects.create(
        session=session,
        event_type=EmergencyEvent.EventType.STATE_CHANGED,
        payload={"from": from_status, "to": to_status, "actor": actor, "reason": reason},
    )
    return session
