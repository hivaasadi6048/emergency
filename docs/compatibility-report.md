# Compatibility Report — PHASE 1 (قالب + روش تست)

- **سند:** `compatibility-report.md`
- **نسخه:** 0.1 (قالب — پر کردن آن فقط با دستگاه واقعی)
- **قاعده قطعی:** هیچ ردیفی بدون اجرای واقعی پر نمی‌شود. هیچ نتیجه‌ای فقط بر اساس Emulator پذیرفته نیست.

---

## 1. فرمت ردیف (طبق سند نیازمندی)

```text
Feature | Device | OEM | Android Version | App Version | Battery State | Permission State |
Network State | Test | Result (PASS/FAIL/PARTIAL/UNSUPPORTED) | Notes | Evidence
```

Evidence معتبر: `adb logcat` مرتبط، screen recording، عکس تنظیمات، خروجی اپ.

## 2. ساخت PoC و نصب

```bash
cd G:\Emergency\mobile
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

اپ: «Emergency PoC» — سه بخش: مجوزها، ردیابی FGS، Volume Sequence (EXPERIMENTAL).

### 2.1 شناخته‌های محیط build این سیستم (2026-10-01)

| موضوع | یافته | اقدام |
|---|---|---|
| `dl.google.com` (Google Maven) | مستقیم مسدود (timeout تکراری — AGP 9.0.1 resolve نشد؛ اولین بیلد FAIL شد) | آینه Aliyun Google-Maven به‌صورت repository اول در `settings.gradle.kts` و `android/build.gradle.kts` — با comment دلیل؛ `google()`/`mavenCentral()` به‌عنوان fallback مانده‌اند |
| Maven Central (`repo.maven.apache.org`) | مستقیم کار می‌کند اما کند (~5s) | بدون تغییر |
| `download.flutter.io` (artifact های engine) | **رفتار متناوب** — همان artifact یک بار HTTP 200 و یک بار **403 Forbidden** (تحریم GCS)؛ بیلد دوم روی 403 شکست خورد | `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` — آینه رسمی Flutter (مستند «Using Flutter in China») — در سطح user با `setx` ثبت شد و در هر build نیز inline پاس می‌شود. مکانیزم رسمی است، نه hack: کد افزونه (`FlutterPlugin.kt:92`, `resolve_dependencies.gradle.kts:17`) این env را می‌خواند |
| `maven.aliyun.com` (آینه Google Maven) | AGP 9.0.1 + AndroidX (core-ktx 1.12/1.15، annotation، lifecycle) همه HTTP 200 — بیلد سوم از این آینه resolve شد | در `settings.gradle.kts` و `android/build.gradle.kts` به‌عنوان repository اول با comment دلیل |
| Supply-chain note | artifact های engine از آینه جامعه (flutter-io.cn توسط CFUG) می‌آیند | برای CI/Production بعداً مقایسه hash یا استفاده از منبع رسمی در دسترس‌پذیر — ثبت به‌عنوان follow-up |
| پراکسی محلی کاربر | در رجیستری `127.0.0.1:2080` تنظیم شده ولی غیرفعال/خاموش | گزینه دوم اگر آینه کافی نباشد؛ در `~/.gradle/gradle.properties` با `systemProp` تنظیم می‌شود |
| JDK | روی PATH فقط Java 8 است (برای AGP کافی نیست) | `flutter config --jdk-dir` به JBR اندروید استودیو (OpenJDK 21) تنظیم شد |
| targetSdk/compileSdk | android-36 نصب است؛ الزام Play از 31 اوت 2026 | 36/36 تنظیم شد؛ minSdk 26 |

کلاسیفیکیشن شکست اولین بیلد: **Environment Problem** (نه Implementation Bug) — نتیجه تست دستگاهی قبل از رفع محیطی معتبر نیست.

### 2.2 شواهد بیلد (2026-10-01)

| # | Build | Command | Result | Evidence |
|---|---|---|---|---|
| 1 | اولین | `flutter build apk --debug` | **FAIL** — AGP 9.0.1 resolve نشد (dl.google.com unreachable) | log: «Plugin [id: 'com.android.application', version: '9.0.1'] was not found» — 24.9s |
| 2 | با آینه Aliyun | همان + آینه‌ها در gradle | **FAIL** — AGP/AndroidX حل شد ولی `io.flutter:x86_64_debug` از storage.googleapis.com → **403 Forbidden** (تحریم GCS، رفتار متناوب) | log — 217.6s |
| 3 | با آینه Flutter | `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn flutter build apk --debug` | **FAIL** — همه وابستگی‌ها حل شد؛ فقط 1 خطای کامپایل Kotlin در کد PoC (Location.getProvider() در compileSdk 36 nullable) | log — 593.9s؛ fix: null-safe در EmergencyLocationService.kt |
| 4 | نهایی | همان #3 بعد از fix | **PASS** — `√ Built build\app\outputs\flutter-apk\app-debug.apk` | APK: 140MB (debug, all ABIs)؛ badging: `package=com.emergency.app.emergency_poc, minSdk 26, targetSdk 36, compileSdk 36` — 61.3s |

**هشدار صادقانه:** بیلد موفق فقط یعنی کد compile می‌شود — به هیچ وجه معیار صحت رفتار (FGS، باتری، screen off، Volume Trigger) نیست. آن معیار فقط ماتریس دستگاه واقعی بخش 3-5 است.

**دستور نصب روی دستگاه:**
```bash
"C:\Users\ZHIRO\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r build\app\outputs\flutter-apk\app-debug.apk
```

---

## 7. نتایج Device Matrix — Samsung Galaxy A21s (SM-A217F)

```text
Device: SM-A217F | OEM: Samsung | OneUI 4.0 / Android 12 (SDK 31) | App: 1.0.0-debug (targetSdk 36)
Battery: 70-80% (USB) | Permissions: FINE+COARSE granted (USER_SET) | Network: 4G
Dates: 2026-10-01 / 2026-10-03 | Evidence: docs/evidence/*.png + logcat
```

| # | Test | Result | Notes | Evidence |
|---|---|---|---|---|
| 1 | نصب (adb install) | PASS | Streamed Install → Success | log |
| 2 | اجرا و UI | PASS | بخش‌های مجوزها/FGS/Volume به‌درستی رندر شدند | `poc_t1_launch.png` |
| 3 | Permission Flow واقعی | PASS | دیالوگ سیستم → `granted=true, flags=[USER_SET]`؛ آیکون موقعیت در status bar | dumpsys package |
| 4 | شروع FGS از foreground | PASS | `isForeground=true, startForegroundCount=1, uidState: TOP, targetSdkVersion:36` — دقیقاً مطابق D-05 | dumpsys activity services |
| 5 | FGS Notification | PASS | `NotificationRecord id=42 channel=emergency_poc_fgs importance=2` | dumpsys notification |
| 6 | جمع‌آوری در screen-on | PASS | interval واقعی ~9-10s، GPS+Network، همگرایی دقت 45m→7m، `captured_at` صحیح | `poc_t1_dialog.png` |
| 7 | Background (HOME، 90s، USB) | PASS | سرویس زنده (`isForeground=true`)، نقاط ادامه یافتند | `poc_t3_background.png` |
| 8 | Screen-off ۲ دقیقه (USB) | **PARTIAL** | تحویل ادامه یافت ولی throttle: 10s → 30-37s؛ بعد از wake بازگشت به 10s | `poc_tb_screenoff.png` |
| 9 | Screen-off + ناپایداری USB (روز ۱) | **FAIL** | قطع کامل silent ~۶ دقیقه؛ سیستم GNSS فعال بود، اپ هیچ fix ای نگرفت و همچنان ACTIVE نمایش می‌داد؛ فقط با stop/start سرویس بازیابی شد | `poc_t3c_restart.png` |
| 10 | Screen-off/قفل امن ۳ دقیقه (روز ۲، با watchdog) | **FAIL → MITIGATED** | stall در 55s شناسایی شد → DEGRADED صادقانه + re-request → تحویل حین قفل از سر گرفته شد (نقاط 14:17:26→14:19:34) → بازگشت به ACTIVE؛ شمارنده بازیابی‌ها در UI: 2 (تا پایان جلسه: 4) | logcat `LOCATION_DELIVERY_STALL` + `poc_r2_result.png` |
| 11 | معافیت باتری (deviceidle whitelist) | **INSUFFICIENT** | شبیه‌سازی «Unrestricted»: سیستم GNSS را خاموش نکرد ولی جلوی suspension سطح اپ را هم نگرفت؛ راه‌حل مؤثر: watchdog re-request | dumpsys deviceidle |
| 12 | Volume Trigger — foreground (تزریق keyevent) | **PASS** | `VOL_MONITOR_ARMED` → 5×VOL_PRESS در 1.8s → `VOL_SEQ_DETECTED`؛ شمارنده UI: 1. کلیدها consume نمی‌شوند (volume HUD فعال می‌ماند — رفتار صادقانه). نکته اجرایی: ارسال ۵ keyevent باید در یک shell باشد (round-trip های جدا از پنجره 3s بیرون می‌زنند) | logcat PocVol + `poc_td3.png` |
| 13 | Volume Trigger — screen off | **UNSUPPORTED** | با صفحه خاموش، هیچ رویداد volume به اپ نمی‌رسد (logcat کاملاً خالی) — بدون API عمومی، بدون workaround (AccessibilityService ممنوع D-13). تأیید ماندن در Experimental | logcat خالی + روش تست §4 |
| 14 | Revoke FINE location حین اجرای FGS | **FAIL (سیستم) — رفتار صادقانه اپ** | سیستم **سرویس FGS را فوراً stop کرد** (ServiceRecord حذف، حتی یک log هم از اپ باقی نماند — فرصت واکنش به watchdog نبود). پیامد معماری: تشخیص این failure سمت اپ ممکن نیست؛ باید در backend (توقف جریان location) و در باز شدن بعدی اپ صادقانه اعلام شود | dumpsys services (0 record) + `granted=false` |
| 15 | Launch اکتیویتی از adb وقتی دستگاه قفل است | BLOCKED توسط سیستم | `am start` در حالت keyguard امن بی‌اثر — تأیید جانبی محدودیت background-start (D-05) | `poc_tf_relaunch.png` |
| 16 | Reboot با Session فعال (Q-05) | **FAIL — بازیابی خودکار وجود ندارد** | `adb reboot` با سرویس ACTIVE؛ +30s و +2.5min پس از boot: **0 ServiceRecord**؛ پروسه بعد از ~۲دقیقه بدون سرویس spawn شد؛ START_STICKY سرویس location را روی OneUI 4 برنمی‌گرداند. ← طراحی: تشخیص توقف جریان location در backend + prompt «ادامه Session» در باز شدن بعدی اپ | dumpsys + pidof قبل/بعد |
| 17 | Location Services خاموش | **PASS (رفتار صادقانه)** | `location_mode=0` → start سرویس → **DEGRADED** + `LOCATION_SERVICES_OFF` + دیالوگ سیستمی «No location access»؛ پس از روشن‌کردن + restart → بازگشت به **ACTIVE** با نقاط GPS | `poc_tg_locoff/degraded/recovered.png` |

### 7.1 یافته معماری از ماتریس (ورودی Phase 5/9)

1. **OneUI به‌صورت silent، تحویل fix ها را از اپِ while-in-use+FGS قطع می‌کند** (screen-off/قفل؛ حتی با battery exemption) در حالی که:
   - درخواست listener هنوز ثبت است (`ProviderRequest[@+10s, HIGH_ACCURACY, WorkSource{app}]`)
   - GNSS سطح سیستم فعال و در حال تولید fix است (عمر fix: 0.8s در حین قفل)
   - هیچ خطایی به اپ گزارش نمی‌شود و وضعیت اپ بدون watchdog، به‌اشتباه ACTIVE می‌ماند.
2. **Watchdog تازگی موقعیت** (پیاده‌سازی شد و اعتبارسازی شد): اگر >45s (4.5×interval) fix نیامد → `serviceState=DEGRADED` + `lastError=LOCATION_DELIVERY_STALL` + re-request با API عمومی → بازیابی تأیید شد (logcat + نقاط حین قفل). این باید در Phase 5 به‌صورت `LocationPolicy` قابل‌config درآید و در Phase 9 تست failure شود.
3. **Revoke مجوز حین اجرا:** سیستم FGS را فوراً stop می‌کند و به اپ فرصت واکنش نمی‌دهد → تشخیص این failure فقط سمت backend (توقف جریان location) و در باز شدن بعدی اپ ممکن است.
4. **Reboot (Q-05):** بازیابی خودکار سرویس location روی OneUI 4 رخ نمی‌دهد (START_STICKY کافی نیست).
5. **Q-10 (سؤال باز جدید):** آیا `ACCESS_BACKGROUND_LOCATION` (Allow all the time) suspension را کلاً حذف می‌کند؟ تضاد بالقوه با D-06 (سیاست Play) — تصمیم بعداً با بررسی فنی/حقوقی.
6. نتایج فوق فقط برای A21s/OneUI 4 است — تعمیم به Pixel/Xiaomi نیازمند تکرار ماتریس است (هیچ OEM-specific behavior ای تعمیم داده نشود).

## 3. شرایط استاندارد تست (هر یک روی هر دستگاه)

| شرط | روش ایجاد |
|---|---|
| foreground / screen on | اپ باز، صفحه روشن |
| background | دکمه Home؛ سرویس باید ادامه دهد؛ نقاط باید ادامه یابند |
| screen off | دکمه پاور؛ پس از ۵ دقیقه باز کنید و نقاط فاصله‌دار را بررسی کنید |
| lock screen | قفل گذاشتن؛ بررسی ادامه نقاط |
| removed from recents | swipe کردن اپ از recent apps؛ سرویس FGS نباید بمیرد (OEM-dependent — ثبت دقیق) |
| battery saver | فعال‌کردن Battery Sader از Settings، تکرار تست background/screen off |
| reboot | ری‌استارت با Session «فعال» (سرویس در حال اجرا) → رفتار پس از بوت (Q-05) |
| Location Services خاموش | Settings → Location off → انتظار: DEGRADED با خطای LOCATION_SERVICES_OFF |
| Permission revoke | حین سرویس فعال، مجوز Location را لغو کنید → رفتار باید صادقانه FAILED/DEGRADED شود |
| network off | Airplane mode → سرویس محلی ادامه می‌دهد (PoC بدون backend)؛ ثبت وضعیت |

## 4. ماتریس Volume Trigger (EXPERIMENTAL — D-13)

۵ فشردن سریع ولوم در پنجره ۳ ثانیه. برای هر دستگاه × هر شرط:

| شرط | انتظار اولیه (بر اساس بررسی مستندات) | Result |
|---|---|---|
| foreground + screen on | PASS (probe کار می‌کند) | PENDING |
| foreground + screen off | نامشخص — event های کلید ممکن است نرسد | PENDING |
| background (Home) | انتظار: UNSUPPORTED (window focus ندارد) | PENDING |
| lock screen | انتظار: UNSUPPORTED | PENDING |
| removed from recents | انتظار: UNSUPPORTED | PENDING |
| battery saver | نامشخص | PENDING |
| reboot | انتظار: UNSUPPORTED (monitoring state از بین می‌رود) | PENDING |

قواعد تصمیم: اگر FAIL/PARTIAL/UNSUPPORTED → Volume Trigger از Core خارج می‌ماند (Experimental، فقط دستگاه‌های PASS، یا حذف). هیچ workaround شکننده‌ای (AccessibilityService/MediaSession hack) مجاز نیست.

## 5. انتظارات FGS (طبق معماری — نتیجه هر کدام باید با کد match شود)

- بدون `ACCESS_FINE_LOCATION` → start باید با `PERMISSION_REQUIRED` رد شود (policy STARTING→FAILED).
- Android 13+ بدون `POST_NOTIFICATIONS` → رفتار نمایش notification مستند شود.
- Location Services خاموش → وضعیت DEGRADED + خطای `LOCATION_SERVICES_OFF`.
- فقط GPS خاموش / فقط Network خاموش → DEGRADED.
- interval واقعی نقاط ~10s (LocationPolicy پوک) — فاصله واقعی در log ثبت شود.

## 6. دستگاه‌های هدف (پیشنهادی — تکمیل توسط مالک)

- یک Xiaomi/Redmi (MIUI/HyperOS) — بدترین OEM از نظر battery kill
- یک Samsung (OneUI)
- یک Pixel (استوک)
- یک میان‌رده رایج ایران

هر دستگاه: شماره ردیف + Model + OEM + Android Version + نتیجه هر تست بالا + Evidence.
