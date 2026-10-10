"""Emergency session flows — creation (dedupe), resolve, cancel, capability report.

Every flow runs inside one transaction with a row lock on the session/user so
duplicate triggers and races cannot produce inconsistent state
(docs/state-machine.md §4-5, docs/failure-model.md §3).
"""
import logging

from django.db import IntegrityError, transaction
from django.utils import timezone

from devices.models import Device

from .models import ACTIVE_SESSION_STATUSES, EmergencyEvent, EmergencySession
from .state_machine import InvalidTransition, apply_transition

logger = logging.getLogger(__name__)


class SessionStateConflict(Exception):
    """API-visible invalid transition / wrong-state action."""

    def __init__(self, code: str, message: str = ""):
        self.code = code
        self.message = message
        super().__init__(code)


def _locked_session(user, session_id) -> EmergencySession:
    """Object-level authorization happens here: another user's session is 404."""
    session = EmergencySession.objects.select_for_update().filter(user=user, pk=session_id).first()
    if session is None:
        raise SessionStateConflict("NOT_FOUND", "session not found")
    return session


def _event(session, event_type, payload):
    return EmergencyEvent.objects.create(session=session, event_type=event_type, payload=payload)


@transaction.atomic
def create_session(*, user, trigger_type: str, device_id=None):
    """Trigger -> Session. Duplicate triggers never create a second session."""
    device = None
    if device_id is not None:
        device = Device.objects.filter(user=user, pk=device_id).first()
        if device is None:
            raise SessionStateConflict("VALIDATION_ERROR", "unknown device")

    active = (
        EmergencySession.objects.select_for_update()
        .filter(user=user, status__in=ACTIVE_SESSION_STATUSES)
        .first()
    )
    if active is not None:
        # duplicate trigger: register the event on the existing session only
        _event(
            active,
            EmergencyEvent.EventType.TRIGGER_DUPLICATE_IGNORED,
            {"trigger_type": trigger_type, "active_session_status": active.status},
        )
        logger.info("emergency.duplicate_trigger user=%s session=%s", user.id, active.id)
        return active, False  # not created

    try:
        # savepoint: a C-01 race loss must not poison the outer transaction
        with transaction.atomic():
            session = EmergencySession.objects.create(user=user, device=device, trigger_type=trigger_type)
    except IntegrityError:
        active = (
            EmergencySession.objects.select_for_update()
            .filter(user=user, status__in=ACTIVE_SESSION_STATUSES)
            .first()
        )
        _event(active, EmergencyEvent.EventType.TRIGGER_DUPLICATE_IGNORED, {"trigger_type": trigger_type})
        return active, False

    _event(session, EmergencyEvent.EventType.TRIGGER_RECEIVED, {"trigger_type": trigger_type})
    _event(session, EmergencyEvent.EventType.SESSION_CREATED, {"trigger_type": trigger_type})
    # Session stays TRIGGERED: the cancel window (TRIGGERED->CANCELLED) remains open
    # until the first capability report advances it to STARTING (C-011, 2026-10-04).
    logger.info("emergency.session_created user=%s session=%s trigger=%s", user.id, session.id, trigger_type)
    return session, True


@transaction.atomic
def resolve_session(user, session_id):
    """ACTIVE/DEGRADED -> RESOLVING -> RESOLVED, idempotent on final states."""
    session = _locked_session(user, session_id)
    if session.status == EmergencySession.Status.RESOLVED:
        return session, False  # idempotent replay without a stored response
    apply_transition(session, EmergencySession.Status.RESOLVING, actor="CLIENT", reason="user_resolve")
    apply_transition(session, EmergencySession.Status.RESOLVED, actor="BACKEND", reason="resolve_complete")
    _event(session, EmergencyEvent.EventType.SESSION_RESOLVED, {})
    logger.info("emergency.session_resolved user=%s session=%s", user.id, session.id)
    return session, True


@transaction.atomic
def cancel_session(user, session_id):
    """TRIGGERED -> CANCELLED only (docs/state-machine.md §3 note 1)."""
    session = _locked_session(user, session_id)
    if session.status == EmergencySession.Status.CANCELLED:
        return session, False
    apply_transition(session, EmergencySession.Status.CANCELLED, actor="CLIENT", reason="user_cancel")
    _event(session, EmergencyEvent.EventType.SESSION_CANCELLED, {})
    logger.info("emergency.session_cancelled user=%s session=%s", user.id, session.id)
    return session, True


def _compose_status(location_capability: str, network_ok: bool) -> str:
    """Failure-model §3 matrix (Phase 3 subset): worst capability wins."""
    if location_capability == "FAILED":
        return EmergencySession.Status.FAILED
    if location_capability == "DEGRADED" or not network_ok:
        return EmergencySession.Status.DEGRADED
    return EmergencySession.Status.ACTIVE


@transaction.atomic
def report_capability(user, session_id, *, location_capability: str, network_ok: bool):
    """The client reports native capability FACTS; the backend decides the session
    state through policy — the client never sets session.status directly.

    A TRIGGERED session advances through STARTING on its first report
    (TRIGGERED->STARTING->target), which also closes the cancel window (C-011)."""
    session = _locked_session(user, session_id)
    if session.status not in (
        EmergencySession.Status.TRIGGERED,
        EmergencySession.Status.STARTING,
        EmergencySession.Status.ACTIVE,
        EmergencySession.Status.DEGRADED,
    ):
        raise SessionStateConflict("CONFLICT_INVALID_TRANSITION", f"capability reports not accepted in {session.status}")

    target = _compose_status(location_capability, network_ok)
    if target == session.status:
        return session, False

    if session.status == EmergencySession.Status.TRIGGERED:
        apply_transition(session, EmergencySession.Status.STARTING, actor="CLIENT", reason="first_capability_report")

    if session.status == target:
        return session, True

    if not _transition_allowed(session.status, target):
        # e.g. STARTING -> FAILED is allowed; DEGRADED -> FAILED is not (per spec)
        raise SessionStateConflict("CONFLICT_INVALID_TRANSITION", f"{session.status} -> {target} not allowed")

    reason_bits = []
    if location_capability != "ACTIVE":
        reason_bits.append(f"location={location_capability}")
    if not network_ok:
        reason_bits.append("network=down")
    apply_transition(session, target, actor="CLIENT", reason=";".join(reason_bits) or "capabilities_nominal")
    if not network_ok:
        _event(session, EmergencyEvent.EventType.NETWORK_LOST, {})
    logger.info("emergency.capability user=%s session=%s target=%s", user.id, session.id, target)
    return session, True


def _transition_allowed(from_status, to_status) -> bool:
    from .state_machine import can_transition

    return can_transition(from_status, to_status)


def attach_location(session, *, client_uuid, captured_at):
    """Post-ingest bookkeeping for an accepted point."""
    first = not session.locations.exists()
    session.last_location_at = captured_at
    session.save(update_fields=["last_location_at", "updated_at"])
    if first:
        _event(session, EmergencyEvent.EventType.FIRST_LOCATION_RECEIVED, {"captured_at": captured_at.isoformat()})
