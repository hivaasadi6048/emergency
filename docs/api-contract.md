# API Contract (v1) — پیش‌نویس PHASE 0

- **سند:** `api-contract.md`
- **نسخه:** 0.1 (Draft — PHASE 0) — قرارداد نهایی باید پس از تأیید معماری و در پایان Phase 2/3 با مدل واقعی هم‌راستا شود
- **تاریخ:** 2026-10-01

---

## 1. قواعد عمومی

- Base path versioned: `/api/v1/...`. تغییرات breaking فقط با نسخه جدید.
- فرمت زمان: ISO-8601 UTC.
- Auth: `Authorization: Bearer <access token>` (کوتاه‌عمر) + refresh token. جزئیات نهایی در Phase 2 (D-07).
- Header idempotency: `Idempotency-Key: <UUID>` — **الزامی** برای: ایجاد Session، Upload Location، Resolve، ایجاد Alert. تکرار همان key همان پاسخ قبلی را با هدر `Idempotency-Replayed: true` برمی‌گرداند؛ استفاده از key یکسان با body متفاوت → `409 IDEMPOTENCY_KEY_REUSED`.
- Rate limiting فعال است؛ پاسخ `429` با هدرهای استاندارد retry.
- هر پاسخ خطا ساختار ثابت دارد:

```json
{ "error": { "code": "MACHINE_READABLE_CODE", "message": "...", "details": {} } }
```

کدهای اصلی: `VALIDATION_ERROR`, `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT_INVALID_TRANSITION`, `CONFLICT_ACTIVE_SESSION`, `IDEMPOTENCY_KEY_REUSED`, `RATE_LIMITED`, `NO_ACTIVE_SESSION`, `INTERNAL_ERROR`.

## 2. Endpoint ها

### Auth
```text
POST /api/v1/auth/request-otp     { phone }              → 204 (همیشه؛ بدون افشای وجود شماره)
POST /api/v1/auth/verify-otp      { phone, code, device_info } → { access, refresh, user, device }
POST /api/v1/auth/refresh         { refresh }            → { access, refresh }
POST /api/v1/auth/logout          { refresh }            → 204
```

### Users / Devices
```text
GET   /api/v1/users/me                        → User
PATCH /api/v1/users/me          { display_name }
POST  /api/v1/devices                          → Device   (register/update)
GET   /api/v1/devices                          → [Device]
```

### Contacts
```text
GET    /api/v1/contacts                        → [TrustedContact]
POST   /api/v1/contacts         { name, phone, relationship?, priority? }
PATCH  /api/v1/contacts/{id}
DELETE /api/v1/contacts/{id}                   → 204
```

### Emergency
```text
POST /api/v1/emergency/sessions
     Idempotency-Key الزامی
     { trigger_type: IN_APP_SOS | SAFETY_TIMER }
     → 201 { session } | 200 { session } با Idempotency-Replayed
     خطاها: 409 CONFLICT_ACTIVE_SESSION (Session فعال موجود — پاسخ شامل Session موجود)

GET  /api/v1/emergency/sessions/{id}            → { session, latest_location, capability_status }
GET  /api/v1/emergency/sessions                 → تاریخچه (صفحه‌بندی ساده)
GET  /api/v1/emergency/sessions/{id}/events     → [EmergencyEvent] (timeline)

POST /api/v1/emergency/sessions/{id}/resolve
     Idempotency-Key الزامی  → 202 { session(status=RESOLVING) } تا 200 { session(RESOLVED) }

POST /api/v1/emergency/sessions/{id}/cancel
     Idempotency-Key الزامی  → 200 { session(CANCELLED) }
     فقط در TRIGGERED مجاز؛ در غیر این صورت 409 CONFLICT_INVALID_TRANSITION

POST /api/v1/emergency/sessions/{id}/capability        [افزوده Phase 3 — C-010]
     { location_capability: ACTIVE|DEGRADED|FAILED, network_ok: bool }
     → 200 { session }  (backend طبق ماتریس failure-model وضعیت را می‌سازد؛ کلاینت هرگز status مستقیم نمی‌فرستد)
     فقط در STARTING/ACTIVE/DEGRADED پذیرفته می‌شود؛ 409 CONFLICT_INVALID_TRANSITION در بقیه
```

### Locations
```text
POST /api/v1/locations
     Idempotency-Key الزامی (یک key per batch)
     { session_id, points: [ { client_uuid, latitude, longitude, accuracy_m?, altitude_m?,
                               speed_mps?, heading_deg?, captured_at, source } ] }
     → 202 { accepted: [client_uuid...], duplicates: [client_uuid...] }
```
- dedupe با `(session_id, client_uuid)` — تکرار خطا نمی‌دهد، فقط `duplicates` گزارش می‌شود.
- هر point جدا validate می‌شود؛ رکوردهای نامعتبر با کد و دلیل در پاسخ برمی‌گردند (reject نیمه‌بچ بدون سکوت).

### Access Links (مدیریت توسط کاربر)
```text
POST /api/v1/emergency/sessions/{id}/access-links     → { url, expires_at }  (token خام فقط یک‌بار)
DELETE /api/v1/emergency/sessions/{id}/access-links/{link_id}  → 204 (revoke)
```

### Web Viewer (public با signed token)
```text
GET  /w/{token}                       → صفحه Web View (بدون نیاز به اکانت)
GET  /api/v1/view/{token}/state       → { session_summary: {status, started_at, elapsed},
                                          last_location: {lat,lng,accuracy_m,captured_at},
                                          connection: LIVE | STALE, expires_at }
WS   /ws/view/{token}/                → رویدادهای زنده session.update / location.new
```
token: حداقل 128-bit entropy، hash‌شده ذخیره می‌شود، TTL کوتاه، قابل revoke؛ URL دائمی/عمومی نیست.

## 3. WebSocket (Trusted Contact) — قواعد

1. authorization هنگام connect و در subscribe (token ↔ session) بررسی می‌شود.
2. هر Location قبل از broadcast **persist** شده است؛ پیام WS فقط notify است.
3. Reconnect: کلاینت موظف است پس از reconnect وضعیت کامل را از `GET /api/v1/view/{token}/state` بگیرد؛ «هیچ eventی از دست نرفته» هرگز فرض نمی‌شود.
4. پیام‌ها:
```json
{ "type": "location.new", "data": { "latitude": 35.7, "longitude": 51.4, "accuracy_m": 12, "captured_at": "..." } }
{ "type": "session.update", "data": { "status": "DEGRADED", "reason": "NETWORK_LOST" } }
```

## 4. object-level Authorization (قاعده ثابت)

- هر endpoint که به session/location/event/link دسترسی می‌دهد باید ownership را بررسی کند:
  مالک Session = کاربر توکن؛ مخاطب = فقط با link معتبر و فقط همان Session.
- هیچ Trusted Contact یا کاربر دیگری نمی‌تواند location کاربر دیگر را query کند (تست اختصاصی در Phase 3/10).

## 5. موارد باز برای تکمیل قرارداد (در Phase 2/3)

- ساختار دقیق توکن‌ها (claim ها، مدت، rotation).
- صفحه‌بندی و فیلترهای تاریخچه Session.
- ساختار کامل خطاهای validation هر فیلد.
- نسخه‌بندی deprecation policy رسمی.
