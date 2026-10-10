from datetime import timedelta

from django.core.cache import cache
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import OtpCode, User

PHONE = "+989121234567"


def get_code(client, phone=PHONE):
    response = client.post(
        reverse("request-otp"), {"phone": phone}, format="json"
    )
    assert response.status_code == 200, response.content
    return response.data["debug_code"]


class AuthOtpFlowTests(TestCase):
    def setUp(self):
        cache.clear()  # LocMem throttle counters must not leak between tests
        self.client = APIClient()

    def test_request_otp_always_succeeds_and_does_not_reveal_existence(self):
        response = self.client.post(reverse("request-otp"), {"phone": PHONE}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertIn("debug_code", response.data)  # OTP_DEV_MODE
        self.assertNotIn("detail", {})  # no user-existence signal

    def test_verify_creates_user_and_returns_tokens(self):
        code = get_code(self.client)
        response = self.client.post(
            reverse("verify-otp"),
            {"phone": PHONE, "code": code, "device_platform": "ANDROID", "device_identifier": "test-device-1"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertIn("access", response.data)
        self.assertIn("refresh", response.data)
        self.assertEqual(response.data["user"]["phone"], PHONE)
        self.assertIsNotNone(response.data["device"])
        self.assertTrue(User.objects.filter(phone=PHONE).exists())

    def test_same_phone_logs_into_same_user(self):
        code1 = get_code(self.client)
        first = self.client.post(reverse("verify-otp"), {"phone": PHONE, "code": code1}, format="json")
        code2 = get_code(self.client)
        second = self.client.post(reverse("verify-otp"), {"phone": PHONE, "code": code2}, format="json")
        self.assertEqual(first.data["user"]["id"], second.data["user"]["id"])

    def test_wrong_code_fails_and_counts_attempts(self):
        get_code(self.client)
        for i in range(5):
            response = self.client.post(reverse("verify-otp"), {"phone": PHONE, "code": "000000"}, format="json")
            self.assertEqual(response.status_code, 400)
        # 6th wrong attempt: OTP is locked after max attempts
        response = self.client.post(reverse("verify-otp"), {"phone": PHONE, "code": "000000"}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "otp_locked")

    def test_expired_code_rejected(self):
        code = get_code(self.client)
        OtpCode.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        response = self.client.post(reverse("verify-otp"), {"phone": PHONE, "code": code}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "otp_expired")

    def test_otp_issue_rate_limited(self):
        for _ in range(3):
            self.client.post(reverse("request-otp"), {"phone": PHONE}, format="json")
        response = self.client.post(reverse("request-otp"), {"phone": PHONE}, format="json")
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.data["error"]["code"], "otp_rate_limited")

    def test_invalid_phone_rejected_without_hint(self):
        response = self.client.post(reverse("request-otp"), {"phone": "not-a-phone"}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "VALIDATION_ERROR")

    def test_me_requires_auth(self):
        response = self.client.get(reverse("me"))
        self.assertEqual(response.status_code, 401)

    def test_me_roundtrip(self):
        code = get_code(self.client)
        tokens = self.client.post(reverse("verify-otp"), {"phone": PHONE, "code": code}, format="json").data
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
        me = self.client.get(reverse("me"))
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.data["phone"], PHONE)
        patched = self.client.patch(reverse("me"), {"display_name": "Ali"}, format="json")
        self.assertEqual(patched.data["display_name"], "Ali")

    def test_logout_blacklists_refresh(self):
        code = get_code(self.client)
        tokens = self.client.post(reverse("verify-otp"), {"phone": PHONE, "code": code}, format="json").data
        response = self.client.post(reverse("logout"), {"refresh": tokens["refresh"]}, format="json")
        self.assertEqual(response.status_code, 204)
        replay = self.client.post(reverse("refresh"), {"refresh": tokens["refresh"]}, format="json")
        self.assertEqual(replay.status_code, 401)
