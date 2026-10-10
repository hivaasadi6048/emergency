# PHASE REPORT — PHASE 2: Backend Foundation

- تاریخ: 2026-10-03
- Status: **PASS**

## 1. هدف Phase
پیاده‌سازی Backend بر اساس معماری مصوب: Django Modular Monolith، PostgreSQL source of truth، مدل داده کامل، Authentication با OTP، و تست‌ها — بدون ورود به Emergency Domain APIs (Phase 3).

## 2. خروجی‌های مورد انتظار
اسکلت backend/ (config + 6 اپ)، مدل‌های طبق data-model.md (با افزوده‌های مستند)، migration، auth OTP، constraint ها و index ها، تست‌ها.

## 3. موارد پیاده‌سازی‌شده

| Feature | Status | Files | Notes |
|---|---|---|---|
| اسکلت Modular Monolith | DONE | `backend/config/` + `accounts/ devices/ contacts/ emergency/ locations/ notifications/` | مطابق architecture.md §12 |
| مدل User + OTP | DONE | `accounts/models.py`, `services.py`, `phone.py` | OTP هش می‌شود (بدون ذخیره خام)، TTL 5min، سقف 5 تلاش، سقف صدور 3/10min per phone (سرویس‌محور) |
| Phone normalization | DONE | `accounts/phone.py` | ارقام فارسی/عربی، 00، +98، 09، 9، جداکننده‌ها — دامنه: موبایل ایران (+989…) |
| JWT auth (SimpleJWT) | DONE | `accounts/views.py`, `config/settings/base.py` | access 15min، refresh 14d با rotation+blacklist؛ logout با blacklist |
| Device (hash شناسه) | DONE | `devices/` | شناسه خام ذخیره نمی‌شود — فقط SHA-256؛ upsert با last_seen |
| TrustedContact CRUD | DONE | `contacts/` | soft delete؛ partial-unique برای contact فعال تکراری |
| مدل‌های Emergency | DONE | `emergency/models.py` | Session + Event + AccessLink + IdempotencyKey (فقط schema؛ API در Phase 3) |
| LocationPoint | DONE | `locations/models.py` | C-02, C-03 + check constraint مختصات |
| DeliveryAttempt | DONE | `notifications/models.py` | C-05 —_SENT≠DELIVERED در طراحی وضعیت‌ها |

## 4. تست‌های اجراشده

- Test: کل سوئیت Backend
  - Type: Unit + Integration (Django TestCase روی PostgreSQL واقعی)
  - Environment: Windows / Python 3.10.11 / Django 5.2.17 / PostgreSQL 16 (Zonky portable) / DB تست پاک `test_emergency_dev`
  - Command: `manage.py test --settings=config.settings.test`
  - Expected: همه Pass
  - Actual: **Ran 39 tests — OK** (0 fail / 0 error)
  - Result: PASS
  - Evidence: خروجی بالا؛ پوشش: 15 تست نرمال‌سازی شماره، 10 تست جریان OTP/auth، 1 تست سیاست no-secret-logging، 4 تست Device (شامل عدم ذخیره شناسه خام و جداسازی object-level)، 4 تست Contacts (شامل isolation و duplicate)، 3 تست constraint Session (C-01)، 4 تست constraint Location (C-02/C-03 + بازه مختصات)

- Test: مهاجرت روی محیط پاک
  - Type: Integration
  - Environment: `emergency_dev` تازه‌ساخت (empty) روی PostgreSQL 16
  - Command: `manage.py migrate`
  - Expected: تمام migration ها OK
  - Actual: همه OK (شامل 6 اپ + auth + token_blacklist)
  - Result: PASS

- Test: constraint های سطح DB در PostgreSQL واقعی
  - Type: Integration / Security
  - Command: کوئری pg_constraint/pg_indexes
  - Expected: C-01..C-05 موجود
  - Actual: `uniq_active_session_per_user` (partial unique — تعریف کامل استخراج شد)، `uniq_location_client_uuid`، `uniq_device_per_user`، `uniq_idempotency_key`، `uniq_delivery_attempt_per_target`، `chk_latitude_range`، `chk_longitude_range`
  - Result: PASS

## 5. معیارهای پذیرش فاز (تطبیق با سند)

