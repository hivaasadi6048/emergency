/// Stable API error (docs/api-contract.md §1 envelope).
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic>? body;

  ApiException({required this.status, required this.code, required this.message, this.body});

  bool get isAuthError => status == 401;
  bool get isConflictActiveSession => code == 'CONFLICT_ACTIVE_SESSION';

  /// Persian UX text per stable code — the UI never shows raw codes to users.
  String get persianMessage {
    switch (code) {
      case 'VALIDATION_ERROR':
        return 'اطلاعات وارد شده معتبر نیست.';
      case 'UNAUTHORIZED':
        return 'ورود دوباره لازم است.';
      case 'AUTH_EXPIRED':
        return 'نشست شما منقضی شده است؛ لطفاً دوباره وارد شوید.';
      case 'FORBIDDEN':
        return 'دسترسی مجاز نیست.';
      case 'NOT_FOUND':
        return 'یافت نشد.';
      case 'CONFLICT_INVALID_TRANSITION':
        return 'این عملیات در وضعیت فعلی ممکن نیست.';
      case 'CONFLICT_ACTIVE_SESSION':
        return 'یک وضعیت اضطراری فعال دارید.';
      case 'IDEMPOTENCY_KEY_REUSED':
      case 'IDEMPOTENCY_IN_PROGRESS':
        return 'درخواست تکراری است؛ چند لحظه بعد دوباره تلاش کنید.';
      case 'RATE_LIMITED':
      case 'otp_rate_limited':
        return 'تعداد درخواست‌ها زیاد است؛ بعداً تلاش کنید.';
      case 'otp_invalid':
        return 'کد وارد شده درست نیست.';
      case 'otp_expired':
        return 'کد منقضی شده؛ کد جدید بگیرید.';
      case 'otp_locked':
        return 'کد به‌دلیل تلاش‌های زیاد قفل شد؛ کد جدید بگیرید.';
      case 'otp_not_found':
        return 'کدی برای این شماره صادر نشده.';
      case 'MISSING_IDEMPOTENCY_KEY':
        return 'درخواست ناقص بود.';
      case 'NETWORK':
        return 'ارتباط با سرور برقرار نشد؛ اینترنت را بررسی کنید.';
      default:
        return 'خطای غیرمنتظره رخ داد. ($code)';
    }
  }

  @override
  String toString() => 'ApiException($status, $code)';
}
