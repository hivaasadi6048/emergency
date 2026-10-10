/// Domain entities — pure data, no Flutter/API dependencies.
enum EmergencyStatus {
  triggered,
  starting,
  active,
  degraded,
  resolving,
  resolved,
  cancelled,
  failed;

  static EmergencyStatus fromName(String? raw) =>
      values.firstWhere((e) => e.name == (raw ?? '').toLowerCase(), orElse: () => EmergencyStatus.triggered);

  bool get isTerminal => this == resolved || this == cancelled || this == failed;

  String get persianLabel => switch (this) {
        triggered => 'ثبت شد',
        starting => 'در حال راه‌اندازی',
        active => 'فعال',
        degraded => 'کاهش‌یافته',
        resolving => 'در حال پایان',
        resolved => 'پایان یافت',
        cancelled => 'لغو شد',
        failed => 'ناموفق',
      };
}

class UserEntity {
  final String id;
  final String phone;
  final String displayName;
  UserEntity({required this.id, required this.phone, required this.displayName});

  factory UserEntity.fromJson(Map<String, dynamic> j) => UserEntity(
        id: (j['id'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        displayName: (j['display_name'] ?? '').toString(),
      );
}

class ContactEntity {
  final String id;
  final String name;
  final String phone;
  final String relationship;
  final int priority;
  final bool isActive;
  ContactEntity({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.priority,
    required this.isActive,
  });

  factory ContactEntity.fromJson(Map<String, dynamic> j) => ContactEntity(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        relationship: (j['relationship'] ?? '').toString(),
        priority: (j['priority'] is num) ? (j['priority'] as num).toInt() : 0,
        isActive: (j['is_active'] ?? true) == true,
      );
}

class SessionEntity {
  final String id;
  final EmergencyStatus status;
  final String triggerType;
  final DateTime? startedAt;
  final DateTime? resolvedAt;
  final DateTime? lastLocationAt;
  final Map<String, dynamic>? latestLocation; // {latitude, longitude, accuracy_m, captured_at}

  SessionEntity({
    required this.id,
    required this.status,
    required this.triggerType,
    this.startedAt,
    this.resolvedAt,
    this.lastLocationAt,
    this.latestLocation,
  });

  factory SessionEntity.fromJson(Map<String, dynamic> j) => SessionEntity(
        id: (j['id'] ?? '').toString(),
        status: EmergencyStatus.fromName(j['status']?.toString()),
        triggerType: (j['trigger_type'] ?? '').toString(),
        startedAt: _date(j['started_at']),
        resolvedAt: _date(j['resolved_at']),
        lastLocationAt: _date(j['last_location_at']),
        latestLocation: j['latest_location'] is Map ? Map<String, dynamic>.from(j['latest_location'] as Map) : null,
      );

  static DateTime? _date(Object? raw) =>
      raw == null ? null : DateTime.tryParse(raw.toString())?.toUtc();
}

class EventEntity {
  final String id;
  final String eventType;
  final Map<String, dynamic> payload;
  final DateTime? createdAt;
  EventEntity({required this.id, required this.eventType, required this.payload, this.createdAt});

  factory EventEntity.fromJson(Map<String, dynamic> j) => EventEntity(
        id: (j['id'] ?? '').toString(),
        eventType: (j['event_type'] ?? '').toString(),
        payload: j['payload'] is Map ? Map<String, dynamic>.from(j['payload'] as Map) : {},
        createdAt: j['created_at'] == null ? null : DateTime.tryParse(j['created_at'].toString()),
      );
}
