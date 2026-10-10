"""Phone normalization (docs/data-model.md §1).

MVP scope is the Iranian market: the normalized form is E.164 Iranian mobile
`+989XXXXXXXXX`. Persian/Arabic digits, spaces, dashes, parentheses, `00`
prefixes and missing country codes are all handled here, in exactly one place.
"""
import re

from django.core.exceptions import ValidationError

PERSIAN_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")
ARABIC_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")

IRAN_MOBILE_RE = re.compile(r"^\+989\d{9}$")


def normalize_phone(raw: str) -> str:
    """Normalize a raw Iranian mobile number to E.164 (+989XXXXXXXXX).

    Raises ValidationError with a stable code for anything out of scope so
    serializers can surface it without leaking which part failed.
    """
    if raw is None:
        raise ValidationError("phone_invalid")
    value = str(raw).strip().translate(PERSIAN_DIGITS).translate(ARABIC_DIGITS)
    value = re.sub(r"[\s()\-.]", "", value)

    if value.startswith("00"):
        value = "+" + value[2:]
    elif value.startswith("+"):
        pass
    elif value.startswith("98") and len(value) == 12:
        value = "+" + value
    elif value.startswith("09") and len(value) == 11:
        value = "+98" + value[1:]
    elif value.startswith("9") and len(value) == 10:
        value = "+98" + value
    else:
        raise ValidationError("phone_invalid")

    if not IRAN_MOBILE_RE.match(value):
        raise ValidationError("phone_invalid")
    return value
