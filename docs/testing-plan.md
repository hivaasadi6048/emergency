# Testing Plan — پلتفرم ایمنی شخصی و ارتباط اضطراری

- **سند:** `testing-plan.md`
- **نسخه:** 0.1 (Draft — PHASE 0)
- **تاریخ:** 2026-10-01
- **وضعیت:** در انتظار تأیید معماری

---

## 1. اصول

1. هیچ ادعایی بدون تست اجراشده + Evidence (نام تست، محیط، روش، Expected/Actual/Result) پذیرفته نیست.
2. هیچ نتیجه Android-only فقط بر اساس Emulator پذیرفته نمی‌شود.
3. نتیجه تست که به‌دلیل مشکل محیطی مخدوش شده قابل اتکا نیست و باید تکرار شود.
4. هر Feature: Unit + (در صورت ارتباط بین اجزا) Integration + رفتار Failure/Degraded.

## 2. پوشش تست بر اساس لایه

### Backend (pytest / Django TestCase + factory_boy)
- State transitions (مجاز/غیرمجاز/نهایی) — جدول‌محور
- Idempotency (Session، Location، Resolve، Alert) و race conditions
- Authorization و object-level access
- Phone normalization (ارقام فارسی/عربی، 00، فاصله، خط تیره)
- Location validation (محدوده، بازه captured_at، بچ نیمه‌معتبر)
- Alert orchestration (FakeProvider ها: موفق، شکست، partial، timeout)
- Retry logic و backoff (با clock قابل تزریق)
- Rate limiting و OTP flows
- «هیچ داده حساسی در log نیست» (تست خروجی logger)

### Flutter (flutter test + integration_test)
- Repository ها و Use Case ها (با fake API client)
- Emergency State mapping (ACTIVE/DEGRADED/FAILED/elapsed)
- API error handling (401/403/409/429/timeout/offline)
- Widget tests جریان SOS و Permission UX
- Validation فرم‌ها (contacts، OTP)

### Kotlin (JUnit + Robolectric فقط برای منطق خالص)
- Trigger State Machine (VOLUME_SEQUENCE experimental)
- Local Queue (سقف، عمر، ترتیب، dedupe، backoff)
- منطق Permission handling و capability status
- نکته: Robolectric برای FGS/lifecycle واقعی کافی نیست — پوشش رفتار واقعی فقط Device Matrix.

## 3. Integration Test های الزامی (حداقل)

| # | سناریو | لایه |
|---|---|---|
| 1 | SOS → Session creation (idempotent) | Backend |
| 2 | Session → First Location → status transitions | Backend |
| 3 | Location upload (batch + duplicate + invalid) → persist | Backend |
| 4 | Persist → Realtime broadcast به viewer مجاز | Backend/Channels |
| 5 | Resolve/Cancel → idempotent + Events کامل | Backend |
| 6 | Network loss → Local Queue (Kotlin) | Device |
| 7 | Network restoration → ارسال ترتیبی + sync | Device+Backend |
| 8 | Duplicate SOS (هم‌زمان/race) → یک Session | Backend |
| 9 | Invalid transition → reject + Event | Backend |
| 10 | Unauthorized location access → reject | Backend |
| 11 | Provider Failure (fake) → DEGRADED نه FAILED نه false success | Backend |
| 12 | FCM Failure/absence → بدون اثر بر Session | Backend |

## 4. Device Test Matrix (الزام — هیچ ردیفی با Emulator پر نمی‌شود)

```text
Model | OEM | Android Version | App Version | Battery State | Permission State |
Network State | Test | Result(PASS/FAIL/PARTIAL/UNSUPPORTED) | Notes | Evidence
```

دستگاه‌های حداقلی پیشنهادی: یک Xiaomi/Redmi (MIUI)، یک Samsung (OneUI)، یک Pixel (استوک)، یک دستگاه میان‌رده رایج ایران — نهایی‌سازی در Phase 1.

### ماتریس Volume Trigger (Experimental) — هر شرایط × هر دستگاه
`foreground / background / screen on / screen off / lock screen / removed from recent apps / battery saver / reboot / چند OEM / چند نسخه Android`

نتیجه جزء FAIL/PARTIAL/UNSUPPORTED → ماندن در Experimental، فعال‌سازی فقط روی دستگاه‌های PASS مشخص، یا حذف. هیچ workaround شکننده‌ای مجاز نیست.

## 5. Performance — اندازه‌گیری الزامی (بدون عدد بدون اندازه‌گیری)

| متریک | روش اندازه‌گیری | Phase |
|---|---|---|
| Battery در Session 1 ساعته | درصد مصرف روی 2 دستگاه واقعی، screen-off | 5 |
| Location Update Frequency واقعی | لاگ فاصله زمانی نقاط FGS | 5 |
| API Latency (p50/p95) | load test ساده (locust) + timing log | 3/6 |
| WebSocket Latency | timestamp سرور → دریافت viewer | 6 |
| Local Queue Growth | سناریوی قطع شبکه 1 ساعت | 5/9 |
| DB Write Rate | metrics در load test | 6/11 |
| Provider Delivery Latency | attempted_at→delivered_at per provider | 7 |

## 6. محیط‌ها و CI Gates

| محیط | توضیح |
|---|---|
| local | docker-compose: postgres + redis + backend (ASGI) + stub provider ها |
| CI | backend: migrations روی DB پاک + کل تست‌ها؛ flutter analyze + test؛ بررسی secret-scan |
| device | Phase 1/5/9 با ماتریس بالا |
| staging | قبل از production؛ تست deployment پاک (Phase 11) |

گیت‌های CI: شکست هر تست الزامی = merge ممنوع. FCM credential در CI وجود ندارد — اثبات «اجرای کامل بدون FCM» خودش یک تست معماری است.

## 7. معیار توقف تستی

هر کدام از این‌ها → STOP + Failure Report (طبق نیازمندی):
- شکست تست ضروری؛
- قابلیت کلیدی فقط روی Emulator کار کند؛
- رفتار failure نامشخص/ناامن/غیرقابل پیش‌بینی (Phase 9)؛
- duplicate request اثر تکراری کنترل‌نشده بگذارد؛
- unauthorized access پیدا شود (Phase 10 → BLOCKED برای High/Critical بدون mitigation).
