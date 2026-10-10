# معماری مرجع — پلتفرم ایمنی شخصی و ارتباط اضطراری

- **سند:** `architecture.md`
- **نسخه:** 0.1 (Draft — PHASE 0)
- **تاریخ:** 2026-10-01
- **وضعیت:** در انتظار تأیید معماری. تا تأیید صریح مالک محصول، هیچ implementation جدی شروع نمی‌شود (STOP Gate).

---

## 1. هدف سند

این سند تصمیم‌های معماری، فرض‌ها، سؤالات باز، ریسک‌ها و یافته‌های اولیه بررسی مستندات رسمی را ثبت می‌کند. هر تصمیم دارای Rationale، گزینه‌های ردشده و Impact است. تغییر هر تصمیم در آینده باید در همین سند با شماره نسخه جدید ثبت شود.

## 2. خلاصه محصول و تعهدات صادقانه

سیستم، ارتباط اضطراری شخصی و اشتراک‌گذاری موقعیت است: کاربر Emergency Session را فعال می‌کند، سیستم موقعیت را تا پایان Session جمع‌آوری می‌کند و اطلاعات را از طریق AlertProvider ها به Trusted Contact ها می‌رساند.

محصول **هرگز** این‌ها را ادعا نمی‌کند:

- جرم را متوقف می‌کند.
- نجات را تضمین می‌کند.
- تحویل پیام را تضمین می‌کند.
- دریافت موقعیت را در تمام شرایط تضمین می‌کند.

این محدودیت‌ها باید در UI، مستندات و پیام‌های محصول منعکس شوند.

## 3. مرزهای MVP (ممنوعه‌های قطعی)

| مورد | وضعیت |
|---|---|
| اتصال مستقیم به پلیس/اورژانس/آتش‌نشانی | ممنوع در MVP |
| تشخیص خودکار خطر با AI | ممنوع در MVP |
| ضبط مخفی صدا/دوربین، نظارت مخفیانه | ممنوع |
| تفسیر خودکار حرکت به‌عنوان خطر | ممنوع |
| iOS / Wearable | خارج از MVP |
| Power Button به‌عنوان Trigger | ممنوع (بدون workaround غیررسمی) |
| AccessibilityService برای دور زدن محدودیت‌ها | ممنوع |
| FCM به‌عنوان کانال اصلی/تضمینی Emergency | ممنوع — فقط best-effort |
| API بدون پشتیبانی عمومی Android | ممنوع |

## 4. نمای کلی سیستم

```text
Flutter Mobile App (UI/Domain/Data)
        |
        | Pigeon (type-safe Platform Channel)
        v
Kotlin Android Native Layer
  ├── EmergencyLocationService (Foreground Service, type=location)
  ├── Location Pipeline + Offline Queue
  └── Native Emergency State
        |
        | HTTPS (REST /api/v1)
        v
Django REST API (Modular Monolith, ASGI)
   ├── accounts / devices / contacts
   ├── emergency (State Machine + Orchestrator)
   ├── locations
   └── notifications (Alert Providers)
        |
   +----+--------+
   |             |
   v             v
PostgreSQL     Redis (Channels layer, rate limit, state موقت — NOT source of truth)
                 |
                 v
              Django Channels (WebSocket)
                 |
                 v
              Trusted Contact Web UI (signed, expiring access)
```

 مسئولیت‌ها:

- **Flutter:** UI، Navigation، Authentication، Contacts، Emergency UI، Settings، Session history، Map، Server API integration.
- **Kotlin:** Foreground Location Service، Location collection، Local emergency queue، Android notifications، Android permissions، Native lifecycle/state، Hardware-trigger experiments (فقط Experimental).
- **Backend:** source of truth برای Session/State، State Machine enforcement، Idempotency، Authorization، Alert orchestration، Realtime broadcast.
- **Web:** نمایش وضعیت اضطراری برای Trusted Contact با access کوتاه‌عمر.

