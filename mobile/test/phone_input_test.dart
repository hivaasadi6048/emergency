import 'package:flutter_test/flutter_test.dart';

import 'package:emergency_poc/core/phone_input.dart';

void main() {
  test('strips invisible direction marks and keeps valid characters', () {
    // RTL mark (U+200F) between digits — what Persian keyboards inject
    expect(sanitizePhoneInput('0912\u200F1234567'), '09121234567');
    expect(sanitizePhoneInput('\u200E0912 123 4567'), '0912 123 4567');
  });

  test('converts persian and arabic digits', () {
    expect(sanitizePhoneInput('۰۹۱۲۱۲۳۴۵۶۷'), '09121234567');
    expect(sanitizePhoneInput('٠٩١٢١٢٣٤٥٦٧'), '09121234567');
  });

  test('drops letters and emoji entirely', () {
    expect(sanitizePhoneInput('abc 0912 📱 1234567'), '0912  1234567');
  });

  test('trims whitespace', () {
    expect(sanitizePhoneInput('  09121234567  '), '09121234567');
  });
}
