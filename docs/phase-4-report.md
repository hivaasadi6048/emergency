# PHASE REPORT — PHASE 4: Flutter Application

- تاریخ: 2026-10-05
- Status: **PASS_WITH_LIMITATIONS**

## 1. هدف Phase
اپلیکیشن Flutter با لایه‌بندی Presentation/Domain/Data روی backend واقعی: Authentication، Contacts، SOS، Emergency State، Session History، Settings — بدون API call داخل Widget و با تست.

## 2. موارد پیاده‌سازی‌شده

| Feature | Status | Files | Notes |
|---|---|---|---|
| لایه‌بندی کامل | DONE | `lib/core/`, `lib/domain/`, `lib/data/`, `lib/state/`, `lib/features/` | Widget ها فقط از AppState (ChangeNotifier) استفاده می‌کنند |
| ApiClient بدون وابستگی pub | DONE | `lib/core/api/api_client.dart` | dart:io + Bearer + Idempotency-Key + **Content-Length صریح (B-018)** + refresh-once-on-401 + retry شبکه |
| Authentication | DONE | `lib/features/auth/`, `data/repositories_impl.dart` | OTP dev-mode با کارت سبز + پرشدن خودکار فیلد؛ پیام خطای واقعی به‌جای پیام گمراه‌کننده |
| Contacts CRUD | DONE | `lib/features/contacts/` | لیست/افزودن/ویرایش/حذف با تأییدیه |
| SOS + Emergency State | DONE | `lib/features/emergency/` | SOS → Session → **گیت مجوز** → Native FGS → capability → نمایش صادقانه ACTIVE/DEGRADED/FAILED/TRIGGERED + elapsed + تأییدیه Resolve/Cancel |
| Session History + Timeline | DONE | `lib/features/history/` | لیست + Event Timeline |
| Settings | DONE | `lib/features/settings/` | آدرس backend، وضعیت مجوزهای واقعی، متن صداقت محصول، خروج |
| پل آپلود موقعیت (C-014) | DONE | `lib/state/app_state.dart` | بافر Native → بچ با client_uuid پایدار → dedupe سمت سرور (C-02) |

## 3. تست‌های اجراشده

| تست | Environment | Command | Expected | Actual | Result |
|---|---|---|---|---|---|
| Backend کامل (بعد از C-011) | PostgreSQL 16 واقعی، DB پاک | `manage.py test --noinput` | همه Pass | **72/72 OK** | PASS |
| Flutter analyze | Windows | `flutter analyze` | 0 issue | **No issues found** | PASS |
| Flutter tests (شامل fake-server واقعی dart:io) | dart test env | `flutter test` | همه Pass | **15/15 All tests passed** | PASS |
| E2E دستگاهی — ورود | A21s/Android 12 + adb reverse | درایو adb | ورود موفق | ✓ (۲ بار؛ لاگ verify-otp 200) | PASS |
| E2E دستگاهی — SOS → State Machine | A21s | درایو adb | TRIGGERED→capability→ACTIVE/DEGRADED/FAILED | ✓ — TRIGGERED (پنجره لغو C-011) → دیالوگ مجوز → رد موقت → **FAILED صادقانه** → تایید مجوز → SOS مجدد → **DEGRADED/ACTIVE** با گزارش capability هر ۳ ثانیه (لاگ: capability 200 + GET 200 متوالی) | PASS |
| E2E دستگاهی — Resume بعد از نصب مجدد | A21s | reinstall + login | Session باز بازیابی شود | ✓ Session b37c8a77 ACTIVE adopt شد و polling ادامه یافت | PASS |
| E2E دستگاهی — نمایش موقعیت | A21s (داخل ساختمان) | — | نقاط آپلود و نمایش | **PARTIAL** — آپلود پیاده و آماده؛ دستگاه داخل ساختمان از بوت هیچ fix ای نگرفته (dumpsys: بدون last location) → نمایش صادقانه «هنوز نقطه‌ای دریافت نشده». تست نزدیک پنجره/فضای باز باقی است | PARTIAL |
| E2E دستگاهی — خاموشی Location Services | A21s | `location_mode=0→3` | DEGRADED صادقانه + بازیابی با watchdog | ✓ DEGRADED نمایش داده شد؛ **باگ B-019 کشف شد** (watchdog در شاخه services-off استارت نمی‌شد) و رفع شد | PASS |