## 5. تصمیم‌های معماری ثبت‌شده

| ID | تصمیم | Rationale | جایگزین‌های ردشده | Impact |
|---|---|---|---|---|
| D-01 | **Monorepo و Modular Monolith** در Backend | نبود شواهد Scale برای سرویس‌های جدا؛ نگهداشت ساده‌تر؛ تراکنش‌های ACID بین emergency/locations/notifications | Microserviceهای جدا برای Location/Contacts/Emergency | ساختار `/mobile /backend /web /infra /docs`؛ مرزهای ماژول با service-layer و تست اثبات می‌شود |
| D-02 | **PostgreSQL = source of truth؛ Redis فقط ephemeral** | دوام داده اضطراری حیاتی است؛ Redis با restart/eviction از دست می‌رود | نگه‌داشتن session state در Redis | Redis فقط: Channels layer، rate limit، coordination کوتاه‌مدت |
| D-03 | **State Machine در Backend enforce می‌شود** | Client نباید arbitrary state تعیین کند؛ رقابت دو دستگاه/دو request باید کنترل شود | اعتماد به state اعلامی کلاینت | پیاده‌سازی: service layer + row lock + جدول transition مجاز + Event در همان تراکنش |
| D-04 | **Kotlin Native برای Location اضطراری** (Foreground Service، نه Flutter background timer) | قابلیت اطمینان در screen-off/Doze فقط با FGS واقعی ممکن است؛ Dart timer در process suspend قابل اعتماد نیست | geolocator plugin در background | پل Flutter↔Kotlin با Pigeon، strongly typed |
| D-05 | **شروع FGS فقط از foreground** (کاربر SOS را در اپ می‌زند) | از Android 12، شروع FGS از background با `ForegroundServiceStartNotAllowedException` مسدود است؛ exemption ها محدود و غیرقابل اتکا هستند | شروع خودکار Service از background/boot به‌عنوان مسیر اصلی | رفتار degraded برای reboot حین Session فعال به‌عنوان open question (Q-05) ثبت شد |
| D-06 | **درخواست نمی‌شود `ACCESS_BACKGROUND_LOCATION` در MVP** | چون SOS در foreground زده می‌شود و FGS با while-in-use permission کار می‌کند؛ سیاست Play برای background location سخت‌گیرانه است (declaration form + ویدیو + prominent disclosure) | درخواست "Allow all the time" | ساده‌سازی Permission UX و شانس تأیید Play؛ اگر در آینده نیاز شد، به‌عنوان تغییر معماری ثبت می‌شود |
| D-07 | **Auth = شماره موبایل + OTP** (توکن کوتاه‌عمر + refresh) | بازار ایران، هم‌خوان با مدل User/Device | ایمیل/رمز به‌عنوان identity اصلی | OTP Provider (درگاه پیامک ایرانی) یک open question است (Q-01)؛ تأیید نهایی کتابخانه در Phase 2 |
| D-08 | **Idempotency با `Idempotency-Key` + `client_uuid` برای هر LocationPoint** | retry و duplicate request نباید Session/Location/Alert تکراری بسازد؛ قطعی شبکه حین ارسال location رایج است | فقط dedupe بر اساس timestamp (نامطمئن، ساعت دستگاه قابل دستکاری) | جدول `idempotency_keys` و unique constraint روی `(session_id, client_uuid)` — مدل داده را ببینید |
| D-09 | **Alertها فقط از طریق interface `AlertProvider` + `AlertOrchestrator`** | جداسازی Emergency Domain از transport؛ تعویض‌پذیری provider؛ تست‌پذیری | فراخوانی مستقیم FCM/SMS از Domain | ساختار در بخش 6؛ اثبات با Unit/Integration Test |
| D-10 | **اطلاع‌رسانی به مخاطب در MVP: (1) اشتراک‌گذاری دستی لینک توسط کاربر — مسیر پیش‌فرض و بدون وابستگی؛ (2) SMS از طریق Gateway — best-effort؛ (3) FCM — optional و best-effort** | مسیر (1) به هیچ provider بیرونی وابسته نیست و قابل تضمین است؛ مسیرهای 2 و 3 تضمین تحویل ندارند و هرگز نباید `SENT == DELIVERED` فرض شود | اتکا به FCM به‌عنوان کانال اصلی اطلاع‌رسانی | UI باید وضعیت هر کانال را جدا و صادقانه نشان دهد (DeliveryAttempt tracking) |
| D-11 | **Safety Timer با دقت غیر-exact** (timer داخل FGS / alarm inexact) | `SCHEDULE_EXACT_ALARM` در Android 12+ محدود شده و برای اپ‌های alarm/clock محفوظ است؛ دقت ثانیه‌ای برای Safety Timer نیاز نیست | Exact Alarm برای countdown | انحراف قابل‌قبول timer مستند و در UI منعکس می‌شود |
| D-12 | **Versioned API `/api/v1/...` + DRF + Django 5.2 LTS + Channels ≥4.3** | Django 5.2 LTS تا ~آوریل 2028 پشتیبانی امنیتی دارد؛ Channels 4.3 سازگاری Django 5.2 را تعمیر کرده است | Django 6.x در شروع (سازگاری ecosystem/DRF هنوز باید تأیید شود) | pin دقیق نسخه‌ها در آغاز Phase 2 انجام و در `backend/requirements` ثبت می‌شود |
| D-13 | **Volume Sequence = Experimental، پیش‌فرض خاموش، پشت feature flag** | هیچ API عمومی برای دریافت رویداد volume خارج از foreground وجود ندارد؛ راه‌های موجود (AccessibilityService، MediaSession tricks) شکننده/ممنوع/OEM-dependent هستند | افزودن به Core MVP | PoC اجباری در Phase 1؛ در صورت PARTIAL/UNSUPPORTED از Core حذف می‌ماند |
| D-14 | **دسترسی Trusted Contact فقط با Signed Link کوتاه‌عمر + قابل revoke (بدون اکانت جداگانه در MVP)** | نصب/ثبت‌نام اپ دوم برای مخاطب بار بالایی دارد؛ الزام سند: بدون نیاز قطعی به اپ دوم | اکانت کامل برای مخاطبین | محدودیت ذاتی: لینک قابل forward است — در threat-model صادقانه ثبت شده؛ TTL کوتاه + revoke + عدم استفاده از URL دائمی |

