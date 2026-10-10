from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include("accounts.urls")),
    path("api/v1/", include("devices.urls")),
    path("api/v1/", include("contacts.urls")),
    path("api/v1/", include("emergency.urls")),
    path("api/v1/", include("locations.urls")),
]
