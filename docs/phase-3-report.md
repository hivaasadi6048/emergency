# PHASE REPORT — PHASE 3: Emergency Domain

- تاریخ: 2026-10-04
- Status: **PASS**

## 1. هدف Phase
State Machine enforcement سمت سرور، Idempotency عملیاتی، Emergency APIs، Location ingestion با dedupe، Event Timeline و object-level authorization — طبق state-machine.md و api-contract.md مصوب.

## 2. خروجی‌های مورد انتظار
موتور گذار با row-lock، سرویس idempotency، API های create/resolve/cancel/capability/events، POST /locations بچ‌محور، تست‌های گذار مجاز/غیرمجاز/duplicate/race.

## 3. موارد پیاده‌سازی‌شده

| Feature | Status | Files | Notes |
|---|---|---|---|
| State Machine engine | DONE | `emergency/state_machine.py` | جدول گذار مجاز = تنها منبع حقیقت؛ هر گذار دقیقاً یک Event STATE_CHANGED در همان تراکنش؛ state های نهایی بدون خروج |
| Idempotency service | DONE | `emergency/idempotency.py` | replay با `Idempotency-Replayed: true`؛ key تکراری با body متفاوت → 409 `IDEMPOTENCY_KEY_REUSED`؛ IN_PROGRESS → 409 |
| Session create + duplicate SOS | DONE | `emergency/services.py` | trigger دوم → 409 + `existing_session` + Event `TRIGGER_DUPLICATE_IGNORED` — هرگز Session دوم؛ مسیر race با C-01 + savepoint |
| Resolve / Cancel | DONE | همان | resolve: ACTIVE/DEGRADED→RESOLVING→RESOLVED (دو گذار + `SESSION_RESOLVED` + resolved_at)؛ cancel فقط از TRIGGERED؛ هر دو idempotent (با و بدون key) |
| Capability report [C-010] | DONE | `emergency/views.py` | کلاینت FACT گزارش می‌دهد؛ backend طبق ماتریس failure-model وضعیت می‌سازد؛ ارسال `status` توسط کلاینت → 400 unknown_field |
| Locations batch API | DONE | `locations/views.py`, `serializers.py` | dedupe با client_uuid (C-02)، clock-skew policy per-point (پیش‌فرض -5min/+10min)، gating وضعیت Session، `FIRST_LOCATION_RECEIVED` فقط یک‌بار، سقف batch=200 |
| Event Timeline | DONE | `emergency/views.py` | GET events مرتب؛ GET session با latest_location |
| object-level authorization | DONE | همه ویوها | Session کاربر دیگر → 404 (تست‌شده برای get/events/resolve) |

## 4. تست‌های اجراشده

- Test: کل سوئیت (Phase 2 + Phase 3)
  - Type: Unit + Integration (Django TestCase روی PostgreSQL 16 واقعی، DB تست پاک)
  - Environment: Python 3.10.11 / Django 5.2.17 / `test_emergency_dev`
  - Command: `manage.py test --settings=config.settings.test --noinput`
  - Expected: همه Pass
  - Actual: **Ran 71 tests — OK** (32 تست جدید Phase 3)
  - Result: PASS
  - Evidence: خروجی؛ پوشش Phase 3:
    - گذارهای مجاز: هر ۱۰ گذار سند به‌صورت جدول‌محور (subTest) PASS
    - گذارهای غیرمجاز: **تست اhaustive همه ترکیب‌های 8×8 منهای مجازها** → همگی رد
    - state های نهایی بدون خروج؛ هر گذار دقیقاً یک Event؛ `resolved_at` فقط یک‌بار
    - duplicate SOS → یک Session + Event + 409 با existing_session
    - idempotency: replay با همان key (بدون Event تکراری)، key تکراری body متفاوت، IN_PROGRESS
    - locations: batch موفق، dedupe، clock_skew per-point، مختصات نامعتبر per-point، رد در RESOLVED، 404 برای Session دیگری، FIRST_LOCATION فقط یک‌بار
    - object-level: کاربر B روی Session کاربر A → 404 برای detail/events/resolve

## 5. معیارهای پذیرش فاز (تطبیق با سند)

| معیار | نتیجه |
|---|---|
| Transitionهای مجاز Pass | ✓ (جدول‌محور) |
| Transitionهای غیرمجاز Reject | ✓ (اhaustive) |
| Client نتواند State arbitrary تعیین کند | ✓ (serializer سخت‌گیر: فیلد ناشناس → 400؛ فقط action می‌فرستد) |
| duplicate SOS Session دوم نسازد | ✓ (سرویس + C-01 + تست race-loss) |
| duplicate Location رکورد تکراری نسازد | ✓ (C-02 + get_or_create + تست) |
| Resolve و Cancel idempotent | ✓ (با key: replay؛ بدون key: 200 همان state) |
| Event Timeline کامل | ✓ (TRIGGER_RECEIVED→SESSION_CREATED→STATE_CHANGED…→SESSION_RESOLVED) |
| object-level authorization تست شود | ✓ |

## 6. محدودیت‌ها و رفتار Degraded
1. Resolve فعلاً synchronous است (RESOLVING→RESOLVED در یک تراکنش)؛ در Phase 6/7 اگر finalize ناهمگ (مثل قطع alertها) طولانی شود، RESOLVING به‌صورت وضعیت میانی واقعی با job خواهد آمد — semantics فعلی idempotent و امن است.
2. Duplicate SOS پاسخ 409 با existing_session می‌دهد (طبق api-contract) — کلاینت Phase 4 باید آن را به‌عنوان «اتصال به Session موجود».handle کند.
3. اولویت‌بندی capability هنوز فقط location/network است؛ باتری و alert providerها در Phase 5/7 به ماتریس اضافه می‌شوند.
4. Throttle عمومی هنوز LocMem است (Redis → Phase 6).

## 7. تصمیم‌های معماری جدید
- D-18: **Capability Report endpoint** — کلاینت FACT گزارش می‌کند، backend وضعیت را از ماتریس می‌سازد (جدا کردن کامل «حق تعیین state» از کلاینت). ثبت: change-log C-010، api-contract.md به‌روز شد.

## 8. فایل‌های تغییرکرده
- Added: `emergency/state_machine.py`, `emergency/idempotency.py`, `emergency/services.py`, `emergency/serializers.py`, `emergency/views.py`, `emergency/urls.py`, `emergency/tests/{test_state_machine,test_session_api}.py`, `locations/serializers.py`, `locations/views.py`, `locations/urls.py`, `locations/tests/test_locations_api.py`, `docs/phase-3-report.md`
- Modified: `config/urls.py`, `config/exception_handler.py`, `docs/api-contract.md`, `docs/change-log.md`, `README.md`

## 9. ریسک‌های باقی‌مانده
- Resolving طولانی در آینده (اگر finalize چندمرحله‌ای شود) — ردیابی در Phase 6/7.
- ماتریس capability فعلاً ۲ بعدی است (location, network) — بسط در Phase 5/7 با تست.
- آزمون فشار/همزمانی واقعی (چند worker) هنوز انجام نشده — Phase 6/11.

## 10. نتیجه توقف یا ادامه
- Decision: **STOP**
- Reason: هر ۸ معیار پذیرش Phase 3 برآورده و 71/71 تست PASS؛ تأیید مالک برای Phase 4 لازم است.

## 11. Phase بعدی
**PHASE 4 — Flutter Application**: لایه‌بندی Presentation/Domain/Data، AuthRepository/ContactRepository/EmergencyRepository، صفحات Auth/Contacts/SOS/Emergency State/History/Settings، بدون API call داخل Widget — و اتصال به backend همین پروژه.
