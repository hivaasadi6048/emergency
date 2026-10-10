from django.urls import path

from .views import DeviceListCreateView

urlpatterns = [
    path("devices", DeviceListCreateView.as_view(), name="device-list"),
]
