import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url = TextEditingController(text: widget.state.client.baseUrl);

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onChange);
    _loadPermissions();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPermissions() async {
    await widget.state.native.permissions();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_onChange);
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('آدرس Backend', style: TextStyle(fontWeight: FontWeight.bold)),
              TextField(controller: _url, decoration: const InputDecoration(hintText: AppConfig.defaultBackendUrl)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  state.client.baseUrl = _url.text.trim().isEmpty
                      ? AppConfig.defaultBackendUrl
                      : _url.text.trim();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('آدرس ذخیره شد: ${state.client.baseUrl}')),
                  );
                },
                child: const Text('ذخیره آدرس'),
              ),
              const SizedBox(height: 6),
              const Text(
                'روی گوشی واقعی با adb reverse tcp:8000 tcp:8000 آدرس پیش‌فرض کار می‌کند.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مجوزهای دستگاه (وضعیت واقعی)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              FutureBuilder<Map<String, dynamic>>(
                future: state.native.permissions(),
                builder: (context, snap) {
                  final p = snap.data ?? {};
                  bool b(Object? v) => v == true;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('موقعیت دقیق: ${b(p['fineLocation']) ? "دارد ✓" : "ندارد ✗"}'),
                    Text('اعلان‌ها: ${b(p['notifications']) ? "دارد ✓" : "ندارد ✗"}'),
                    const Text('موقعیت پس‌زمینه: عمداً درخواست نمی‌شود (D-06)',
                        style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ]);
                },
              ),
              const SizedBox(height: 6),
              const Text(
                'پیامد نبود مجوز: بدون مجوز موقعیت، Session اضطراری نمی‌تواند ردیابی را شروع کند و وضعیت FAILED/DEGRADED صادقانه نمایش داده می‌شود.',
                style: TextStyle(fontSize: 11),
              ),
            ]),
          ),
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('صداقت محصول', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text(
                'این سیستم: جرم را متوقف نمی‌کند؛ نجات را تضمین نمی‌کند؛ تحویل پیام را تضمین نمی‌کند؛ '
                'دریافت موقعیت در تمام شرایط را تضمین نمی‌کند. وضعیت واقعی (ACTIVE/DEGRADED/FAILED) همیشه صادقانه نمایش داده می‌شود.',
                style: TextStyle(fontSize: 12),
              ),
            ]),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('خروج'),
            onTap: () async {
              // C-020: navigation is centralized — HomeShell's auth listener routes
              // to /login when AppState drops the user (covers manual logout AND
              // server-side session death with one code path; no double navigation).
              await state.logout();
            },
          ),
        ),
      ],
    );
  }
}
