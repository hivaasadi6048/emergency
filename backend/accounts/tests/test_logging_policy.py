"""Policy test: auth flow logs must never contain codes, tokens or raw phones."""
import logging
from io import StringIO

from django.core.cache import cache
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

PHONE = "+989121234567"


class NoSensitiveDataInLogsTests(TestCase):
    def setUp(self):
        cache.clear()
        self.stream = StringIO()
        handler = logging.StreamHandler(self.stream)
        self.root = logging.getLogger()
        self.root.addHandler(handler)
        self.old_level = self.root.level
        self.root.setLevel(logging.DEBUG)
        self.addCleanup(self.root.removeHandler, handler)
        self.addCleanup(self.root.setLevel, self.old_level)
        self.client = APIClient()

    def test_auth_flow_logs_do_not_leak_secrets(self):
        response = self.client.post(reverse("request-otp"), {"phone": PHONE}, format="json")
        code = response.data["debug_code"]
        tokens = self.client.post(
            reverse("verify-otp"),
            {"phone": PHONE, "code": code, "device_platform": "ANDROID", "device_identifier": "dev-1"},
            format="json",
        ).data
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
        self.client.get(reverse("me"))
        self.client.post(reverse("logout"), {"refresh": tokens["refresh"]}, format="json")

        logs = self.stream.getvalue()
        self.assertNotIn(code, logs, "OTP code leaked into logs")
        self.assertNotIn(tokens["access"], logs, "access token leaked into logs")
        self.assertNotIn(tokens["refresh"], logs, "refresh token leaked into logs")
        self.assertNotIn(PHONE, logs, "raw phone leaked into logs")
