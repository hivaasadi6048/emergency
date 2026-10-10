# Emergency — پلتفرم ایمنی شخصی و ارتباط اضطراری

سیستم ارتباط اضطراری شخصی و اشتراک‌گذاری موقعیت: فعال‌سازی Emergency Session، جمع‌آوری موقعیت با Native Foreground Service، و اطلاع‌رسانی به Trusted Contact ها از طریق AlertProvider های قابل تعویض.

**محصول تضمین نمی‌کند:** توقف جرم، نجات، تحویل پیام، یا دریافت موقعیت در تمام شرایط — سیستم وضعیت واقعی (از جمله DEGRADED/FAILED) را صادقانه گزارش می‌کند.

## ساختار مخزن

```text
G:\Emergency
├── docs/          ← اسناد معماری (وضعیت فعلی: PHASE 0)
├── mobile/        ← Flutter + Kotlin (خالی تا تأیید معماری)
├── backend/       ← Django Modular Monolith (خالی تا تأیید معماری)
├── web/           ← Trusted Contact Web View (خالی تا تأیید معماری)
└── infra/         ← docker/deployment (خالی)
```

## اسناد

| سند | موضوع |
|---|---|
| [architecture.md](docs/architecture.md) | تصمیم‌های معماری، فرض‌ها، سؤالات باز، ریسک‌ها، یافته‌های مستندات رسمی |
| [data-model.md](docs/data-model.md) | مدل داده، constraint ها، retention |
| [state-machine.md](docs/state-machine.md) | State ها، transition ها، enforcement |
| [api-contract.md](docs/api-contract.md) | قرارداد API v1 (پیش‌نویس) |
| [failure-model.md](docs/failure-model.md) | 22 failure، ماتریس وضعیت، Offline Queue |
| [threat-model.md](docs/threat-model.md) | STRIDE، سناریوها، ریسک‌های باقی‌مانده |
| [testing-plan.md](docs/testing-plan.md) | استراتژی تست، Device Matrix، Performance |
| [phase-0-report.md](docs/phase-0-report.md) | گزارش رسمی PHASE 0 |

## وضعیت Phase ها

| Phase | موضوع | وضعیت |
|---|---|---|
| 0 | Architecture Validation | **APPROVED** (2026-10-01 — پس از audit مالک) |
| 1 | Android PoC (FGS + Volume Trigger validation) | **IN PROGRESS** — ماتریس A21s کامل؛ کشف قطع پنهان OneUI + watchdog اثبات‌شده؛ باقی: سایر دستگاه‌ها |
| 2 | Backend Foundation | **DONE — PASS** (39/39 تست روی PostgreSQL 16 واقعی؛ phase-2-report.md) |
| 3 | Emergency Domain (State Machine + Idempotency) | **DONE — PASS** (71/71 تست؛ phase-3-report.md) |
| 4 | Flutter Application | **DONE — PASS_WITH_LIMITATIONS** (analyze 0، 15/15 تست، E2E دستگاهی ورود/SOS/State Machine ✓؛ phase-4-report.md) |
| 5 | Native Emergency Engine | شروع پس از تأیید مالک |
| 6 | Realtime (Channels/Redis) | - |
| 7 | Alert Providers | - |
| 8 | Trusted Contact Web App | - |
| 9 | Failure Testing | - |
| 10 | Security Hardening | - |
| 11 | Production Readiness | - |

## قواعد ثابت (خلاصه)

- FCM فقط best-effort و هرگز کانال اصلی Emergency نیست.
- Volume Trigger و Power Button: Experimental / ممنوع — تا Device Validation.
- State Machine فقط در Backend enforce می‌شود.
- Idempotency برای SOS/Location/Resolve/Alert الزامی است.
- `SENT ≠ DELIVERED`.
- git هنوز init نشده (پس از تأیید، در شروع Phase 1 راه‌اندازی می‌شود).
