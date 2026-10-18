# PHASE REPORT — PHASE 5: Native Emergency Engine

- تاریخ: 2026-10-18
- Status: **IN_PROGRESS** (کد کامل؛ دو آیتم اعتبارسنجی باقی)

## 1. خروجی‌های این فاز (پیاده‌سازی‌شده)

| Feature | Status | Files | Notes |
|---|---|---|---|
| LocationPolicy (config object) | DONE | `LocationPolicy.kt` | interval/watchdog/queue caps یکجا — D-آرش §10 |
| PersistentPointQueue | DONE | `PersistentPointQueue.kt` | صف فایل‌پشتیبان JSONL، سقف ۲۰۰، survives process death |
| سرویس متصل به Policy + Queue | DONE | `EmergencyLocationService.kt` | initQueue از onCreate |
| پل آپلود موقعیت (C-014) | DONE | `lib/state/app_state.dart` | بافر native → بچ dedupe → POST /locations |
| گیت مجوز در جریان SOS (B-020) | DONE | همان | requestPermissions + انتظار + FAILED صادقانه |
| دیپلوی آزمایشی ابری | DONE→PARKED | `config/settings/deploy.py`, `build.sh`, `docs/deploy-render.md` | Render build سبز شد ولی **onrender.com از ایران DNS-poisoned** (تشخیص: 10.10.34.36 جعلی) → مسیر جایگزین: **GitHub Codespaces** (`app.github.dev` از ایران باز — 200 تأیید) + `infra/codespace-setup.sh` بدون sudo |

## 2. تست‌ها

| تست | Result |
|---|---|
| backend suite | **72/72 OK** |
| flutter analyze / test | **0 issue / 15/15** |
| E2E دستگاهی ورود+SOS+State Machine | ✓ (فاز 4، اثبات مجدد در فاز 5) |
| Resume Session باز پس از نصب مجدد | ✓ (b37c8a77) |
| صف پایدار در process death | ⏳ در انتظار تست دستگاهی |
| نمایش موقعیت indoor | ⏳ محیطی — دستگاه از بوت fix نگرفته؛ تست در فضای باز |

## 3. موانع محیطی حل‌شده/باز

| مانع | حل |
|---|---|
| onrender.com از ایران مسدود (DNS poisoning) | Render کنار گذاشته شد؛ Codespaces جایگزین شد (B-022) |
| ETXTBSY در wake شدن Codespace | اسکریپت: stop postgres قبل از re-extract |
| مرگ پردازه‌های لوکال با خاموشی/kill سشن | `start-servers.bat`/`stop-servers.bat` (اجرای کاربر پایدار است)؛ سرویس‌سازی با admin به Phase 11 |

## 4. باقی‌مانده فاز 5 (برای گزارش نهایی)
1. تست صف پایدار: SOS → آپلود نقاط → force-stop اپ → SOS مجدد → ادامه آپلود از صف.
2. تست موقعیت در فضای باز (نزدیک پنجره).
3. Pigeon فرمال (جایگزین پل موقت).
4. اندازه‌گیری باتری (ورودی LocationPolicy).

## 5. نتیجه
- Decision: **CONTINUE** (فاز 5 بسته نمی‌شود؛ دو اعتبارسنجی دستگاهی مانده)
- شرط ادامه: گوشی وصل + `start-servers.bat` اجرا شده (HTTP 401) + ترمینال Codespace بیدار
