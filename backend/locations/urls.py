from django.urls import path

from .views import LocationBatchUploadView

urlpatterns = [
    path("locations", LocationBatchUploadView.as_view(), name="locations-upload"),
]