## 6. معماری AlertProvider (غیرقابل مذاکره)

```text
EmergencySession
       |
       v
AlertOrchestrator        ← مخاطبان، channel، retry، timeout، escalation، provider failure، delivery tracking
       |
       v
AlertProvider (interface)
   ├── WebProvider            → ساخت/به‌روزرسانی access link + رکورد وضعیت (MVP)
   ├── SMSGatewayProvider     → ارسال SMS از طریق درگاه پیامک (best-effort، مشمول بررسی فنی/حقوقی)
   ├── FCMProvider            → best-effort فقط، جدا از Emergency Domain (optional)
   └── FutureProvider
```

Interface (معادل strongly-typed در کد):

```text
AlertProvider:
  sendEmergencyAlert(...)  -> AttemptRef
  getDeliveryStatus(...)   -> DeliveryStatus   # SENT != DELIVERED
  retry(...)
  cancel(...)
```

قواعد:

1. `EmergencySession` هیچ provider مشخصی نمی‌شناسد و هرگز SDK/transport نمی‌داند.
2. شکست یک provider به‌تنهایی false success تولید نمی‌کند و نباید Session را FAILED کند.
3. `SENT` هرگز معادل `DELIVERED` فرض نمی‌شود؛ `DeliveryAttempt` جدا ردیابی می‌شود.
4. معماری باید بدون هیچ provider بیرونی قابل اجرا و تست باشد (FakeProvider برای تست).

