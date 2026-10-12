#!/usr/bin/env bash
# GitHub Codespaces one-shot setup: PostgreSQL + Django + gunicorn on :8001
# Run INSIDE a Codespace terminal:  bash infra/codespace-setup.sh
# Then: Ports panel → port 8001 → Visibility: Public
set -e

echo "=== 1) PostgreSQL install/start (2-3 min) ==="
sudo apt-get update -qq
sudo apt-get install -y -qq postgresql postgresql-contrib > /dev/null
sudo service postgresql start || sudo service postgresql restart
sleep 2
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'emergency_dev_pw';" > /dev/null
sudo -u postgres createdb emergency 2>/dev/null || echo "(db already exists)"

echo "=== 2) python deps ==="
pip install -q -r backend/requirements.txt

echo "=== 3) environment (deploy settings) ==="
cd backend
export DJANGO_SETTINGS_MODULE=config.settings.deploy
export DJANGO_SECRET_KEY="${DJANGO_SECRET_KEY:-$(python -c 'import secrets; print(secrets.token_urlsafe(50))')}"
export DATABASE_URL="postgres://postgres:emergency_dev_pw@127.0.0.1:5432/emergency"
export OTP_TEST_MODE=1
export OTP_TEST_CODE="${OTP_TEST_CODE:-123456}"
# persist for future terminals in this codespace
printenv DJANGO_SECRET_KEY DATABASE_URL OTP_TEST_MODE OTP_TEST_CODE DJANGO_SETTINGS_MODULE > .env.codespace

echo "=== 4) migrate ==="
python manage.py migrate --noinput 2>&1 | tail -2

echo "=== 5) gunicorn on :8001 ==="
nohup gunicorn config.wsgi:application --bind 0.0.0.0:8001 > /tmp/gunicorn.log 2>&1 &
sleep 4
curl -s -o /dev/null -w "local check: HTTP %{http_code} (401 = alive)\n" --max-time 10 http://127.0.0.1:8001/api/v1/users/me

echo ""
echo "=============================================================="
echo " DONE. Three steps left (in the VS Code UI):"
echo "  1) Ports panel (bottom) → port 8001 → right-click →"
echo "     Port Visibility → Public"
echo "  2) Your backend URL:"
echo "     https://<CODESPACE-NAME>-8001.app.github.dev"
echo "     (the Ports panel shows the exact forwarded address)"
echo "  3) In the phone app: تنظیمات → آدرس Backend = همان URL"
echo "     Login OTP (test mode): $OTP_TEST_CODE"
echo "=============================================================="
