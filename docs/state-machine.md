# State Machine — EmergencySession

- **سند:** `state-machine.md`
- **نسخه:** 0.1 (Draft — PHASE 0)
- **تاریخ:** 2026-10-01
- **وضعیت:** در انتظار تأیید معماری

---

## 1. State ها

| State | معنا | نکته |
|---|---|---|
| `IDLE` | بدون Session فعال | حالت مفهومی؛ رکورد DB ساخته نمی‌شود |
| `TRIGGERED` | Trigger دریافت شد، Session در حال ساخت | لایه‌ی ثبت اولیه |
| `STARTING` | در حال راه‌اندازی capabilities (FGS، Location، Alert اولیه) | |
| `ACTIVE` | حداقل capability اصلی (Location سرویس) فعال و عملیاتی | |
| `DEGRADED` | عملیاتی ولی با کاهش قابلیت (به‌صورت صادقانه گزارش می‌شود) | دلیل degraded در Event ثبت می‌شود |
| `RESOLVING` | فرایند پایان (Resolve) در جریان است | resolve **idempotent** است و تا RESOLVED تلاش می‌شود |
| `RESOLVED` | پایان تأییدشده (توسط کاربر) | نهایی |
| `CANCELLED` | کاربر قبل از فعال‌سازی انصراف داده | نهایی |
| `FAILED` | راه‌اندازی شکست خورد | نهایی؛ برای ادامه، Session جدید لازم است |

## 2. Transition های مجاز (منطبق با نیازمندی)

```text
IDLE        -> TRIGGERED        (ساخت Session — فقط با موفقیت dedupe/idempotency)
TRIGGERED   -> STARTING
TRIGGERED   -> CANCELLED        (انصراف کاربر قبل از فعال‌سازی)
STARTING    -> ACTIVE
STARTING    -> DEGRADED
STARTING    -> FAILED
ACTIVE      -> DEGRADED
DEGRADED    -> ACTIVE
ACTIVE      -> RESOLVING
DEGRADED    -> RESOLVING
RESOLVING   -> RESOLVED
```

Transition های دیگر **همگی غیرمجاز** هستند و باید با خطای `CONFLICT_INVALID_TRANSITION` رد شوند.

## 3. معنای دقیق گذارها و Guard ها

| گذار | Guard / شرط | Event ثبت‌شده |
|---|---|---|
| IDLE→TRIGGERED | Trigger معتبر + auth + نبود Session فعال دیگر + idempotency key تازه/تکراری مدیریت‌شده | `SESSION_CREATED`, `TRIGGER_RECEIVED`؛ اگر duplicate: بدون ساخت Session دوم فقط `TRIGGER_DUPLICATE_IGNORED` و برگرداندن Session موجود |
| TRIGGERED→STARTING | شروع فرایند راه‌اندازی capabilities | `STATE_CHANGED` |
| TRIGGERED→CANCELLED | درخواست Cancel معتبر از مالک Session | `SESSION_CANCELLED` |
| STARTING→ACTIVE | FGS با type=location در حال اجرا + مجوزها برقرار | `LOCATION_SERVICE_STARTED` |
| STARTING→DEGRADED | FGS فعال اما یک capability از دست رفته (مثلاً اینترنت) | دلیل در payload |
| STARTING→FAILED | FGS قابل شروع نیست یا مجوز ضروری موجود نیست — طبق policy مستند failure-model | `SESSION_FAILED` |
| ACTIVE↔DEGRADED | تغییر وضعیت capability طبق ماتریس policy | `NETWORK_LOST/RESTORED`، `ALERT_RESULT` و… |
| ACTIVE/DEGRADED→RESOLVING | درخواست Resolve از مالک (idempotent) | `STATE_CHANGED` |
| RESOLVING→RESOLVED | پایان کامل: توقف Location، finalize alertها، broadcast نهایی | `SESSION_RESOLVED` |

نکات تصمیم‌شده:

1. **Cancel پس از ACTIVE وجود ندارد** (طبق لیست مجاز). UI دکمه Cancel حین Session فعال را به **Resolve** نگاشت می‌کند و این نگاشت باید در UI صادقانه نمایش داده شود.
2. **RESOLVING ممکن است طول بکشد** (مثلاً توقف Service یا انتظار finalize)؛ Resolve idempotent است، تکرار request خطا نمی‌دهد و state نادرست نمی‌سازد.
3. `FAILED`/`RESOLVED`/`CANCELLED` نهایی هستند؛ بازگشت از آن‌ها غیرمجاز است. ساخت Session جدید پس از Session نهایی مجاز است (محدود با rate limit).

## 4. Enforcement در Backend

1. **Service layer + row lock:** هر transition در یک تراکنش با `SELECT … FOR UPDATE` روی رکورد Session انجام می‌شود؛ رقابت دو request هم‌زمان serialize می‌شود.
2. **جدول transition مجاز** به‌صورت configuration در کد (نه شرط‌های پراکنده) — ورود state غیرمجاز رد می‌شود.
3. **C-01 (partial unique index)** در DB دفاع دوم در برابر Session دوم است.
4. **Event `STATE_CHANGED`** همراه هر گذار و در همان تراکنش ثبت می‌شود — Timeline همیشه با State سازگار است.
5. Client هرگز status دلخواه ارسال نمی‌کند؛ فقط **action** (resolve/cancel) می‌فرستد و گذارها سمت سرور از روی state فعلی محاسبه می‌شوند.

## 5. Idempotency × State Machine

| سناریو | رفتار الزامی |
|---|---|
| Duplicate SOS (همان Idempotency-Key یا trigger تازه با Session فعال) | همان Session برگردانده می‌شود؛ `TRIGGER_DUPLICATE_IGNORED` ثبت؛ **Session دوم ساخته نمی‌شود** |
| Retry Resolve با همان key | پاسخ ذخیره‌شده‌ی idempotency برمی‌گردد؛ گذار مضاعف رخ نمی‌دهد |
| Resolve بدون key ولی Session RESOLVED | پاسخ موفق idempotent با همان Session |
| Retry Upload Location با همان `client_uuid` | بدون رکورد جدید (C-02)؛ پاسخ همان نتیجه |
| Race دو درخواست هم‌زمان | row lock + `IdempotencyKey.status=IN_PROGRESS`؛ نتیجه: دقیقاً یک Session/یک گذار |

## 6. معیار پذیرش مربوط به State Machine (برای Phase 3)

- تمام transition های مجاز با تست Pass شوند.
- تمام transition های غیرمجاز (شامل گذار از state های نهایی) Reject شوند.
- Client نتواند state دلخواه تعیین کند (تست با ارسال status در payload).
- Duplicate SOS در تست race، فقط یک Session بسازد.
- هر گذار دقیقاً یک Event داشته باشد؛ Timeline و status همیشه سازگار.
- retry ها هیچ‌گاه گذار غیرمجاز ایجاد نکنند.