## 7. سیاست Trigger و Experimental Flags

- Core MVP: فقط `IN_APP_SOS`.
- `VOLUME_SEQUENCE`: Experimental — در code، docs و UI با برچسب Experimental؛ پیش‌فرض خاموش؛ فعال‌سازی فقط پس از گذراندن Device Validation Matrix کامل در Phase 1.
- `SAFETY_TIMER`: Trigger ثانویه؛ انقضای آن فقط یعنی «کاربر Safety را تأیید نکرده»، نه وقوع جرم — این تفکیک در Domain (trigger_type) و UI ثبت می‌شود.
- Trigger ها فقط Session موجود را می‌سازند/به‌روزرسانی می‌کنند؛ منطق مستقل ارسال هشدار ندارند.
- برای هر User فقط یک Session فعال (حالت‌های TRIGGERED/STARTING/ACTIVE/DEGRADED/RESOLVING) مجاز است؛ Trigger دوم فقط Event ثبت می‌کند.

## 8. سیاست FCM (ثابت)

1. `FCM Sent == Emergency Delivered` ممنوع. `FCM Available == Emergency Channel Available` ممنوع.
2. FCMProvider جدا از Emergency Domain و فقط best-effort است.
3. شکست FCM هرگز Session را FAILED و هرگز success کاذب تولید نمی‌کند.
4. FCM هرگز تنها کانال Emergency نیست.
5. سیستم بدون FCM باید کامل بیلد، اجرا و تست شود (CI بدون اعتبار FCM).

مستند رسمی، FCM را best-effort بدون تضمین تحویل توصیف می‌کند (تحویل متأثر از connectivity، throttling/quotas، battery optimization و TTL) — لینک‌ها در بخش 14.

## 9. معماری Mobile (Flutter + Kotlin)

لایه‌های Flutter:

```text
Presentation (Widgets)     ← بدون API call و بدون business logic اضطراری
Domain/Application         ← UseCase ها + State
Data                       ← Repository ها + API client + DTO ها
```

Repository های اصلی: `AuthRepository`، `ContactRepository`، `EmergencyRepository`، `LocationRepository`.

پل Flutter/Kotlin با **Pigeon** (کد تولیدی typed). API مفهومی:

```text
startEmergencyLocationService()
stopEmergencyLocationService()
getLocationServiceStatus()
startHardwareTriggerMonitoring()   // Experimental — volume trigger PoC
stopHardwareTriggerMonitoring()
getNativeEmergencyState()
```

Kotlin مسئول نگه‌داشتن native emergency state و local queue است؛ این قابلیت‌ها به Dart منتقل نمی‌شوند. minSdk پیشنهادی: **26 (Android 8.0)** — FGS از 26 معتبر است؛ تصمیم نهایی در Phase 1 (Q-04). targetSdk باید الزام سالانه Google Play (target API requirement) را برآورده کند.

## 10. Location و Permission Model

- جمع‌آوری موقعیت اضطراری فقط با **Kotlin Foreground Service با نوع `location`** انجام می‌شود.
- Android 14+: manifest باید `foregroundServiceType="location"` + `FOREGROUND_SERVICE_LOCATION` را declare کند و **قبل از start سرویس**، runtime permission موقعیت (while-in-use) باید گرفته شده باشد؛ در Play Console نیز declaration مربوط به FGS location لازم است.
- Android 13+: `POST_NOTIFICATIONS` runtime لازم است؛ بدون آن FGS notification نمایش داده نمی‌شود → جریان SOS باید این permission را قبل از فعال‌سازی درخواست/بررسی کند.
- شروع FGS از background در Android 12+ محدود است (D-05). مسیر MVP: کاربر اپ را باز کرده و SOS می‌زند → app در foreground است.
- `ACCESS_BACKGROUND_LOCATION` درخواست نمی‌شود (D-06).
- **LocationPolicy** یک Configuration Object است (نه magic constant) با حالت‌های: `emergency` / `normal` / `degraded` / `low_battery` — interval های MVP محافظه‌کارانه و configurable؛ اعداد نهایی فقط پس از اندازه‌گیری باتری در Phase 5 تعیین می‌شوند.
- وضعیت عملیاتی Location: `ACTIVE / DEGRADED / FAILED` — و Session طبق policy ترکیب می‌شود (failure-model.md).

