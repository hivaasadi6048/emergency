from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from accounts.models import User
from devices.models import Device

PHONE_A = "+989121234567"
PHONE_B = "+989122222222"


class DeviceTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user_a = User.objects.create_user(PHONE_A)
        self.user_b = User.objects.create_user(PHONE_B)
        self.client.force_authenticate(self.user_a)

    def test_register_upserts_by_identifier(self):
        payload = {"platform": "ANDROID", "device_identifier": "imei-xyz", "app_version": "1.0.0"}
        first = self.client.post(reverse("device-list"), payload, format="json")
        self.assertEqual(first.status_code, 201, first.content)
        second = self.client.post(reverse("device-list"), {**payload, "app_version": "1.0.1"}, format="json")
        self.assertEqual(second.status_code, 201)
        self.assertEqual(first.data["id"], second.data["id"])  # upsert, not duplicate
        self.assertEqual(Device.objects.filter(user=self.user_a).count(), 1)
        device = Device.objects.get(user=self.user_a)
        self.assertEqual(device.app_version, "1.0.1")

    def test_raw_identifier_never_stored(self):
        self.client.post(reverse("device-list"), {"platform": "ANDROID", "device_identifier": "super-secret-imei"}, format="json")
        stored = list(Device.objects.values_list("device_hash", flat=True))
        self.assertTrue(stored)
        for value in stored:
            self.assertNotIn("super-secret-imei", value)
            self.assertEqual(len(value), 64)  # sha256 hex

    def test_object_level_isolation(self):
        self.client.post(reverse("device-list"), {"platform": "ANDROID", "device_identifier": "a-dev"}, format="json")
        self.client.force_authenticate(self.user_b)
        listing = self.client.get(reverse("device-list"))
        self.assertEqual(listing.data, [])  # user B sees nothing of user A
