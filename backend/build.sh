#!/usr/bin/env bash
# Render.com build command: `bash build.sh`
set -e
# Without this, manage.py falls back to dev settings (localhost Postgres) — B-021
export DJANGO_SETTINGS_MODULE=config.settings.deploy
pip install -r requirements.txt
python manage.py migrate --noinput
python manage.py collectstatic --noinput
