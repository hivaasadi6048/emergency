# Failure Model — پلتفرم ایمنی شخصی و ارتباط اضطراری

- **سند:** `failure-model.md`
- **نسخه:** 0.1 (Draft — PHASE 0)
- **تاریخ:** 2026-10-01
- **وضعیت:** در انتظار تأیید معماری

---

## 1. اصول

1. هر Failure الزاماً Session را FAILED نمی‌کند؛ وضعیت بر اساس **capability باقی‌مانده** و policy زیر تعیین می‌شود.
2. وضعیت واقعی باید صادقانه گزارش شود (UI + Event Timeline)؛ هیچ failure با پیام مبهم پنهان نمی‌شود.
3. `SENT` هرگز معادل `DELIVERED` فرض نمی‌شود.
4. شکست FCM یا هر provider اختیاری، هرگز false success یا FAILED کل Session تولید نمی‌کند.
5. هر failure باید Event مربوطه را در Timeline تولید کند (بدون داده حساس).

## 2. مدیریت 22 Failure الزامی

| # | Failure | تشخیص | واکنش / Policy | اثر روی Session |
|---|---|---|---|---|
| 1 | GPS unavailable | provider/accuracy callback | اگر شبکه هست، تلاش برای location با دقت پایین‌تر (network) + گزارش DEGRADED | DEGRADED |
| 2 | Location accuracy پایین | `accuracy_m` بالای آستانه policy | ثبت نقطه با flag accuracy؛ UI accuracy را نشان می‌دهد؛ آستانه در LocationPolicy | ACTIVE با گزارش صادقانه (نه مسکوت) |
| 3 | Internet unavailable | ارسال ناموفق به backend | نقاط در Local Queue (بخش 4)؛ هشدار اولیه اگر از طریق SMS دستی/خودکار ممکن باشد | DEGRADED (اگر FGS فعال) |
| 4 | Backend unavailable | timeout/5xx | همان #3 + retry با backoff؛ UI وضعیت را نشان می‌دهد | DEGRADED |
| 5 | WebSocket disconnect | heartbeat/close | فقط اطلاع‌رسانی به مخاطب مختل؛ ingest از مسیر REST مستقل است؛ reconnect + state sync | بدون تغییر الزامی؛ Event `NETWORK_LOST` سمت وب |
| 6 | Alert Provider unavailable | شکست provider | تلاش با provider دیگر طبق اولویت؛ ثبت `ALERT_RESULT(FAILED)` | DEGRADED اگر همه کانال‌های هدف شکست خورده‌اند |
| 7 | Battery بسیار کم | broadcast سطح باتری | سوییچ LocationPolicy به low_battery (interval بالاتر) + گزارش DEGRADED | DEGRADED |
| 8 | Location Permission لغوشده | SecurityException / callback | توقف جمع‌آوری؛ UI راهنمای فعال‌سازی؛ اگر هیچ capability نماند → FAILED طبق policy؛ Session فعال به‌صورت صادقانه نشان داده می‌شود | DEGRADED→FAILED طبق policy |
| 9 | Location Services خاموش | ProviderStatus callback | مشابه #8؛ گزارش صریح | DEGRADED→FAILED طبق policy |
| 10 | Notification Permission unavailable | چک permission | FGS بدون notification قابل نمایش نیست — SOS flow قبل از فعال‌سازی آن را می‌خواهد؛ در نبودش: ادامه با پیامد صریح طبق رفتار واقعی دستگاه (validate در Phase 5) | حداقل DEGRADED + هشدار |
| 11 | Foreground Service start failure | exception در start | policy: اگر هیچ مسیر Location باقی نماند → `STARTING→FAILED`؛ در غیر این صورت DEGRADED | FAILED / DEGRADED |
| 12 | App Process killed | — | بازگشت: Session فعال در backend می‌ماند؛ در باز شدن اپ state از backend sync می‌شود؛ دکمه ادامه/resolve | بدون تغییر server-side |
| 13 | Device reboot | — | Session فعال در backend باقی می‌ماند؛ recovery خودکار FGS فقط با validation (Q-05)؛ در نبود آن: Session تا sync بعدی DEGRADED اعلام می‌شود | DEGRADED |
| 14 | Authentication expired | 401 | refresh خودکار؛ در شکست: صف محلی ادامه می‌دهد، ارسال پس از re-auth؛ UI وضعیت auth را نشان می‌دهد | بدون تغییر state؛ تا سقف policy |
| 15 | Duplicate SOS | idempotency + C-01 | همان Session برمی‌گردد + `TRIGGER_DUPLICATE_IGNORED` | بدون تغییر |
| 16 | Duplicate Location Update | C-02 (client_uuid) | dedupe؛ پاسخ `duplicates` | بدون تغییر |
| 17 | Server timeout | timeout client | retry با backoff + idempotency key (هر retry همان key) | بدون تغییر تا سقف retry |
| 18 | Request replay | Idempotency-Key + request_hash | پاسخ ذخیره‌شده یا `IDEMPOTENCY_KEY_REUSED` (body متفاوت) | بدون تغییر |
| 19 | Device/server clock skew | بازه مجاز captured_at | نقاط خارج بازه: flag/Reject طبق config؛ ترتیب‌بندی timeline با received_at + captured_at مستند | بدون تغییر (flag) |
| 20 | Partial Provider failure | per-provider نتیجه | ترکیب نتایج؛ موفقیت هر provider کافی برای ادامه ولی وضعیت هر مخاطب جدا ردیابی می‌شود | ACTIVE/DEGRADED طبق policy |
| 21 | FCM unavailable | شکست/نبود token | **هیچ اثری بر صحت Session**؛ فقط رکورد FAILED در DeliveryAttempt | بدون تغییر |
| 22 | Provider delivery uncertainty | SENT ولی بدون رسید DELIVERED | status = SENT باقی می‌ماند؛ UI «در انتظار تأیید تحویل» نه «تحویل شد» | بدون تغییر |

