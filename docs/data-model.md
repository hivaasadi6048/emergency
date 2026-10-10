# مدل داده — پلتفرم ایمنی شخصی و ارتباط اضطراری

- **سند:** `data-model.md`
- **نسخه:** 0.1 (Draft — PHASE 0)
- **تاریخ:** 2026-10-01
- **وضعیت:** در انتظار تأیید معماری

---

## 1. اصول

1. **PostgreSQL = source of truth.** Redis فقط ephemeral (Channels layer، rate limit، coordination کوتاه‌مدت).
2. کلیدهای اصلی UUID. زمان‌ها UTC و با `timezone=True`.
3. شماره موبایل با فرمت **E.164** نرمال‌شده ذخیره می‌شود (+98…)؛ نرمال‌سازی باید ارقام فارسی/عربی، `00` به‌جای `+`، فاصله و خط تیره را پوشش دهد و Unit Test اختصاصی داشته باشد.
4. حذف نرم فقط در جایی که قانون کاری ایجاب می‌کند (مثلاً `is_active` برای TrustedContact)؛ بقیه از status استفاده می‌کنند.
5. افزوده‌های این سند نسبت به فهرست اولیه فیلدهای نیازمندی، با برچسب **[افزوده]** مشخص شده‌اند و دلیل هر افزوده ذکر شده است.

## 2. نمودار ER (مفهومی)

```text
User 1───* Device
User 1───* TrustedContact
User 1───* EmergencySession *───1 Device
EmergencySession 1───* EmergencyEvent
EmergencySession 1───* LocationPoint
EmergencySession 1───* DeliveryAttempt *───1 TrustedContact
EmergencySession 1───* AccessLink        [افزوده]
User    1───* IdempotencyKey             [افزوده]
```

## 3. جدول‌ها

### User
```text
id            UUID PK
phone         VARCHAR(16) UNIQUE NOT NULL   -- E.164 نرمال‌شده
display_name  VARCHAR(120) NOT NULL
status        ENUM(ACTIVE, SUSPENDED, DELETED)
created_at / updated_at
```

### Device
```text
id                 UUID PK
user_id            FK -> User (index)
platform           ENUM(ANDROID)                -- iOS آینده
device_identifier  VARCHAR(255)                 -- هش‌شده یا opaque؛ PII خام نگه‌داری نمی‌شود
app_version        VARCHAR(32)
push_token         TEXT NULL                    -- فقط metadata زیرساختی؛ نبود آن dependency اضطراری نیست
last_seen_at       TIMESTAMPTZ
status             ENUM(ACTIVE, INACTIVE, REVOKED)
created_at / updated_at
```
`Q-06` (حداکثر Device و revocation) در Phase 2 حل می‌شود.

### TrustedContact
```text
id            UUID PK
user_id       FK -> User (index)
name          VARCHAR(120)
phone         VARCHAR(16) NOT NULL              -- E.164 نرمال‌شده
relationship  VARCHAR(64) NULL
priority      SMALLINT
is_active     BOOLEAN DEFAULT TRUE
created_at / updated_at
```

### EmergencySession
```text
id                        UUID PK
user_id                   FK -> User (index)
device_id                 FK -> Device NULL
status                    ENUM(IDLE*, TRIGGERED, STARTING, ACTIVE, DEGRADED, RESOLVING, RESOLVED, CANCELLED, FAILED)
trigger_type              ENUM(IN_APP_SOS, VOLUME_SEQUENCE, SAFETY_TIMER, FUTURE_WEARABLE)
started_at                TIMESTAMPTZ (ایجاد رکورد)
activated_at              TIMESTAMPTZ NULL (ورود به ACTIVE)
resolved_at               TIMESTAMPTZ NULL
last_location_at          TIMESTAMPTZ NULL
last_contact_attempt_at   TIMESTAMPTZ NULL
created_at / updated_at
```
\* `IDLE` فقط مفهوم «بدون Session» است و رکوردی با این status ذخیره نمی‌شود (اولین رکورد Session با TRIGGERED ساخته می‌شود).

### EmergencyEvent
```text
id          UUID PK
session_id  FK -> EmergencySession (index)
event_type  ENUM(SESSION_CREATED, TRIGGER_RECEIVED, TRIGGER_DUPLICATE_IGNORED, LOCATION_SERVICE_STARTED,
                 FIRST_LOCATION_RECEIVED, ALERT_ATTEMPTED, ALERT_RESULT, NETWORK_LOST, NETWORK_RESTORED,
                 STATE_CHANGED, SESSION_RESOLVED, SESSION_CANCELLED, SESSION_FAILED, ...)
payload     JSONB                                -- اسکیمای بسته، کلیدهای ثابت، سقف اندازه (~2KB)؛ داده حجیم/arbitrary ممنوع
created_at  (index ترکیبی با session_id)
```
`STATE_CHANGED` شامل `from_status`، `to_status`، `actor` (CLIENT/BACKEND/SYSTEM) است.

### LocationPoint
```text
id           UUID PK
session_id   FK -> EmergencySession (index)
client_uuid  UUID NOT NULL                      -- [افزوده] تولید توسط کلاینت؛ پایه dedupe/idempotency
latitude     NUMERIC(9,6) CHECK(-90..90)
longitude    NUMERIC(9,6) CHECK(-180..180)
accuracy_m   REAL NULL
altitude_m   REAL NULL
speed_mps    REAL NULL
heading_deg  REAL NULL
captured_at  TIMESTAMPTZ NOT NULL               -- زمان واقعی ثبت روی دستگاه
received_at  TIMESTAMPTZ NOT NULL DEFAULT now() -- زمان رسیدن به سرور — همیشه جدا از captured_at
source       ENUM(FGS_GPS, FGS_NETWORK, QUEUED_OFFLINE, MANUAL)   -- [افزوده] ریشه داده برای audit
created_at
```
آفست زمانی منطقی: `captured_at` نباید بیش از آستانه policy (پیشنهاد اولیه: 5 دقیقه گذشته / 10 دقیقه آینده) از `received_at` فاصله داشته باشد؛ خارج از بازه: پذیرش با flag (source/event) یا رد، طبق پارامتر config — تصمیم نهایی در Phase 3 با تست clock skew.

