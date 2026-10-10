# Threat Model — پلتفرم ایمنی شخصی و ارتباط اضطراری

- **سند:** `threat-model.md`
- **نسخه:** 0.1 (Draft — PHASE 0)
- **تاریخ:** 2026-10-01
- **وضعیت:** در انتظار تأیید معماری (چارچوب: STRIDE)

---

## 1. Asset ها (دارایی‌ها)

| Asset | حساسیت |
|---|---|
| موقعیت مکانی (LocationPoint ها) | بسیار بالا |
| وضعیت EmergencySession و Timeline | بالا |
| Access Link های Trusted Contact | بالا (گذرنده = دیدن موقعیت) |
| توکن‌های احراز هویت / refresh tokens | بالا |
| PII (شماره موبایل، نام، رابطه مخاطبین) | بالا |
| DeliveryAttempt ها (چه کسی کجا مطلع شد) | متوسط تا بالا |
| Secret های سرور (DB، درگاه SMS، signing keys) | بحرانی |

## 2. Actor ها و مرزهای اعتماد

```text
[مهاجم بیرونی] ──┐
[Trusted Contact] ├─ HTTPS ── [Backend (trusted)] ── [PostgreSQL/Redis]
[کاربر مالک]     ─┘                       │
                                     [Providerهای بیرونی: SMS/FCM — نیمه‌مطمئن]
```

- مرز 1: دستگاه کاربر ↔ Backend
- مرز 2: مرورگر مخاطب ↔ Backend (بدون اکانت، با signed token)
- مرز 3: Backend ↔ Providerهای بیرونی
- Backend و DB داخل مرز اعتماد سرور؛ دسترسی DB با least privilege.

## 3. STRIDE — تهدیدها و Mitigation ها

| ID | تهدید | دسته | Mitigation | Phase |
|---|---|---|---|---|
| T-01 | دسترسی غیرمجاز به موقعیت کاربر دیگر (IDOR) | Information Disclosure / Elevation | object-level authorization در هر endpoint؛ تست خودکار «کاربر A نمی‌تواند Session/location کاربر B را ببیند» | 3، تست 10 |
| T-02 | نشت/forward شدن Access Link | Information Disclosure | TTL کوتاه، token با entropy ≥128 bit و hash‌شده، revoke، rate limit؛ **محدودیت ذاتی: forward کامل جلوگیری‌ناپذیر است — صادقانه مستند می‌شود** | 8/10 |
| T-03 | حدس/brute-force توکن viewer | Spoofing | طول و entropy بالا + rate limit روی `/w/`,`/view/`,`/ws/view/` | 8/10 |
| T-04 | Replay ارسال Location / forged captured_at | Tampering | idempotency + بازه مجاز captured_at (clock skew policy) + auth اجباری | 3/9 |
| T-05 | Sokect/پوشش بدون مجوز به WS مخاطب | Spoofing | authorization در connect و subscribe؛ گروه per-session | 6 |
| T-06 | abuse SOS برای هرزSession / DDoS منابع | DoS | rate limit (Redis)، سقف Session فعال (C-01)، سقف payload | 2/3/10 |
| T-07 | افشای اطلاعات در log (token، location، شماره) | Information Disclosure | قواعد logging: بدون token/secret/location دقیق خارج operational log؛ correlation id؛ تست بررسی خروجی log | همه Phase ها |
| T-08 | نشت secret (hard-code/commit) | Information Disclosure | ممنوعیت commit؛ env/secret manager؛ گیت چک در CI | 2/11 |
| T-09 | MITM | Spoofing/Tampering | HTTPS الزامی در production، HSTS، certificate pinning در اپ (تصمیم نهایی Phase 4 با ریسک قفل‌شدن چرخش گواهی) | 4/11 |
| T-10 | شماره‌کاوی از endpoint های OTP | Information Disclosure | پاسخ یکنواخت 204، rate limit سخت، captcha/تأخیر در تکرار | 2/10 |
| T-11 | تزریق payload در EmergencyEvent | Tampering | اسکیمای بسته، سقف حجم، validation سخت | 3 |
| T-12 | Provider مخرب/ناقص (SMS/FCM) | Repudiation/Denial | DELIVERY tracking مستقل از provider؛ DeliveryAttempt به‌عنوان record مرجع؛ provider شکست‌خورده قابل تعویض | 7 |
| T-13 | نفوذ به admin/ops | Elevation | کمترین سطح دسترسی DB، جدا کردن اکانت ادمین، audit events | 10/11 |

## 4. سناریوهای حیاتی (End-to-End)

1. **«مخاطب علیه کاربر»:** مخاطب با لینک معتبر فقط همان Session را می‌بیند و بعد از انقضا/revoke هیچ؛ هیچ مسیری برای query تاریخچه/کاربران دیگر وجود ندارد.
2. **«مهاجم بیرونی بدون توکن»:** همه مسیرهای داده مستلزم auth یا token viewer هستند؛ بدون آن فقط 401/403.
3. **«کاربر خودش را گروگان‌گیری اطلاعاتی می‌کند»:** لاگ‌ها و API هیچ محتوای موقعیتی خارج از session های مجاز ارائه نمی‌دهند.
4. **«Replay Attack روی SOS»:** همان Idempotency-Key همیشه نتیجه یکسان می‌دهد؛ Session دوم ساخته نمی‌شود.

## 5. قواعد ثابت امنیتی (از نیازمندی، enforce-شونده)

- HTTPS در production؛ هیچ secret/api key/password/private key در کد یا commit؛
- rate limiting و request validation همه‌جا؛ audit events برای عملیات حساس؛
- database least privilege؛ عدم ثبت اطلاعات حساس در log؛
- عدم استفاده از location دقیق در analytics؛
- short-lived signed access برای مخاطبین، قابل انقضا و revoke، بدون URL دائمی.

## 6. ریسک‌های باقی‌مانده (Residual)

| ریسک | توضیح صادقانه |
|---|---|
| Forward شدن لینک | با کنترل فنی کامل قابل جلوگیری نیست؛ با TTL/revoke کاهش می‌یابد |
| توکن در حافظه دستگاه مخاطب | مرورگر کنترل کامل lifetime را نمی‌دهد؛ TTL کوتاه جبران می‌کند |
| هویت مخاطب = شماره موبایل | تأیید مالکیت شماره مخاطب در MVP انجام نمی‌شود (مخاطب اکانت ندارد)؛ ریسک شماره اشتباه توسط کاربر — UI تأیید دو مرحله‌ای پیشنهاد Phase 4 |
| تحویل SMS/FCM | خارج از کنترل ما؛ فقط best-effort و ردیابی وضعیت واقعی |
