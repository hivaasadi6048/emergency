from django.db import IntegrityError
from django.db.models import Q
from rest_framework import generics
from rest_framework.exceptions import ValidationError

from .models import TrustedContact
from .serializers import TrustedContactSerializer


class ContactListCreateView(generics.ListCreateAPIView):
    serializer_class = TrustedContactSerializer

    def get_queryset(self):
        return TrustedContact.objects.filter(user=self.request.user, is_active=True).order_by("priority", "created_at")

    def perform_create(self, serializer):
        try:
            serializer.save(user=self.request.user)
        except IntegrityError:
            # race-safe backstop for the DB partial-unique constraint
            raise ValidationError({"phone": ["contact_duplicate_active"]})


class ContactDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = TrustedContactSerializer
    # DELETE is a soft delete (is_active=False) per docs/data-model.md §3

    def get_queryset(self):
        return TrustedContact.objects.filter(user=self.request.user)

    def perform_update(self, serializer):
        try:
            serializer.save()
        except IntegrityError:
            raise ValidationError({"phone": ["contact_duplicate_active"]})

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])