### DeliveryAttempt
```text
id                   UUID PK
session_id           FK -> EmergencySession (index)
trusted_contact_id   FK -> TrustedContact (index)
provider             ENUM(WEB, SMS_GATEWAY, FCM, FUTURE)
channel              VARCHAR(32)                  -- مثلا WEB_LINK / SMS / PUSH
status               ENUM(PENDING, SENT, DELIVERED, FAILED, CANCELLED, EXPIRED)
attempt_no           SMALLINT                     -- [افزوده] برای retry کنترل‌شده
attempted_at         TIMESTAMPTZ
delivered_at         TIMESTAMPTZ NULL
failed_at            TIMESTAMPTZ NULL
provider_message_id  VARCHAR(255) NULL
error_code           VARCHAR(64) NULL
created_at / updated_at
```
قاعده قطعی: `SENT` به هیچ وجه معادل `DELIVERED` فرض نمی‌شود. دنباله وضعیت‌های مجاز و گذارها در Phase 7 با State Machine کوچک خودش enforce می‌شود.

### AccessLink — [افزوده]
دلیل افزوده: نیاز «Emergency Web View» با دسترسی کوتاه‌عمر/قابل انقضا/قابل revoke، بدون URL دائمی.

```text
id            UUID PK
session_id    FK -> EmergencySession (index)
token_hash    CHAR(64) UNIQUE NOT NULL          -- SHA-256 از token؛ token خام فقط یک بار در پاسخ ساخت
expires_at    TIMESTAMPTZ
revoked_at    TIMESTAMPTZ NULL
created_at
```
token: حداقل 128 bit entropy، تصادفی، فقط در URL fragment/ path یک‌بار نمایش داده می‌شود؛ در log هرگز ثبت نمی‌شود.

### IdempotencyKey — [افزوده]
دلیل افزوده: الزام idempotency برای ایجاد Session، Upload Location، Resolve و ایجاد Alert با retry امن.

```text
id            UUID PK
user_id       FK -> User (index)
endpoint      VARCHAR(128)
key           VARCHAR(128)
request_hash  CHAR(64)                          -- تشخیصreuse همان key با body متفاوت
response_code SMALLINT
response_body JSONB
status        ENUM(IN_PROGRESS, COMPLETED)      -- رفع race دو request هم‌زمان با همان key
expires_at    TIMESTAMPTZ (پیشنهاد 24 ساعت)
created_at
UNIQUE (user_id, endpoint, key)
```

## 4. Constraint ها و Index های کلیدی

| ID | Constraint/Index | دلیل |
|---|---|---|
| C-01 | **Partial Unique Index** روی `emergency_sessions (user_id)` فقط برای `status IN (TRIGGERED, STARTING, ACTIVE, DEGRADED, RESOLVING)` | تضمین DB-level «فقط یک Session فعال برای هر User» — دفاع دوم در برابر race (اولین دفاع: service layer با row lock) |
| C-02 | **Unique** روی `location_points (session_id, client_uuid)` | dedupe دقیق Location حین retry/دوباره‌فرستادن queue |
| C-03 | Index روی `location_points (session_id, captured_at)` | ترتیب timeline و کوئری «آخرین موقعیت» |
| C-04 | Index روی `emergency_events (session_id, created_at)` | Event Timeline |
| C-05 | Index روی `delivery_attempts (session_id)` + unique عملیاتی `(session_id, trusted_contact_id, provider, channel, attempt_no)` | جلوگیری از Attempt تکراری در retry ها |
| C-06 | Index روی `trusted_contacts (user_id)` و `devices (user_id)` | کوئری‌های پرتکرار |
| C-07 | Index روی `access_links (session_id)` و lookup یکتا با `token_hash` | resolve سریع لینک بدون token scan |

رد هر index پیشنهادی دیگر باید با دلیل ثبت شود (الزام Phase 2).

## 5. سیاست Retention (پیش‌نویس — نیازمند تأیید Q-03)

- `location_points`: پیش‌فرض 90 روز پس از پایان Session، سپس حذف (configurable). هیچ تاریخچه بی‌نهایتی روی دستگاه هم نگه‌داری نمی‌شود.
- `emergency_events`: پیش‌فرض 180 روز.
- `access_links`: منقضی/revoked حذف یا anonimise می‌شوند.
- Log های عملیاتی: بدون داده حساس؛ location دقیق فقط داخل operational log های مجازِ Session.

## 6. الگوهای Redis (ephemeral)

| الگو | کاربرد | عمر |
|---|---|---|
| `channels` layer groups (`session.<id>`) | broadcast به Trusted Contact | دائمی‌نبودن — تضمین نمی‌شود |
| `rate:<scope>:<id>` | rate limiting (OTP، SOS، link) | پنجره شمارنده |
| `idem:lock:<user>:<endpoint>:<key>` | قفل کوتاه idempotency برای رفع race | ثانیه‌ها |

هیچ وضعیت اضطراری پایداری در Redis نگه‌داری نمی‌شود؛ ری‌استارت Redis نباید داده Session را از بین ببرد.
