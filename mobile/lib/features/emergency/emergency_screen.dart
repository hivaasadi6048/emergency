import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities.dart';
import '../../state/app_state.dart';
import '../shared/ui.dart';

class EmergencyScreen extends StatefulWidget {
  final AppState state;
  const EmergencyScreen({super.key, required this.state});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onChange);
    widget.state.refreshActiveFromBackend();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.state.hasActiveSession) setState(() {});
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_onChange);
    _elapsedTimer?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final s = widget.state.activeSession;
    if (s == null || s.startedAt == null) return '—';
    final seconds = DateTime.now().toUtc().difference(s.startedAt!).inSeconds.clamp(0, 86399);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _fmt(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  Future<void> _confirmAndResolve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('پایان وضعیت اضطراری؟'),
        content: const Text('ردیابی موقعیت متوقف می‌شود و مخاطبین دیگر به‌روزرسانی نمی‌شوند. مطمئنید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('بازگشت')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('بله، پایان')),
        ],
      ),
    );
    if (ok == true) await widget.state.resolveActive();
  }

  Future<void> _confirmAndCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('لغو درخواست اضطراری؟'),
        content: const Text('این عملیات فقط قبل از فعال‌شدن ردیابی ممکن است.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('بازگشت')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('لغو کن')),
        ],
      ),
    );
    if (ok == true) await widget.state.cancelActive();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final session = state.activeSession;
    if (session != null && session.status.isTerminal) {
      // finished — show a close card instead of SOS
      return _FinishedCard(state: state, session: session);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ErrorBanner(message: state.lastError),
        if (session == null) ...[
          const SizedBox(height: 8),
          Center(
            child: Column(children: [
              const Text('در خطر هستید؟', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              SizedBox(
                width: 190,
                height: 190,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    shape: const CircleBorder(),
                  ),
                  onPressed: state.busy ? null : () => state.sos(),
                  child: const Text('SOS', style: TextStyle(fontSize: 40, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'با فشردن SOS، Session اضطراری ساخته می‌شود، ردیابی موقعیت شروع می‌شود و لینک مشاهده برای مخاطبین شما آماده خواهد شد.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ]),
          ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  StatusChip(status: session.status),
                  const SizedBox(width: 10),
                  Text('زمان سپری‌شده: $_elapsed'),
                ]),
                const SizedBox(height: 8),
                Text('شناسه Session: ${session.id.substring(0, 8)}…',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
                if (session.latestLocation != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'موقعیت فعلی: ${session.latestLocation!['latitude']}, ${session.latestLocation!['longitude']}'
                    ' (±${session.latestLocation!['accuracy_m'] ?? '?'} متر)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  if (session.lastLocationAt != null)
                    Text('آخرین ثبت: ${_fmt(session.lastLocationAt!.toLocal())}',
                        style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('هنوز نقطه موقعیتی دریافت نشده — چند لحظه صبر کنید.',
                        style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ),
                if (session.status == EmergencyStatus.starting)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('در حال راه‌اندازی ردیابی… چند لحظه صبر کنید.',
                        style: TextStyle(color: Colors.deepOrange)),
                  ),
                if (session.status == EmergencyStatus.degraded)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('وضعیت کاهش‌یافته: بخشی از قابلیت‌ها در دسترس نیست. وضعیت واقعی همین است که می‌بینید.',
                        style: TextStyle(color: Colors.deepOrange)),
                  ),
                const SizedBox(height: 10),
                Row(children: [
                  if (session.status == EmergencyStatus.triggered)
                    OutlinedButton(onPressed: state.busy ? null : _confirmAndCancel, child: const Text('لغو')),
                  if (session.status == EmergencyStatus.active || session.status == EmergencyStatus.degraded)
                    FilledButton.tonal(
                      onPressed: state.busy ? null : _confirmAndResolve,
                      child: const Text('پایان وضعیت اضطراری'),
                    ),
                ]),
              ]),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('مخاطبین شما', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (state.contacts.isEmpty)
                  const Text('هنوز مخاطبی اضافه نکرده‌اید — از تب «مخاطبین» اضافه کنید.',
                      style: TextStyle(fontSize: 12, color: Colors.black54))
                else
                  ...state.contacts.take(3).map((c) => Text('• ${c.name} — ${c.phone}',
                      style: const TextStyle(fontSize: 12))),
              ]),
            ),
          ),
        ],
        const Card(
          child: Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'تضمینی برای توقف جرم، نجات یا تحویل پیام وجود ندارد. این صفحه وضعیت واقعی سیستم را نشان می‌دهد.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        ),
      ],
    );
  }
}

class _FinishedCard extends StatelessWidget {
  final AppState state;
  final SessionEntity session;
  const _FinishedCard({required this.state, required this.session});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            StatusChip(status: session.status),
            const SizedBox(height: 10),
            Text(switch (session.status) {
              EmergencyStatus.resolved => 'وضعیت اضطراری با تأیید شما پایان یافت.',
              EmergencyStatus.cancelled => 'درخواست قبل از فعال‌سازی لغو شد.',
              EmergencyStatus.failed => 'راه‌اندازی ناموفق بود — ردیابی انجام نشد.',
              _ => 'Session بسته شد.',
            }),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => state.clearFinishedSession(),
              child: const Text('بستن'),
            ),
          ]),
        ),
      ),
    ]);
  }
}
