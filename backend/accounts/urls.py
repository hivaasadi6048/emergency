from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import LogoutView, MeView, RequestOtpView, VerifyOtpView

urlpatterns = [
    path("auth/request-otp", RequestOtpView.as_view(), name="request-otp"),
    path("auth/verify-otp", VerifyOtpView.as_view(), name="verify-otp"),
    path("auth/refresh", TokenRefreshView.as_view(), name="refresh"),
    path("auth/logout", LogoutView.as_view(), name="logout"),
    path("users/me", MeView.as_view(), name="me"),
]