## 3. ماتریس ترکیب وضعیت Session

Session status از ترکیب capability ها محاسبه می‌شود (بدترین وضعیت غالب است):

| Location (FGS) | Network→Backend | Alerts | → Session Status |
|---|---|---|---|
| فعال | سالم | حداقل یک کانال SENT/DELIVERED | ACTIVE |
| فعال | قطع | هر وضعیت | DEGRADED |
| فعال با دقت پایین | سالم | سالم | ACTIVE + flag صادقانه |
| توقف (permission/services off) | سالم | سالم | DEGRADED→FAILED طبق policy |
| غیرقابل شروع | هر | هر | FAILED (STARTING→FAILED) |
| فعال | سالم | همه کانال‌ها FAILED | DEGRADED |

این ماتریس باید در Phase 3 به‌صورت Unit Test جدول‌محور پیاده شود.

## 4. Offline Location Queue (سیاست)

- **سقف اندازه:** پیشنهاد 200 نقطه/Session (configurable) — پرشدن: جایگزینی قدیمی‌ترین با ثبت Event `QUEUE_OVERFLOW` (رفتار باید مستند و در UI بازتاب داشته باشد).
- **حداکثر عمر:** پیشنهاد 24 ساعت (configurable) — منقضی‌ها دور ریخته می‌شوند با Event.
- **فیلدهای حفظ‌شده:** `captured_at` همیشه حفظ می‌شود و از `received_at` جدا است.
- **Retry:** backoff نمایی با سقف؛ فقط پس از بازگشت شبکه ارسال، با ترتیب captured_at.
- **Idempotency:** هر نقطه `client_uuid` ثابت خودش را دارد؛ ارسال مجدد باعث رکورد تکراری نمی‌شود (C-02).
- **Process restart:** queue در storage محلی کوچک (capped) persist می‌شود؛ بازیابی پس از restart در حد policy قابل اتکاست (تست Phase 5).

## 5. Provider Policy

- ترتیب تلاش (قابل config): Web (لینک) → SMS Gateway (اگر فعال) → FCM (اگر فعال، best-effort).
- retry کنترل‌شده با سقف (پیشنهاد: 3 بار per provider، backoff).
- نبود provider (مثلاً FCM token موجود نیست) = failure ثبت‌شده، نه crash و نه success کاذب.
- شکست همه provider ها به‌تنهایی Session را FAILED نمی‌کند (اطلاع‌رسانی مدام تلاش می‌شود)؛ ولی وضعیت DEGRADED و Event ثبت می‌شود.

## 6. معیار پذیرش این سند (Phase 3/9)

- هر 22 failure یک تست/سناریوی معیارشده در testing-plan.md داشته باشد.
- رفتار هر failure قابل پیش‌بینی و مطابق ماتریس بخش 3 باشد.
- هیچ failure با پیام مبهم پنهان نشود.
