"""ASGI entrypoint. Channels/websocket layering lands in Phase 6 (D-12)."""
import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")

application = get_asgi_application()
