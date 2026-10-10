import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emergency_poc/core/api/api_client.dart';
import 'package:emergency_poc/core/native/emergency_native.dart';
import 'package:emergency_poc/data/repositories_impl.dart';
import 'package:emergency_poc/features/auth/login_screen.dart';
import 'package:emergency_poc/state/app_state.dart';

void main() {
  // REGRESSION (owner report, 2026-10-04): typing in the phone field never
  // enabled the «دریافت کد تأیید» button, because TextField text changes do
  // not rebuild the widget and the listener only rebuilt on field errors.
  testWidgets('submit button enables as soon as a phone number is typed', (tester) async {
    final tokens = InMemoryTokenStore();
    final client = ApiClient(baseUrl: 'http://127.0.0.1:9', tokenStore: tokens); // nothing listens — button-only test
    final state = AppState(
      tokens: tokens,
      client: client,
      authRepo: AuthRepositoryImpl(client, tokens),
      contactRepo: ContactRepositoryImpl(client),
      emergencyRepo: EmergencyRepositoryImpl(client),
      native: EmergencyNative(),
    );

    await tester.pumpWidget(MaterialApp(home: LoginScreen(state: state)));
    await tester.pump();

    FilledButton button() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'دریافت کد تأیید'));

    // initially disabled (empty field)
    expect(button().onPressed, isNull);

    // typing must rebuild and ENABLE the button
    await tester.enterText(find.byType(TextField).first, '09121234567');
    await tester.pump();

    expect(button().onPressed, isNotNull);
  });
}