## 11. Realtime

- Django Channels + Redis (layer) برای WebSocket سمت Trusted Contact.
- WebSocket جایگزین persistence نیست: **هر LocationPoint قبل از broadcast باید validate و persist شود**.
- گروه‌ها: `session.<id>` فقط اعضای مجاز (mخاطبین با link معتبر) subscribe می‌شوند؛ authorization در connect و در subscribe بررسی می‌شود.
- Reconnect: کلاینت پس از reconnect وضعیت کامل را از REST (source of truth) می‌گیرد؛ فرض «هیچ eventی از دست نرفته» ممنوع.

## 12. مرزهای ماژول‌های Backend

```text
backend/
  config/            # settings, asgi, urls
  accounts/          # User, OTP auth, tokens
  devices/           # Device registration
  contacts/          # TrustedContact CRUD
  emergency/         # EmergencySession, State Machine, Events, AlertOrchestrator
  locations/         # LocationPoint ingestion + validation
  notifications/     # AlertProvider interface + Web/SMS/FCM providers, DeliveryAttempt
  tests/
```

قاعده: وابستگی‌ها یک‌طرفه به سمت emergency هستند (emergency از notifications استفاده می‌کند، نه برعکس) و مرزها با تست معماری اثبات می‌شوند.

## 13. فرض‌ها (Assumptions) و سؤالات باز (Open Questions)

فرض‌ها (هر فرض باید در Phase مربوطه تأیید یا رد شود):

| ID | فرض |
|---|---|
| A-01 | کاربران هدف روی Android 8.0+ (minSdk 26) هستند. |
| A-02 | هویت = شماره موبایل نرمال‌شده E.164 (+98). |
| A-03 | یک کاربر می‌تواند چند Device ثبت کند اما Session در سطح User یکتا است (یکی فعال). |
| A-04 | در MVP یک region واحد برای Backend کافی است. |
| A-05 | تماس/پیامک مستقیم به سازمان‌های امدادی در MVP وجود ندارد. |
| A-06 | retention پیشنهادی برای LocationPoint و Events: پیش‌فرض 90 روز، configurable (نیاز به تأیید مالک — Q-03). |

سؤالات باز (قبل/حین Phase های مربوطه باید پاسخ داده شوند):

| ID | سؤال | Phase هدف |
|---|---|---|
| Q-01 | کدام درگاه OTP/پیامک ایرانی (Kavenegar و مشابه)؟ هزینه، deliverability، محدودیت‌ها؟ | 2 / 7 |
| Q-02 | Hosting داخل ایران یا خارج؟ تأثیر بر دسترسی به Google/Firebase (FCM در برخی شبکه‌های ایران ناپایدار است — این خود دلیل تقویت D-10 است)، latency، تحریم‌ها. | 2 / 11 |
| Q-03 | Retention دقیق داده موقعیت و Eventها؟ سیاست privacy نهایی؟ | 0-تأیید مالک |
| Q-04 | minSdk نهایی (26 پیشنهاد)؟ — targetSdk حل شد: **36** (الزام Play از 31 اوت 2026؛ مهلت گذشته) | 1 |
| Q-05 | بازیابی Session فعال پس از Reboot — **برای A21s/OneUI 4 پاسخ داده شد (2026-10-03): بازیابی خودکار وجود ندارد** (START_STICKY سرویس location را برنمی‌گرداند — compatibility-report §7 ردیف 16). طراحی: تشخیص توقف جریان location سمت backend + prompt ادامه Session در باز شدن اپ. سایر OEM ها: باید تکرار شود | 1 |
| Q-06 | حداکثر Device برای هر User و سیاست revocation دستگاه قدیمی؟ | 2 |
| Q-07 | مدت پیش‌فرض Safety Timer و آیا انقضای آن بدون اینترنت هم به صورت محلی Trigger می‌شود؟ (بله باید محلی باشد — طراحی در Phase 4/5) | 4 |
| Q-08 | زبان(های) UI (فارسی فقط یا + English)؟ | 4 |
| Q-09 | pin نهایی نسخه‌ها: Flutter stable، Pigeon، DRF، Channels، Postgres، Redis. | 1/2 |