| معیار | نتیجه |
|---|---|
| migration روی محیط پاک | ✓ |
| constraint ها و relationها صحیح | ✓ (شواهد DB + تست‌ها) |
| phone normalization تست شود | ✓ (15 تست) |
| indexها ایجاد یا دلیل رد ثبت شود | ✓ (C-01..C-05؛ C-06/C-07 به‌صورت index های ساده روی user/session) |
| داده حساس log نشود | ✓ (تست سیاست: کد OTP/token ها/شماره خام در لاگ نیستند) |
| authorization پایه | ✓ (secure-by-default + object-level برای devices/contacts) |
| Unit و Integration Testها Pass | ✓ (39/39) |
| API Contract با مدل واقعی سازگار | ✓ با یک انحراف مستند (بخش 6) |

## 6. محدودیت‌ها و رفتار Degraded / انحرافات مستند

1. **OTP هنوز SMS ندارد** (Q-01 باز است): در حالت dev `debug_code` در پاسخ برگردانده می‌شود (فقط وقتی `OTP_DEV_MODE=True`؛ production هرگز). به همین دلیل `request-otp` فعلاً 200 با payload برمی‌گرداند نه 204 خالص — با آمدن Provider در Phase 7 هم‌راستا می‌شود.
2. **Redis هنوز استفاده نشده** (Phase 6) — throttle عمومی فعلاً LocMem (per-process) است؛ سهمیه OTP سرویس‌محور و DB-backed است.
3. **کنترل clock-skew در captured_at** در لایه API Phase 3 اعمال می‌شود (در schema الان فقط فیلدها جدا هستند).
4. کلاستر Postgres محلی با trust auth و فقط 127.0.0.1:5433 — پیکربندی production در Phase 11.
5. `SECRET_KEY` در dev از env یا fallback تصادفی dev-only؛ settings های production (Phase 11) اجباری می‌کنند.

## 7. تصمیم‌های معماری جدید

- D-15: **PostgreSQL قابل‌حمل (Zonky) از Maven Central به‌جای نصب سیستمی/Docker** — دلیل: هیچ Postgres/Docker روی سیستم نیست و Maven Central در دسترس است؛ Impact: DB dev/test قابل تکرار و بدون admin؛ جایگزین ردشده: SQLite (ناقض «PostgreSQL source of truth») و نصب EDB (نیاز به interaction/admin).
- D-16: **سقف صدور OTP سرویس‌محور (DB)** به‌جای throttle مبتنی بر cache — قابل اتکا در multi-worker و مستقل از Redis.
- D-17: **پاسخ خطای یکپارچه** `{"error":{code,message,details}}` با exception handler سفارشی (قرارداد API).

همه در `docs/change-log.md` (C-007..C-009) ثبت شدند.

## 8. فایل‌های تغییرکرده
- Added: کل `backend/` (manage.py، config/ با 3 settings، 6 اپ با models/serializers/views/urls/tests، requirements.txt)، `docs/phase-2-report.md`، `docs/change-log.md`
- Modified: `README.md` (وضعیت فازها)
- Deleted: —

## 9. ریسک‌های باقی‌مانده
- R-03 (درگاه OTP/پیامک ایران) — همچنان باز (Q-01)؛ mitigate: چون OTP سرویس‌محور است، تعویض provider فقط در `accounts/services` رخ می‌دهد.
- عملکرد: هنوز load test نشده (Phase 11).
- نگهداشت داده: retention job ها هنوز پیاده نشده (نیازمندی Privacy — به Phase 3/11 موکول شد و در ریسک ثبت می‌شود).

## 10. نتیجه توقف یا ادامه
- Decision: **STOP**
- Reason: معیارهای پذیرش Phase 2 برآورده شد؛ طبق پروتکل فازها، قبل از ورود به Phase 3 تأیید مالک لازم است.
- Required approval: تأیید گزارش + پاسخ نداشتن به موانع (Q-01 می‌تواند بعداً پاسخ دهد).

## 11. Phase بعدی
**PHASE 3 — Emergency Domain**: State Machine enforcement، Idempotency عملیاتی، Emergency APIs (create session / resolve / cancel / events / locations با dedupe)، Event Timeline کامل، تست‌های گذار مجاز/غیرمجاز و duplicate/race.
