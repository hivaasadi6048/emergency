import 'package:flutter/material.dart';

import '../../core/phone_input.dart';
import '../../state/app_state.dart';
import '../shared/ui.dart';

class LoginScreen extends StatefulWidget {
  final AppState state;
  const LoginScreen({super.key, required this.state});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _devCode;
  bool _otpSent = false;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onChange);
    // TextField text changes do NOT rebuild the widget by themselves: without
    // an unconditional setState the submit button stays disabled forever.
    _phone.addListener(() {
      if (mounted) setState(() {});
      if (_fieldError != null) _fieldError = null;
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
    if (widget.state.isLoggedIn && mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onChange);
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final phone = sanitizePhoneInput(_phone.text);
    if (phone.isEmpty) {
      setState(() => _fieldError = 'شماره موبایل را وارد کنید — مثال: 09121234567');
      return;
    }
    String? code;
    try {
      code = await widget.state.requestOtp(phone);
    } catch (_) {
      code = null;
    }
    if (!mounted) return;
    setState(() {
      if (code == null || code.isEmpty) {
        // show the REAL cause (network vs validation) — never a misleading one
        _fieldError = widget.state.lastError ?? 'دریافت کد ناموفق بود؛ دوباره تلاش کنید.';
      } else {
        _fieldError = null;
        _otpSent = true;
        _devCode = code;
        _code.text = code; // dev-mode auto-fill
      }
    });
  }

  Future<void> _verify() async {
    await widget.state.verifyOtp(_phone.text, _code.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(title: const Text('ورود — پلتفرم ایمنی')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('شماره موبایل شما تنها هویت شما در سیستم است (E.164).'),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'شماره موبایل (مثلاً ۰۹۱۲…)',
              border: const OutlineInputBorder(),
              errorText: _fieldError,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: state.busy || _phone.text.trim().isEmpty ? null : _requestOtp,
            child: const Text('دریافت کد تأیید'),
          ),
          if (_devCode != null) ...[
            const SizedBox(height: 8),
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('کد تأیید (حالت توسعه):', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(_devCode!, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4)),
                  const Text(
                    'کد در پیامک ارسال نمی‌شود — در حالت توسعه همین‌جا نمایش داده می‌شد و خودکار پر شده است. فقط «ورود» را بزنید.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ]),
              ),
            ),
          ],
          if (_otpSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'کد تأیید', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: state.busy ? null : _verify,
              child: const Text('ورود'),
            ),
          ],
          ErrorBanner(message: state.lastError),
          const SizedBox(height: 24),
          const Text(
            'این سیستم جرم را متوقف نمی‌کند و نجات یا تحویل پیام را تضمین نمی‌کند؛ '
            'وضعیت واقعی را صادقانه نشان می‌دهد.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
