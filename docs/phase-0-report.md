# PHASE REPORT — PHASE 0: Architecture Validation

- تاریخ: 2026-10-01
- محل پروژه: `G:\Emergency`
- Status: **PASS_WITH_LIMITATIONS**

## 1. هدف Phase
اعتبارسنجی معماری: بررسی الزامات فعلی Android/Flutter/Kotlin و Django/Channels/Redis و سیاست‌های Play و ماهیت FCM و امکان Volume Trigger؛ تولید اسناد معماری قابل بررسی — بدون implementation گسترده.

## 2. خروجی‌های مورد انتظار
- 7 سند معماری + README + گزارش این Phase
- فرض‌ها/سؤالات باز، برنامه بررسی مستندات، ریسک‌ها، معیار پذیرش، تصمیم PoC ها، فهرست قابلیت‌های «بدون Validation فرض‌نشده»

## 3. موارد پیاده‌سازی‌شده
| خروجی | Status | Files |
|---|---|---|
| اسکلت Monorepo | DONE | `README.md`, `.gitignore`, `mobile/.gitkeep`, `backend/.gitkeep`, `web/.gitkeep`, `infra/.gitkeep` |
| معماری + تصمیم‌ها (14 تصمیم D-01..D-14) | DONE | `docs/architecture.md` |
| مدل داده (+ افزوده‌های مستند: AccessLink, IdempotencyKey, client_uuid, source) | DONE | `docs/data-model.md` |
| State Machine (guard ها، enforcement، idempotency × state) | DONE | `docs/state-machine.md` |
| API Contract v1 پیش‌نویس | DONE | `docs/api-contract.md` |
| Failure Model (22 failure + ماتریس وضعیت + queue policy) | DONE | `docs/failure-model.md` |
| Threat Model (STRIDE، T-01..T-13) | DONE | `docs/threat-model.md` |
| Testing Plan (12 Integration سناریو، Device/Volume Matrix، Performance) | DONE | `docs/testing-plan.md` |

## 4. بررسی مستندات رسمی انجام‌شده (بررسی دسکتاپ، نه تست دستگاه)
| موضوع | یافته کلیدی | Result |
|---|---|---|
| FGS در Android 14+ | الزام `foregroundServiceType=location` + `FOREGROUND_SERVICE_LOCATION` + runtime permission قبل از start + declaration در Play | PASS (مستند) |
| شروع FGS از background (Android 12+) | مسدود با `ForegroundServiceStartNotAllowedException`؛ exemption ها محدود → FGS فقط از foreground | PASS (مستند) |
| Android 15 BOOT_COMPLETED | انواع dataSync/camera/mediaPlayback/… ممنوع؛ `location` در فهرست منع نیست اما validate دستگاه لازم | PARTIAL → PoC Phase 1 |
| Play policy background location | declaration form + ویدیو + prominent disclosure → در MVP درخواست نمی‌شود | PASS (تصمیم D-06) |
| FCM | best-effort بدون تضمین تحویل → فقط optional provider | PASS (مستند) |
| Volume Key خارج از foreground | API عمومی وجود ندارد؛ راه‌ها AccessibilityService/MediaSession (ممنوع/شکننده/OEM-dependent) | PARTIAL → PoC اجباری Phase 1 |
| Django 5.2 LTS + Channels ≥4.3 | سازگاری تأییدشده؛ LTS ~تا آوریل 2028 | PASS (مستند) |

## 5. محدودیت‌ها و رفتار Degraded (خلاصه)
- Volume Trigger در screen-off/lock احتمالاً PARTIAL/UNSUPPORTED است — Experimental باقی می‌ماند.
- Recovery خودکار پس از reboot حین Session فعال: نامشخص → Q-05/PoC.
- Forward شدن Access Link: محدودیت ذاتی، فقط با TTL/revoke کاهش می‌یابد.

## 6. تصمیم‌های معماری
14 تصمیم (D-01..D-14) با Rationale و جایگزین ردشده در `architecture.md` بخش 5. مهم‌ترین‌ها: Modular Monolith، FGS فقط از foreground، عدم درخواست ACCESS_BACKGROUND_LOCATION، اطلاع‌رسانی مخاطب با manual-share پیش‌فرض، Idempotency با client_uuid، State Machine فقط backend.

## 7. فایل‌های تغییرکرده
- Added: `README.md`, `.gitignore`, `docs/architecture.md`, `docs/data-model.md`, `docs/state-machine.md`, `docs/api-contract.md`, `docs/failure-model.md`, `docs/threat-model.md`, `docs/testing-plan.md`, `docs/phase-0-report.md`, `.gitkeep` × 4
- Modified: — | Deleted: —

## 8. ریسک‌های باقی‌مانده
R-01..R-08 در `architecture.md` بخش 17 (بالاترین: R-01 Volume Trigger، R-02 OEM battery optimization).

## 9. نتیجه توقف یا ادامه
- **Decision: STOP** (الزام معیار توقف Phase 0)
- Reason: معماری باید پیش از implementation توسط مالک تأیید شود.
- Required approval: تأیید مجموعه اسناد + پاسخ به Q-01..Q-09 (به‌ویژه Q-02 hosting و Q-03 retention) یا پذیرش پیش‌فرض‌های ثبت‌شده.

## 10. Phase بعدی
پس از تأیید: **PHASE 1 — Android PoC** (Kotlin FGS Location، Permission Flow، Screen Off/Background/Battery Saver، Pigeon Bridge، ماتریس کامل Volume Trigger) روی دستگاه واقعی.

---

## ضمیمه (2026-10-01 — پس از ارائه گزارش)

1. **تأیید معماری:** مالک محصول تأیید شرطی داد («اگر همه موارد اوکی است وارد فاز 1 شویم»). Audit تک‌تک اقدامات (1-6)، اسناد (7) و معیارهای پذیرش (11 بند) Phase 0 انجام شد — بدون مورد باقی‌مانده. → تأیید معماری ثبت و وارد **PHASE 1** شدیم.
2. **تکمیلی «الزامات فعلی Android»** (به architecture.md §14 ردیف 9-10 اضافه شد): رفتارهای Android 16 (API 36) و الزام targetSdk=36 پلی‌استور از 31 اوت 2026 (مهلت گذشته → از روز اول 36).
3. **وضعیت ابزار Phase 1:** Flutter 3.44.9 ✓، Dart 3.12.2 ✓، android-36 + build-tools ✓، JDK 21 (Android Studio JBR) ✓ — گوشی فیزیکی متصل نیست؛ Device Matrix بدون دستگاه واقعی قابل تکمیل نیست (الزام سند: Emulator کافی نیست).
