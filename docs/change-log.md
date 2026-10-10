# Change Log — تصمیم‌ها و تغییرات اجرایی

- **قاعده:** هر تغییری نسبت به تصمیم‌های ثبت‌شده معماری یا کد منتشرشده، اینجا با دلیل و شواهد ثبت می‌شود (الزام نیازمندی: «معماری را بدون اعلام و ثبت تغییر نده»).
- اجازه اعمال تغییرات اصلاحی برای پیشرفت و اجرایی شدن پروژه توسط مالک محصول صادر شده است (2026-10-03) به شرط ثبت در همین سند.

| ID | تاریخ | تغییر | دلیل | فایل(ها) | شواهد/سند مرتبط |
|---|---|---|---|---|---|
| C-001 | 2026-10-01 | تنظیم build محیطی: آینه Aliyun Google-Maven به‌عنوان repository اول + `FLUTTER_STORAGE_BASE_URL=storage.flutter-io.cn` (setx کاربر) + `flutter config --jdk-dir` به JBR اندروید استودیو (JDK 21) | تحریم: `dl.google.com` مسدود، `download.flutter.io` متناوب 403؛ Java 8 ناکافی برای AGP | `android/settings.gradle.kts`, `android/build.gradle.kts`, `~/.gradle` env | compatibility-report §2.1-2.2 |
| C-002 | 2026-10-01 | targetSdk/compileSdk=36، minSdk=26 در gradle | الزام Play از 2026-08-31 + فرض A-01 | `android/app/build.gradle.kts` | architecture.md Q-04 |
| C-003 | 2026-10-03 | **Watchdog تازگی موقعیت** در سرویس: اگر >45s (4.5×interval) fix نیامد → `DEGRADED` + `LOCATION_DELIVERY_STALL` + re-request خودکار با API عمومی؛ شمارنده `stallRecoveries` به پل/UI اضافه شد | کشف قطع پنهان تحویل fix توسط OneUI حین قفل — اپ بدون این، ACTIVE کاذب نشان می‌داد | `EmergencyLocationService.kt`, `MainActivity.kt`, `lib/main.dart` | compatibility-report §7 ردیف 10 + `poc_r2_result.png` |
| C-004 | 2026-10-03 | Instrumentation: log های `PocVol` (ARMED/DISARMED، هر فشار، تشخیص توالی) | تست Volume Trigger بدون log قابل اعتماد نبود (حدس UI) | `MainActivity.kt` | logcat شواهد |
| C-005 | 2026-10-03 | **سیاست Volume Trigger**: شروع توالی فقط از سکوت (≥1s) + قفل re-arm بعد از هر تشخیص (5s) | یافته مالک: فشار پیوسته/سریع باعث تشخیص‌های پشت‌سرهم (هر ~0.5s) می‌شد — سیاست naive نبود مالکیت intentional را تفکیک می‌داد | `MainActivity.kt`, `lib/main.dart` | همین سند + ردیف 12 گزارش |
| C-006 | 2026-10-03 | وابستگی صریح `androidx.core:core-ktx:1.15.0` | قالب Flutter بلوک dependencies ندارد؛ کد سرویس از NotificationCompat/ContextCompat استفاده می‌کند | `android/app/build.gradle.kts` | بیلد موفق #4 |
| C-007 | 2026-10-03 | **PostgreSQL قابل‌حمل (Zonky 16) از Maven Central** + cluster محلی روی 127.0.0.1:5433 (بدون نصب سیستمی/admin) + دیتابیس‌های emergency_dev/test_emergency_dev | سیستم فاقد Docker/Postgres است؛ Maven Central در دسترس؛ SQLite ناقض «PostgreSQL source of truth» (D-15) | `backend/.localdb/` (gitignore) | phase-2-report §4 |
| C-008 | 2026-10-03 | **آینه PyPI (Aliyun)** برای pip (pypi.org مستقیم مسدود) + venv پروژه‌ای | تحریم PyPI | `backend/.venv/` (gitignore)، requirements.txt | phase-2-report |
| C-009 | 2026-10-03 | **D-16/D-17**: سقف صدور OTP سرویس‌محور (DB-backed)؛ exception handler یکپارچه خطاها | throttle مبتنی بر cache بین worker ها/تست‌ها ناپایدار؛ قرارداد خطای API نیازمند envelope ثابت | `accounts/services.py`, `accounts/views.py`, `config/exception_handler.py`, `config/settings/base.py` | phase-2-report §7 |
| C-010 | 2026-10-04 | **Endpoint جدید**: `POST /emergency/sessions/{id}/capability` — کلاینت FACT های capability (وضعیت سرویس native + شبکه) را گزارش می‌کند و backend طبق ماتریس failure-model وضعیت Session را می‌سازد | موتور State Machine به مسیر ورودی واقعی برای گذارهای STARTING→ACTIVE/DEGRADED/FAILED نیاز داشت؛ کلاینت هرگز status مستقیم نمی‌فرستد (معیار پذیرش Phase 3) | `emergency/views.py`, `emergency/serializers.py`, `emergency/services.py`, `docs/api-contract.md` | phase-3-report |
| C-011 | 2026-10-04 | **create_session در TRIGGERED می‌ماند** (خودکار به STARTING نمی‌رود)؛ اولین capability report گذار TRIGGERED→STARTING→target را انجام می‌دهد | پنجره معنی‌دار «لغو SOS تصادفی» (TRIGGERED→CANCELLED از سند state-machine) با پیشروی خودکار از بین می‌رفت؛ حالا UI می‌تواند قبل از فعال‌سازی لغو کند — دقیقاً مطابق جدول گذار سند | `emergency/services.py`, `emergency/tests/test_session_api.py`, `docs/state-machine.md` (توضیح §3) | 72/72 تست backend PASS |
| C-012 | 2026-10-04 | **Phase 4 با صفر وابستگی pub**: HTTP روی dart:io، توکن‌ها in-memory (run-scoped)، uuid دستی | pub.dev و pub.flutter-io.cn از شبکه در دسترس نیستند (TLS/timeout) | `mobile/lib/core/**`, `mobile/pubspec.yaml` (بدون تغییر) | flutter analyze 0 issue؛ 10/10 تست |
| C-013 | 2026-10-04 | پل موقت Flutter↔Kotlin از کانال Phase 1 (`emergency.poc/native`) در EmergencyScreen استفاده شد | اتصال زودهنگام SOS→FGS→capability برای نمایش واقعی ACTIVE/DEGRADED/FAILED؛ فرمالیزه شدن با Pigeon به Phase 5 موکول شد | `mobile/lib/core/native/emergency_native.dart` | phase-4-report |
| C-014 | 2026-10-05 | **پل آپلود موقعیت**: بافر native → بچ `POST /api/v1/locations` با client_uuid پایدار per-point (dedupe سرور) — پیش‌نمایش لوله Phase 5 روی پل موقت | مالک خواستار دیدن موقعیت در اپ بود؛ همه قطعات موجود بودند | `lib/state/app_state.dart` | phase-4-report |
| C-015 | 2026-10-05 | watchdog تونل dev (`adb reverse tcp:8001`) به‌صورت حلقه background روی سیستم توسعه | تونل با هر قطع USB/restart دیمون adb می‌پرد و اپ NETWORK می‌دید | فرآیند background (فقط dev) | phase-4-report §5 |

