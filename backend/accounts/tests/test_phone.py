from django.core.exceptions import ValidationError
from django.test import SimpleTestCase

from accounts.phone import normalize_phone


class PhoneNormalizationTests(SimpleTestCase):
    def test_plain_iranian_mobile(self):
        self.assertEqual(normalize_phone("09121234567"), "+989121234567")

    def test_without_leading_zero(self):
        self.assertEqual(normalize_phone("9121234567"), "+989121234567")

    def test_with_country_code_no_plus(self):
        self.assertEqual(normalize_phone("989121234567"), "+989121234567")

    def test_with_country_code_plus(self):
        self.assertEqual(normalize_phone("+989121234567"), "+989121234567")

    def test_double_zero_prefix(self):
        self.assertEqual(normalize_phone("00989121234567"), "+989121234567")

    def test_spaces_dashes_parens(self):
        self.assertEqual(normalize_phone("0912 123 4567"), "+989121234567")
        self.assertEqual(normalize_phone("+98-912-123-4567"), "+989121234567")
        self.assertEqual(normalize_phone("(+98) 912 123 4567"), "+989121234567")

    def test_persian_digits(self):
        self.assertEqual(normalize_phone("۰۹۱۲۱۲۳۴۵۶۷"), "+989121234567")

    def test_arabic_digits(self):
        self.assertEqual(normalize_phone("٠٩١٢١٢٣٤٥٦٧"), "+989121234567")

    def test_mixed_digits_and_junk(self):
        self.assertEqual(normalize_phone(" +۹۸ - (912) ۱۲۳۴۵۶۷ "), "+989121234567")

    def test_too_short_rejected(self):
        with self.assertRaises(ValidationError):
            normalize_phone("0912123456")

    def test_too_long_rejected(self):
        with self.assertRaises(ValidationError):
            normalize_phone("091212345678")

    def test_landline_rejected(self):
        with self.assertRaises(ValidationError):
            normalize_phone("02188776655")

    def test_letters_rejected(self):
        with self.assertRaises(ValidationError):
            normalize_phone("0912abc4567")

    def test_empty_rejected(self):
        with self.assertRaises(ValidationError):
            normalize_phone("")
        with self.assertRaises(ValidationError):
            normalize_phone(None)
