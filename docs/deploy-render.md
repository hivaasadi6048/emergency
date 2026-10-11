# راهنمای دیپلوی سرور آزمایشی — GitHub + Render (رایگان)

هدف: سرور **همیشه‌آنلاین** تا گوشی مستقیم با 4G وصل شود؛ دیگر نه تونل USB، نه ترمینال باز.

> **صادقانه:** GitHub خودش هاست اجرایی نیست. GitHub فقط کد را نگه می‌دارد؛ سرور روی **Render.com** (پلن رایگان) اجرا می‌شود و هر بار push، خودکار آپدیت می‌شود. پلن رایگان بعد از ~۱۵ دقیقه بی‌فعالیتی می‌خوابد و اولین درخواست بعدی ~۳۰-۶۰ ثانیه طول می‌کشد (برای فاز آزمایش قابل قبول است).

---

## مرحله ۱ — ساخت ریپو در GitHub (۵ دقیقه)

1. با VPN به [github.com](https://github.com) بروید و لاگین کنید
2. دکمه سبز **New repository** (یا از `+` بالا-راست)
3. نام: `emergency` — Private — **بدون** README/gitignore (همه از قبل هست) → **Create repository**
4. در صفحه بعد، بخش **«…or push an existing repository from the command line»** را باز کنید؛ فقط دستورهای آن را کپی نکنید — آنها را در ترمینال `G:\Emergency` اجرا می‌کنیم (من دستور دقیق را پایین نوشته‌ام؛ فقط `YOUR_USERNAME` را عوض کنید):

```bash
cd G:\Emergency
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/emergency.git
git push -u origin main
```

نام کاربری GitHub خود را بگویید تا خودم این دستور را اجرا کنم (پسورد هم از Git Credential Manager ویندوز پرسیچ می‌شود، نه از من).

## مرحله ۲ — ساخت سرور در Render (۵ دقیقه)

1. با VPN به [render.com](https://render.com) بروید → **Get Started** → با اکانت GitHub ثبت‌نام کنید (تأیید می‌کند)
2. داشبورد → **New +** → **Web Service**
3. **Connect a repository** → ریپوی `emergency` را انتخاب کنید
4. تنظیمات (دقیقاً):

| فیلد | مقدار |
|---|---|
| Name | `emergency-api` |
| Region | Frankfurt (EU) — نزدیک‌ترین به ایران |
| Branch | `main` |
| Root Directory | **`backend`** |
| Runtime | **Python 3** |
| Build Command | `bash build.sh` |
| Start Command | `gunicorn config.wsgi:application --bind 0.0.0.0:$PORT` |

5. **Environment variables** (بخش Environment → Add Environment Variable) — چهار تا اضافه کنید:

| Key | Value |
|---|---|
| `DJANGO_SETTINGS_MODULE` | `config.settings.deploy` |
| `DJANGO_SECRET_KEY` | یک رشته تصادفی طولانی |
| `OTP_TEST_MODE` | `1` |
| `OTP_TEST_CODE` | یک کد ۶ رقمی دلخواه، مثلاً `123456` |

6. پایین صفحه **Create Web Service** → ~۳ دقیقه build می‌شود
7. بعد از Deploy Live شدن، بالا صفحه URL می‌دهد: `https://emergency-api.onrender.com`

## مرحله ۳ — دیتابیس PostgreSQL (۲ دقیقه)

1. داشبورد Render → **New +** → **PostgreSQL**
2. نام: `emergency-db` →_region Frankfurt_ → **Create Database** (رایگان)
3. داخل صفحه دیتابیس، **Connections** → گزینه **Web Service** → سرویس `emergency-api` را تیک بزنید (متغیر `DATABASE_URL` خودکار تزریق می‌شود)

## مرحله ۴ — تست و وصل‌کردن اپ

بعد از live شدن، این را از مرورگر/گوشی تست کنید (باید 401 برگرداند — یعنی زنده است):
```
https://emergency-api.onrender.com/api/v1/users/me
```

بعد در اپ (تنظیمات → آدرس Backend) همین URL را وارد کنید و لاگین با **کد ثابت آزمایشی** (مثلاً 123456). 

---

## نکات مهم

- **کد OTP ثابت فقط برای فاز آزمایش است** (چون هنوز درگاه پیامک نداریم — Q-01). قبل از کاربر واقعی، `OTP_TEST_MODE` را حذف می‌کنیم.
- اولین درخواست بعد از خواب ~۳۰-۶۰s طول می‌کشد (رایگان بودن) — طبیعی است.
- هر `git push` → دیپلوی خودکار.
- کل هزینه: **صفر** (هر دو پلن رایگان).