### اصلاحات باگ حین Phase 2 (چرخه TDD)
| ID | تاریخ | باگ | Fix |
|---|---|---|---|
| B-001 | 2026-10-01 | کامپایل: `Location.getProvider()` در compileSdk 36 nullable | null-safe در `EmergencyLocationService.kt` (شواهد: بیلد #3) |
| B-002 | 2026-10-03 | `ACTIVE_STATUSES` در Meta کلاس قابل دسترسی نبود (scoping پایتون) | انتقال به ثابت ماژول `ACTIVE_SESSION_STATUSES` |
| B-003 | 2026-10-03 | تست‌ها: IntegrityError خارج از savepoint → TransactionManagementError | wrap در `transaction.atomic()` |
| B-004 | 2026-10-03 | URL name های generics بدون router تعریف نشده بودند → NoReverseMatch | `name=` صریح در devices/contacts urls |
| B-005 | 2026-10-03 | import جاافتاده `timezone` در devices/services.py | اضافه شد |
| B-006 | 2026-10-03 | IntegrityError مخاطب تکراری به 500 تبدیل می‌شد | pre-check سریالایزر + backstop در view → 400 |
| B-007 | 2026-10-03 | تست locations: تداخل kwarg؛ تست emergency: سناریوی duplicate ناقص | بازنویسی تست‌ها |
| B-008 | 2026-10-03 | پاسخ create دستگاه 200 بود به‌جای 201 | status=201 صریح |
| B-009 | 2026-10-04 | services به `EmergencySession.ACTIVE_SESSION_STATUSES` (حذف‌شده) ارجاع می‌داد → AttributeError در همه create | import ثابت ماژول |
| B-010 | 2026-10-04 | `Replay` در ویوی create catch نمی‌شد → 500 روی replay | try/except Replay → پاسخ ذخیره‌شده |
| B-011 | 2026-10-04 | `InvalidTransition` از ویوهای action بیرون می‌زد (500) و `_conflict_response` روی آن AttributeError می‌داد | catch دوگانه + نگاشت یکپارچه 409 CONFLICT_INVALID_TRANSITION |
| B-012 | 2026-10-04 | exception handler کد داخلی DRF ('invalid') را به‌جای کد قرارداد برمی‌گرداند | CODE_MAP مقدم بر default_code |
| B-013 | 2026-10-04 | خطای یک point کل batch را 400 می‌کرد | اعتبارسنجی per-point → لیست `rejected` با دلیل (clock_skew/…) |
| B-014 | 2026-10-04 | شکل پاسخ 409 duplicate ناسازگار (جای `existing_session`) | ساختار یکپارچه سطح بالا + snapshot idempotency هماهنگ |
| B-015 | 2026-10-04 | مسیر race در create_session کلاس استثنای سفارشی می‌گرفت که Django هرگز raise نمی‌کرد | `django.db.IntegrityError` + savepoint |
| B-016 | 2026-10-04 | باگ‌های تستی: import سایه‌دار در wrapper، صدا زدن positional سرویس keyword-only، تداخل C-01 بین subTest ها، assert ناقص replay | اصلاح تست‌ها |
| B-017 | 2026-10-04 | **گزارش مالک:** دکمه «دریافت کد تأیید» با تایپ شماره فعال نمی‌شد — تغییر متن TextField خودش rebuild نمی‌کند و listener فقط در حالت خطا setState می‌کرد؛ + خطای شبکه در requestOtp بی‌صدا قورت می‌رفت | listener بدون شرط setState؛ try/catch + بنر خطا در requestOtp؛ پاک‌ساز ورودی شماره (نشانه‌های نامرئی RTL/ارقام فارسی)؛ **widget test رگرسیون** برای فعال‌شدن دکمه (`login_button_regression_test.dart`) |
| B-018 | 2026-10-04 | **گزارش مالک (۲ ساعت گیر):** «شماره موبایل معتبر نیست» برای هر شماره — کلاینت Dart بدون Content-Length بدنه را **chunked** می‌فرستد و http.server پایتون (Django dev server) chunked را نمی‌فهمد → بدنه خالی می‌رسید + بایت‌های باقی‌مانده اتصال keep-alive را خراب می‌کرد (`Bad request syntax ('17')` در لاگ) | Content-Length صریح در ApiClient + fake backend حالا درخواست chunked را 400 می‌کند (تست رگرسیون) |
| B-019 | 2026-10-05 | watchdog در شاخه LOCATION_SERVICES_OFF استارت نمی‌شد → پس از روشن‌کردن Location توسط کاربر، هیچ بازیابی خودکاری رخ نمی‌داد | watchdog از همان ابتدای onStartCommand فعال می‌شود |
| B-020 | 2026-10-05 | جریان SOS بدون درخواست مجوز → پس از نصب مجدد، سرویس ساکت شکست می‌خورد و Session در TRIGGERED گیر می‌کرد | گیت مجوز در sos(): requestPermissions + انتظار ≤10s → در صورت رد: گزارش FAILED صادقانه + پیام راهنما |
