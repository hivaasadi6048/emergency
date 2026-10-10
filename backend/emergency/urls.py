from django.urls import path

from .views import (
    CapabilityView,
    CancelView,
    ResolveView,
    SessionDetailView,
    SessionEventsView,
    SessionListCreateView,
)

urlpatterns = [
    path("emergency/sessions", SessionListCreateView.as_view(), name="emergency-sessions"),
    path("emergency/sessions/<uuid:pk>", SessionDetailView.as_view(), name="emergency-session"),
    path("emergency/sessions/<uuid:pk>/events", SessionEventsView.as_view(), name="emergency-session-events"),
    path("emergency/sessions/<uuid:pk>/resolve", ResolveView.as_view(), name="emergency-resolve"),
    path("emergency/sessions/<uuid:pk>/cancel", CancelView.as_view(), name="emergency-cancel"),
    path("emergency/sessions/<uuid:pk>/capability", CapabilityView.as_view(), name="emergency-capability"),
]
