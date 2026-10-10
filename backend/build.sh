#!/usr/bin/env bash
# Render.com build command: `bash build.sh`
set -e
pip install -r requirements.txt
python manage.py migrate --noinput
python manage.py collectstatic --noinput
