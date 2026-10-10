"""Emergency APIs (docs/api-contract.md §2) — Phase 3.

Idempotency-Key is REQUIRED for: create, resolve, cancel (and location upload —
see locations app). Replays return the stored response.
"""
import logging

from django.db import transaction
from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.response import Response
from rest_framework.views import APIView

from .idempotency import IdempotencyKeyReused, IdempotencyInProgress, Replay, begin, complete, discard
from .models import EmergencyEvent, EmergencySession
from .serializers import (
    CapabilityReportSerializer,
    CreateSessionSerializer,
    SessionDetailSerializer,
    SessionSerializer,
)
from .services import (
    SessionStateConflict,
    cancel_session,
    create_session,
    report_capability,
    resolve_session,
)
from .state_machine import InvalidTransition

logger = logging.getLogger(__name__)


class MissingIdempotencyKey(APIException):
    status_code = 400
    default_code = "MISSING_IDEMPOTENCY_KEY"
    default_detail = "Idempotency-Key header is required for this operation"


def _key(request) -> str:
    key = (request.headers.get("Idempotency-Key") or "").strip()
    if not key:
        raise MissingIdempotencyKey()
    if len(key) > 128:
        raise MissingIdempotencyKey()
    return key


def _conflict_response(exc):
    if isinstance(exc, InvalidTransition):
        code, message = "CONFLICT_INVALID_TRANSITION", str(exc)
    else:
        code, message = exc.code, (exc.message or exc.code)
    http = status.HTTP_404_NOT_FOUND if code == "NOT_FOUND" else status.HTTP_409_CONFLICT
    return Response({"error": {"code": code, "message": message}}, status=http)


def _replay_response(record) -> Response:
    response = Response(record.response_body, status=record.response_code)
    response["Idempotency-Replayed"] = "true"
    return response


class SessionListCreateView(APIView):
    def get(self, request):
        sessions = EmergencySession.objects.filter(user=request.user).order_by("-created_at")[:100]
        return Response(SessionSerializer(sessions, many=True).data)

    def post(self, request):
        serializer = CreateSessionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload = serializer.validated_data
        key = _key(request)
        with transaction.atomic():
            try:
                record = begin(request.user, request.path, key, payload)
            except Replay as replay:
                return _replay_response(replay.record)
            try:
                session, created = create_session(
                    user=request.user, trigger_type=payload["trigger_type"], device_id=payload.get("device_id")
                )
            except Exception:
                discard(record)
                raise
            body = SessionSerializer(session).data
            if created:
                complete(record, 201, body)
                return Response(body, status=201)
            # duplicate trigger: 409 + existing session (docs/api-contract.md §2)
            body_409 = {
                "error": {"code": "CONFLICT_ACTIVE_SESSION", "message": "an active session exists"},
                "existing_session": body,
            }
            complete(record, 409, body_409)
            return Response(body_409, status=409)


class SessionDetailView(APIView):
    def get(self, request, pk):
        session = EmergencySession.objects.filter(user=request.user, pk=pk).first()
        if session is None:
            return Response({"error": {"code": "NOT_FOUND", "message": "session not found"}}, status=404)
        return Response(SessionDetailSerializer(session).data)


class SessionEventsView(APIView):
    def get(self, request, pk):
        session = EmergencySession.objects.filter(user=request.user, pk=pk).first()
        if session is None:
            return Response({"error": {"code": "NOT_FOUND", "message": "session not found"}}, status=404)
        events = session.events.order_by("created_at", "id")[:500]
        return Response(
            [
                {
                    "id": str(e.id),
                    "event_type": e.event_type,
                    "payload": e.payload,
                    "created_at": e.created_at,
                }
                for e in events
            ]
        )


class ResolveView(APIView):
    def post(self, request, pk):
        key = _key(request)
        payload = {"session_id": str(pk)}
        with transaction.atomic():
            try:
                record = begin(request.user, request.path, key, payload)
            except Replay as replay:
                return _replay_response(replay.record)
            try:
                session, changed = resolve_session(request.user, pk)
            except (SessionStateConflict, InvalidTransition) as exc:
                discard(record)
                return _conflict_response(exc)
            body = SessionSerializer(session).data
            if changed:
                complete(record, 200, body)
            return Response(body, status=200)


class CancelView(APIView):
    def post(self, request, pk):
        key = _key(request)
        payload = {"session_id": str(pk)}
        with transaction.atomic():
            try:
                record = begin(request.user, request.path, key, payload)
            except Replay as replay:
                return _replay_response(replay.record)
            try:
                session, _changed = cancel_session(request.user, pk)
            except (SessionStateConflict, InvalidTransition) as exc:
                discard(record)
                return _conflict_response(exc)
            body = SessionSerializer(session).data
            complete(record, 200, body)
            return Response(body, status=200)


class CapabilityView(APIView):
    """POST capability FACTS (native service state + network) — the backend
    composes the session state through the failure-model matrix; the client
    never sets session.status directly (docs/state-machine.md §4)."""

    def post(self, request, pk):
        serializer = CapabilityReportSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            with transaction.atomic():
                session, _changed = report_capability(
                    request.user,
                    pk,
                    location_capability=data["location_capability"],
                    network_ok=data["network_ok"],
                )
        except (SessionStateConflict, InvalidTransition) as exc:
            return _conflict_response(exc)
        return Response(SessionSerializer(session).data, status=200)
