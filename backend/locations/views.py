"""POST /api/v1/locations — batch ingestion with per-point dedupe (C-02),
clock-skew policy and session-state gating."""
import logging

from django.db import transaction
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from emergency.idempotency import Replay, begin, complete, discard
from emergency.models import EmergencyEvent, EmergencySession
from emergency.services import SessionStateConflict

from .models import LocationPoint
from .serializers import LocationBatchSerializer, LocationPointInSerializer

logger = logging.getLogger(__name__)

INGESTABLE_STATUSES = (
    EmergencySession.Status.STARTING,
    EmergencySession.Status.ACTIVE,
    EmergencySession.Status.DEGRADED,
)


class LocationBatchUploadView(APIView):
    def post(self, request):
        key_header = (request.headers.get("Idempotency-Key") or "").strip()
        if not key_header:
            return Response(
                {"error": {"code": "MISSING_IDEMPOTENCY_KEY", "message": "Idempotency-Key header required"}},
                status=400,
            )
        serializer = LocationBatchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload = serializer.validated_data
        endpoint = request.path

        with transaction.atomic():
            try:
                record = begin(request.user, endpoint, key_header, payload)
            except Replay as replay:
                response = Response(replay.record.response_body, status=replay.record.response_code)
                response["Idempotency-Replayed"] = "true"
                return response

            # object-level authorization: only the session owner can upload
            session = (
                EmergencySession.objects.select_for_update()
                .filter(user=request.user, pk=payload["session_id"])
                .first()
            )
            if session is None:
                discard(record)
                return Response({"error": {"code": "NOT_FOUND", "message": "session not found"}}, status=404)
            if session.status not in INGESTABLE_STATUSES:
                discard(record)
                return Response(
                    {"error": {"code": "CONFLICT_INVALID_TRANSITION", "message": f"location upload rejected in {session.status}"}},
                    status=409,
                )

            accepted, duplicates, rejected = [], [], []
            for raw_point in payload["points"]:
                point_serializer = LocationPointInSerializer(data=raw_point)
                if not point_serializer.is_valid():
                    errors = point_serializer.errors
                    first_field = next(iter(errors))
                    reason = str(errors[first_field][0])
                    rejected.append(
                        {"client_uuid": str(raw_point.get("client_uuid", "?")), "reason": reason}
                    )
                    continue
                point = point_serializer.validated_data
                obj, created = LocationPoint.objects.get_or_create(
                    session=session,
                    client_uuid=point["client_uuid"],
                    defaults={
                        "latitude": point["latitude"],
                        "longitude": point["longitude"],
                        "accuracy_m": point.get("accuracy_m"),
                        "altitude_m": point.get("altitude_m"),
                        "speed_mps": point.get("speed_mps"),
                        "heading_deg": point.get("heading_deg"),
                        "captured_at": point["captured_at"],
                        "source": point["source"],
                    },
                )
                if created:
                    accepted.append(str(point["client_uuid"]))
                else:
                    duplicates.append(str(point["client_uuid"]))

            if accepted:
                first = session.last_location_at is None
                latest = max(
                    LocationPoint.objects.filter(session=session, client_uuid__in=[u for u in accepted]).values_list(
                        "captured_at", flat=True
                    )
                )
                session.last_location_at = latest
                session.save(update_fields=["last_location_at", "updated_at"])
                if first:
                    EmergencyEvent.objects.create(
                        session=session,
                        event_type=EmergencyEvent.EventType.FIRST_LOCATION_RECEIVED,
                        payload={"captured_at": latest.isoformat()},
                    )

            body = {"accepted": accepted, "duplicates": duplicates, "rejected": rejected}
            complete(record, 202, body)
            logger.info(
                "locations.upload user=%s session=%s accepted=%d duplicates=%d",
                request.user.id,
                session.id,
                len(accepted),
                len(duplicates),
            )
            return Response(body, status=status.HTTP_202_ACCEPTED)