## 14. برنامه بررسی مستندات رسمی + یافته‌های اولیه (PHASE 0)

| # | موضوع | منبع رسمی | یافته اولیه | وضعیت |
|---|---|---|---|---|
| 1 | FGS type در Android 14+ | [Foreground service types are required](https://developer.android.com/about/versions/14/changes/fgs-types-required)، [FG service types](https://developer.android.com/develop/background-work/services/fgs/service-types)، [Play declarations](https://support.google.com/googleplay/android-developer/answer/13392821) | برای `location`: manifest `FOREGROUND_SERVICE_LOCATION` + runtime location permission قبل از start + declaration در Play | ✔ تکمیل اولیه — enforce در Phase 5 |
| 2 | شروع FGS از background (Android 12+) | [Restrictions on bg-start](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)، [Launch a foreground service](https://developer.android.com/develop/background-work/services/fgs/launch) | `ForegroundServiceStartNotAllowedException`؛ exemption ها محدود؛ راه‌حل‌های جایگزین (WorkManager expedited، high-priority FCM) قابل اتکا برای اضطراری نیستند | ✔ → D-05 |
| 3 | Android 15 محدودیت BOOT_COMPLETED | [FGS type changes in 15](https://developer.android.com/about/versions/15/changes/foreground-service-types)، [Behavior changes 15](https://developer.android.com/about/versions/15/behavior-changes-15) | انواع dataSync/camera/mediaPlayback/phoneCall/mediaProjection از BOOT ممنوع؛ `location` در فهرست نیست ولی رفتار واقعی روی دستگاه validate می‌شود | ✔ → Q-05/PoC |
| 4 | سیاست Play برای background location | [Play policy](https://support.google.com/googleplay/android-developer/answer/9799150)، [Permissions declaration](https://support.google.com/googleplay/android-developer/answer/9214102)، [Request location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions) | declaration form + ویدیو + prominent disclosure + الزام core-feature بودن | ✔ → D-06 (درخواست نمی‌شود) |
| 5 | تضمین تحویل FCM | [Understand message delivery](https://firebase.google.com/docs/cloud-messaging/understand-delivery)، [Throttling & quotas](https://firebase.google.com/docs/cloud-messaging/throttling-and-quotas) | best-effort، بدون تضمین؛ متأثر از connectivity/throttle/battery | ✔ → بخش 8 |
| 6 | Volume Key خارج از foreground/screen-off | [SO: volume long-press screen off](https://stackoverflow.com/questions/76935040/how-to-detect-volume-button-long-press-in-the-background-while-the-screen-is-off)، [GeeksforGeeks: key events](https://www.geeksforgeeks.org/android/how-to-listen-for-volume-button-and-back-key-events-programmatically-in-android) | API عمومی برای رویداد کلید خارج از window focus وجود ندارد؛ راه‌های رایج: AccessibilityService (ممنوع نزد ما + محدودتر شونده توسط Google) و MediaSession (نیازمند playback فعال، شکننده، OEM-dependent مثل MIUI) | ✔ → D-13؛ PoC اجباری Phase 1 |
| 7 | Django/Channels سازگاری | [Django 5.2 release notes (LTS)](https://docs.djangoproject.com/en/6.1/releases/5.2/)، [Channels 4.3.0 notes](https://channels.readthedocs.io/en/latest/releases/4.3.0.html)، [channels PyPI](https://pypi.org/project/channels/) | Django 5.2 LTS (پشتیبانی ~3 سال)؛ Channels ≥4.3.0 سازگاری Django 5.2 | ✔ → D-12 |
| 8 | Notification permission (Android 13+) | مستندات runtime permissions Android | `POST_NOTIFICATIONS` runtime؛ بدون آن FGS notification دیده نمی‌شود | ✔ → بخش 10 |
| 9 | Android 16 (API 36) رفتارهای جدید | [Behavior changes: all apps](https://developer.android.com/about/versions/16/behavior-changes-all)، [Behavior changes: targeting 16](https://developer.android.com/about/versions/16/behavior-changes-16)، [Android 16 summary](https://developer.android.com/about/versions/16/summary) | JobScheduler quota enforcement حتی حین FGS فعال؛ سخت‌گیری بیشتر در FGS type؛ محدودیت‌های background activity launch. طراحی ما (FGS ساده type=location بدون اتکا به JobScheduler) اثر مستقیم ندارد ولی در Device Matrix Phase 1 دیده می‌شود | ✔ ثبت شد |
| 10 | الزام target API پلی‌استور | [Target API level requirements](https://support.google.com/googleplay/android-developer/answer/11926878) | از 31 اوت 2026 اپ/آپدیت جدید باید targetSdk 36 داشته باشد — تاریخ امروز از مهلت گذشته؛ **targetSdk=36 از روز اول** (android-36 روی این سیستم نصب است) | ✔ → Q-04 نیمه‌حل |

Deep-dive های باقی‌مانده (در Phase های مربوطه): OEM battery optimization matrix، WebSocket under Doze، SMS gateway legal/operational، Play FGS location declaration flow واقعی.

## 15. تصمیم نیازهای PoC

| بخش | PoC لازم؟ | کجا |
|---|---|---|
| Volume Sequence (screen off/lock/background/OEMها) | **بله — حیاتی**؛ انتظار واقع‌بینانه: PARTIAL یا UNSUPPORTED | Phase 1 |
| Kotlin FGS location روی دستگاه واقعی (screen off، battery saver، OEM ها) | **بله — حیاتی** | Phase 1 |
| Pigeon bridge (typed) | بله، کوچک | Phase 1 |
| Reboot recovery حین Session فعال (Q-05) | بله | Phase 1 |
| Django/Channels/Redis | خیر — stack استاندارد و شناخته‌شده؛ با Integration Test پوشش داده می‌شود | Phase 2/6 |
| OTP/SMS Gateway | PoC فنی نیست؛ بررسی عملیاتی/حقوقی لازم | قبل از نهایی‌سازی Phase 2 |
| FCM | خیر به‌عنوان PoC مسیر اصلی؛ فقط integration test شکست/نبود آن | Phase 7 |

## 16. فهرست API/قابلیت‌هایی که نباید بدون Validation فرض شوند

1. دریافت رویداد Volume Key در screen-off/lock/recent-apps-removed — **بدون API عمومی**؛ فقط Experimental.
2. Intercept کردن Power Button توسط اپ معمولی — فرض نمی‌شود؛ ممنوع.
3. شروع FGS از background/Doze به‌عنوان مسیر قابل اتکای اضطراری — ممنوع (D-05).
4. ACCESS_BACKGROUND_LOCATION — درخواست/فرض نمی‌شود (D-06).
5. `SCHEDULE_EXACT_ALARM`/ساعت دقیق — فرض نمی‌شود (D-11).
6. تضمین تحویل high-priority FCM روی OEM های چینی/battery saver — فرض نمی‌شود.
7. ارسال خودکار SMS بدون تعامل کاربر با `SEND_SMS` — بدون بررسی سیاست Play و حقوقی فرض نمی‌شود (Phase 7).
8. Auto-revoke مجوزهای بلااستفاده (Android 11+) — فرض می‌شود رخ می‌دهد؛ اپ باید هنگام باز شدن وضعیت permission ها را re-check کند.
9. زنده‌ماندن WebSocket در Doze — فرض نمی‌شود؛ reconnect+state sync الزامی.
10. هر رفتار OEM-specific (Xiaomi/Huawei/Samsung ددلاین‌های kill متفاوت) — فقط با Device Matrix معتبر می‌شود.

## 17. ریسک‌های اصلی

| ID | ریسک | شدت | احتمال | Mitigation | Owner/Next |
|---|---|---|---|---|---|
| R-01 | Volume Trigger در حالت‌های بحرانی (screen off/lock) کار نکند | بالا | بالا | Experimental ماندن؛ هرگز Core نشدن بدون Device Validation؛ حذف در صورت UNSUPPORTED | Phase 1 |
| R-02 | OEM battery optimization سرویس/Location را می‌کشد | بالا | بالا | درخواست exemption باتری + راهنمای کاربر + گزارش صادقانه DEGRADED + Device Matrix | Phase 1/5 |
| R-03 | نبود/ناپایداری درگاه SMS ایران برای OTP و alert | متوسط | متوسط | Web/manual share مسیر پیش‌فرض (D-10)؛ انتخاب gateway با تست واقعی | Q-01 |
| R-04 | رد شدن `POST_NOTIFICATIONS` توسط کاربر → FGS notification دیده نمی‌شود | متوسط | متوسط | درخواست در جریان SOS با توضیح پیامد؛ رفتار degraded مستند | Phase 4/5 |
| R-05 | شکست شروع FGS هنگام SOS (permission لغوشده و…) | بالا | متوسط | Policy صریح STARTING→FAILED/DEGRADED + UI راهنما + تست failure | Phase 5/9 |
| R-06 | Forward شدن signed link → افشای موقعیت | بالا | کم | TTL کوتاه، revoke، token با entropy بالا، rate limit؛ محدودیت ذاتی صادقانه مستند | Phase 8/10 |
| R-07 | Duplicate SOS/request تحت رقابت → Session/Location تکراری | بالا | متوسط | Idempotency + unique partial index + تست race | Phase 2/3 |
| R-08 | محدودیت‌های زیرساخت ایران برای Google/Firebase | متوسط | متوسط | FCM فقط optional؛ معماری بدون FCM تست‌پذیر؛ Q-02 | Phase 7/11 |

> **شواهد Phase 1 برای R-08 (2026-10-01):** `dl.google.com` (Google Maven) از شبکه توسعه مستقیم در دسترس نیست — بیلد AGP 9.0.1 شکست خورد. راه‌حل ثبت‌شده: آینه Aliyun Google-Maven به‌عنوان repository اول در `settings.gradle.kts` و `android/build.gradle.kts` (با comment دلیل). Maven Central مستقیم (کند اما) کار می‌کند؛ پراکسی محلی کاربر (127.0.0.1:2080) خاموش بود — گزینه دوم. جزئیات: `docs/compatibility-report.md` §2.1.

## 18. معیارهای پذیرش PHASE 0

- [x] تصمیم‌های اصلی مستند (بخش 5) با جایگزین‌های ردشده.
- [x] محدودیت‌های Android و dependency ها ثبت شده (بخش‌های 14 و 16).
- [x] State Machine مشخص (state-machine.md).
- [x] مدل داده مشخص (data-model.md).
- [x] API Contract قابل بررسی (api-contract.md).
- [x] Failure Model کامل (failure-model.md — 22 failure + policy).
- [x] Threat Model کامل (threat-model.md).
- [x] Testing Plan کامل (testing-plan.md).
- [x] FCM به‌عنوان Emergency transport تضمین‌شده تعریف **نشده**.
- [x] Volume Trigger به‌عنوان Experimental تعریف شده.
- [ ] تأیید صریح مالک محصول بر این مجموعه اسناد ← شرط خروج از STOP.