## 4. باگ‌های کشف‌شده و رفع‌شده در این فاز (همه در change-log)

- **B-017**: دکمه ورود با تایپ فعال نمی‌شد (listener شرطی) — + widget test رگرسیون.
- **B-018 (ریشه ۲ ساعت گیر)**: dart:io بدون Content-Length بدنه را chunked می‌فرستد؛ Django dev server (http.server پایتون) chunked را نمی‌فهمد → شماره هرگز نمی‌رسید. فیکس: Content-Length صریح + تست رگرسیون (fake backend چون chunked را می‌پذیرفت، حالا آن را 400 می‌کند).
- **B-019**: watchdog در شاخه LOCATION_SERVICES_OFF استارت نمی‌شد → رفع.
- سایر: خطای بی‌صدای network در requestOtp، پیام گمراه‌کننده «شماره معتبر نیست» برای خطای شبکه، پاک‌ساز کاراکترهای نامرئی کیبورد فارسی.

## 5. محدودیت‌ها و رفتار Degraded
1. توکن‌ها in-memory (run-scoped) — پس از هر نصب/ری‌استارت، ورود مجاز لازم است (C-012؛ persistence امن در فاز hardening).
2. OTP فقط dev-mode (Q-01 باز — درگاه پیامک در Phase 7).
3. پل Flutter↔Kotlin موقت (C-013) — Pigeon در Phase 5.
4. آپلود موقعیت به fix اول GPS وابسته است؛ داخل ساختمان ممکن است دقیقه‌ها طول بکشد (رفتار واقعی دستگاه — صادقانه نمایش داده می‌شود). تست نهایی نمایش در فضای باز.
5. `adb reverse` با هر قطع USB می‌پرد → برای dev، watchdog تونل روی سیستم اجرا می‌شود (C-015).

## 6. فایل‌های تغییرکرده
- Added: `lib/core/{config,uuid,phone_input}.dart`, `lib/core/api/{api_client,api_exception}.dart`, `lib/core/native/emergency_native.dart`, `lib/domain/{entities,repositories,usecases}.dart`, `lib/data/repositories_impl.dart`, `lib/state/app_state.dart`, `lib/features/**` (۵ صفحه + shared ui)، `test/{fake_backend,api_client_test,repositories_test,phone_input_test,login_button_regression_test}.dart`، `docs/phase-4-report.md`
- Modified: `lib/main.dart`، `lib/features/auth/login_screen.dart`، `lib/features/emergency/emergency_screen.dart`، `lib/domain/entities.dart`، `emergency/services.py` (C-011)، `emergency/tests/test_session_api.py`، `docs/change-log.md`، `docs/api-contract.md`، `README.md`
- Deleted: `test/widget_test.dart` (قالب پیش‌فرض)

## 7. ریسک‌های باقی‌مانده
- پایداری تونل dev روی USB (فقط dev — production از هاست واقعی).
-室内 GPS acquisition کند — در Phase 5 با LocationPolicy و A-GPS/timeout policy مدیریت می‌شود.
- Token persistence — hardening.

## 8. نتیجه توقف یا ادامه
- Decision: **STOP**
- Reason: خروجی‌های Phase 4 کامل و تست‌شده؛ تنها مورد PARTIAL (نمایش موقعیت داخل ساختمان) محیطی است و با تست فضای باز بسته می‌شود؛ تأیید مالک برای Phase 5 لازم است.

## 9. Phase بعدی
**PHASE 5 — Native Emergency Engine**: فرمالیزه کردن پل با Pigeon، LocationPolicy قابل‌config، Local Queue واقعی با backoff/سقف، lifecycle recovery، watchdog رسمی + تست‌های دستگاهی ماتریس کامل.
