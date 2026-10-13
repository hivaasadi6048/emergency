#!/usr/bin/env bash
# GitHub Codespaces one-shot setup — ZERO SUDO version.
# Portable PostgreSQL binaries (Maven Central) + Django + gunicorn on :8001
# Run INSIDE a Codespace terminal:  git pull && bash infra/codespace-setup.sh
# Then: Ports panel → port 8001 → Visibility: Public
set -e

ROOT="$(pwd)"
PGROOT="$ROOT/.localdb"
PGPORT=5433   # 5432 may be taken by the system postgres service

echo "=== 1) download portable postgres binaries (linux-amd64) ==="
mkdir -p "$PGROOT"
JAR="$PGROOT/pg.jar"
if [ ! -f "$JAR" ]; then
  curl -sL --max-time 300 -o "$JAR" \
    "https://repo1.maven.org/maven2/io/zonky/test/postgres/embedded-postgres-binaries-linux-amd64/16.4.0/embedded-postgres-binaries-linux-amd64-16.4.0.jar" \
  || curl -sL --max-time 300 -o "$JAR" \
    "https://repo.maven.apache.org/maven2/io/zonky/test/postgres/embedded-postgres-binaries-linux-amd64/16.2.0/embedded-postgres-binaries-linux-amd64-16.2.0.jar"
fi
ls -lh "$JAR"

echo "=== 2) stop leftover postgres (codespace wake keeps it alive → ETXTBSY) ==="
if [ -f "$PGROOT/data/PG_VERSION" ]; then
  "$PGROOT/bin/pg_ctl" -D "$PGROOT/data" stop 2>/dev/null || pkill -f "$PGROOT/bin/postgres" 2>/dev/null || true
fi
sleep 1

echo "=== 3) extract ==="
python - "$JAR" "$PGROOT" <<'PY'
import zipfile, tarfile, io, sys, os
jar, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(jar)
txz = [n for n in z.namelist() if n.endswith('.txz')][0]
with tarfile.open(fileobj=io.BytesIO(z.read(txz)), mode='r:xz') as t:
    t.extractall(out)
print("EXTRACTED:", txz)
PY

PGBIN="$PGROOT/bin"
chmod +x "$PGBIN"/*

echo "=== 3) initdb + start (no sudo needed — user-owned data dir) ==="
if [ ! -f "$PGROOT/data/PG_VERSION" ]; then
  "$PGBIN/initdb" -D "$PGROOT/data" -U postgres -A trust -E UTF8 --no-locale 2>&1 | tail -1
fi
"$PGBIN/pg_ctl" -D "$PGROOT/data" -o "-p $PGPORT" -l "$PGROOT/postgres.log" start 2>&1 | tail -1
sleep 2

echo "=== 4) create database ==="
"$PGBIN/psql" -h 127.0.0.1 -p "$PGPORT" -U postgres -c "CREATE DATABASE emergency;" 2>/dev/null || echo "(db already exists)"
"$PGBIN/psql" -h 127.0.0.1 -p "$PGPORT" -U postgres -tAc "SELECT 'PG OK: ' || version();" | head -1

echo "=== 5) python deps ==="
pip install -q -r "$ROOT/backend/requirements.txt"

echo "=== 6) migrate (deploy settings) ==="
cd "$ROOT/backend"
export DJANGO_SETTINGS_MODULE=config.settings.deploy
export DJANGO_SECRET_KEY="${DJANGO_SECRET_KEY:-$(python -c 'import secrets; print(secrets.token_urlsafe(50))')}"
export DATABASE_URL="postgres://postgres:postgres@127.0.0.1:$PGPORT/emergency"
export OTP_TEST_MODE=1
export OTP_TEST_CODE="${OTP_TEST_CODE:-123456}"
export DJANGO_SETTINGS_MODULE=config.settings.deploy
python manage.py migrate --noinput 2>&1 | tail -2

echo "=== 7) gunicorn on :8001 ==="
nohup gunicorn config.wsgi:application --bind 0.0.0.0:8001 > /tmp/gunicorn.log 2>&1 &
sleep 4
curl -s -o /dev/null -w "local check: HTTP %{http_code} (401 = alive)\n" --max-time 10 http://127.0.0.1:8001/api/v1/users/me

# persist env for future terminals in this codespace
printenv DJANGO_SECRET_KEY DATABASE_URL OTP_TEST_MODE OTP_TEST_CODE DJANGO_SETTINGS_MODULE > .env.codespace
echo "env saved to backend/.env.codespace"

echo ""
echo "=============================================================="
echo " DONE — three steps left (in the VS Code UI):"
echo "  1) Ports panel (bottom) → port 8001 → right-click →"
echo "     Port Visibility → Public"
echo "  2) Your backend URL:"
echo "     https://<CODESPACE-NAME>-8001.app.github.dev"
echo "     (the Ports panel shows the exact forwarded address)"
echo "  3) In the phone app: تنظیمات → آدرس Backend = همان URL"
echo "     Login OTP (test mode): $OTP_TEST_CODE"
echo "=============================================================="
