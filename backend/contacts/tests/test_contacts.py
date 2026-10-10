from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from accounts.models import User
from contacts.models import TrustedContact

PHONE_A = "+989121234567"
PHONE_B = "+989122222222"


class ContactTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user_a = User.objects.create_user(PHONE_A, "A")
        self.user_b = User.objects.create_user(PHONE_B, "B")
        self.client.force_authenticate(self.user_a)

    def test_create_normalizes_phone(self):
        response = self.client.post(
            reverse("contact-list"),
            {"name": "Maman", "phone": "۰۹۱۲ ۳۴۵ ۶۷۸۹", "relationship": "family"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.data["phone"], "+989123456789")

    def test_list_excludes_soft_deleted(self):
        contact = TrustedContact.objects.create(user=self.user_a, name="x", phone="+989123456789")
        self.client.delete(reverse("contact-detail", args=[contact.id]))
        listing = self.client.get(reverse("contact-list"))
        self.assertEqual(listing.data, [])
        contact.refresh_from_db()
        self.assertFalse(contact.is_active)  # soft delete, not hard delete

    def test_duplicate_active_phone_rejected(self):
        self.client.post(reverse("contact-list"), {"name": "x", "phone": "+989123456789"}, format="json")
        response = self.client.post(reverse("contact-list"), {"name": "y", "phone": "09123456789"}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_object_level_isolation(self):
        contact = TrustedContact.objects.create(user=self.user_a, name="secret", phone="+989123456789")
        self.client.force_authenticate(self.user_b)
        # user B cannot read, update or delete user A's contact
        self.assertEqual(self.client.get(reverse("contact-detail", args=[contact.id])).status_code, 404)
        self.assertEqual(
            self.client.patch(reverse("contact-detail", args=[contact.id]), {"name": "hacked"}, format="json").status_code,
            404,
        )
        self.assertEqual(self.client.delete(reverse("contact-detail", args=[contact.id])).status_code, 404)
        contact.refresh_from_db()
        self.assertEqual(contact.name, "secret")
