import logging

from rest_framework import generics
from rest_framework.response import Response

from .models import Device
from .serializers import DeviceSerializer
from .services import register_device

logger = logging.getLogger(__name__)


class DeviceListCreateView(generics.ListCreateAPIView):
    serializer_class = DeviceSerializer

    def get_queryset(self):
        # object-level: a user only ever sees their own devices
        return Device.objects.filter(user=self.request.user).order_by("-last_seen_at")

    def perform_create(self, serializer):
        data = self.request.data
        device, _created = register_device(
            user=self.request.user,
            platform=data.get("platform", "ANDROID"),
            raw_identifier=data.get("device_identifier") or "",
            app_version=data.get("app_version") or "",
            push_token=data.get("push_token") or "",
        )
        serializer.instance = device

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer()
        self.perform_create(serializer)
        return Response(serializer.data, status=201)
