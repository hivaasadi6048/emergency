/// Client-side phone input hardening: keyboards (esp. Persian) inject invisible
/// direction marks and other characters the server rejects. Everything except
/// digits/plus/brackets/dash/space/dot is stripped, and Persian/Arabic digits
/// are converted — the server does final normalization (E.164).
const _digitMap = {
  '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4', '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
  '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
};

String sanitizePhoneInput(String raw) {
  var s = raw.split('').map((c) => _digitMap[c] ?? c).join();
  s = s.replaceAll(RegExp(r'[^\d\s()+\-.]'), ''); // drops RTL/LTR marks, letters, emoji…
  return s.trim();
}
