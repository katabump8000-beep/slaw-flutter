import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// التخزين المحلي (مثل localStorage في التطبيق القديم)
late SharedPreferences prefs;

/// لعرض رسائل التنبيه (toast) من أي مكان بدون context
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

const String kDefaultAccentHex = '#ff7a1a';

/// لون الواجهة الحالي (يتغير من الإعدادات)
final ValueNotifier<String> accentHex = ValueNotifier<String>(kDefaultAccentHex);

/// يزيد رقمه عند تغيير أي صورة شخصية ليُعاد رسمها
final ValueNotifier<int> avatarTick = ValueNotifier<int>(0);

// ألوان التطبيق القديم (chat.css)
const Color kBg = Color(0xFF120804);
const Color kBg2 = Color(0xFF1F0E07);
const Color kCard = Color(0xFF2A130A);
const Color kTx = Color(0xFFFFF4E8);
const Color kMu = Color(0xFFC9A58C);
const Color kRed = Color(0xFFFF5A4D);
const Color kLine = Color.fromRGBO(255, 190, 140, 0.18);
const Color kDarkText = Color(0xFF2A0D00);

const List<String> kAccents = [
  '#ff7a1a', '#e53935', '#d81b60', '#8e24aa', '#3949ab',
  '#1e88e5', '#00acc1', '#00897b', '#43a047', '#f9a825',
];

const List<String> kBubbleColors = [
  '#ff7a1a', '#e53935', '#d81b60', '#8e24aa', '#5e35b1', '#3949ab', '#1e88e5',
  '#00acc1', '#00897b', '#43a047', '#7cb342', '#f9a825', '#6d4c41', '#546e7a',
];

bool hexOk(String? c) => c != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(c);

List<int> rgbOf(String h) {
  if (!hexOk(h)) return [136, 136, 136];
  return [
    int.parse(h.substring(1, 3), radix: 16),
    int.parse(h.substring(3, 5), radix: 16),
    int.parse(h.substring(5, 7), radix: 16),
  ];
}

Color hexColor(String? h) {
  final c = rgbOf(h ?? '');
  return Color.fromRGBO(c[0], c[1], c[2], 1);
}

String _toHex(List<int> c) =>
    '#${c.map((v) => v.clamp(0, 255).toInt().toRadixString(16).padLeft(2, '0')).join()}';

String lightenHex(String h, [double k = .35]) =>
    _toHex(rgbOf(h).map((v) => (v + (255 - v) * k).round()).toList());

String darkHex(String h) => _toHex(rgbOf(h).map((v) => (v * .62).round()).toList());

/// ألوان اللون الأساسي للواجهة، تتحدث تلقائياً عند تغييره
extension AccentX on BuildContext {
  Color get accent => Theme.of(this).colorScheme.primary;
  Color get accent2 => Theme.of(this).colorScheme.secondary;
}

/// اللون الأساسي بشفافية معينة
Color accentA(BuildContext c, double a) {
  Theme.of(c);
  final rgb = rgbOf(accentHex.value);
  return Color.fromRGBO(rgb[0], rgb[1], rgb[2], a);
}

ThemeData buildTheme(String ac) {
  final a = hexColor(ac);
  final a2 = hexColor(lightenHex(ac));
  final scheme = ColorScheme.dark(
    primary: a,
    onPrimary: kDarkText,
    secondary: a2,
    onSecondary: kDarkText,
    surface: kBg2,
    onSurface: kTx,
    error: kRed,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: kLine),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    canvasColor: kBg,
    dividerColor: kLine,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg2,
      foregroundColor: kTx,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color.fromRGBO(0, 0, 0, .3),
      contentPadding: const EdgeInsets.all(11),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: a),
      ),
    ),
  );
}

// ---------- أدوات صغيرة ----------

String fmtN(num n) => n
    .toInt()
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

int daysSince(int? ts) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final t = (ts == null || ts == 0) ? now : ts;
  final d = ((now - t) / 86400000).floor();
  return d < 0 ? 0 : d;
}

String hhmm(int ts) {
  if (ts == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// يحوّل الأرقام العربية ٠١٢ إلى 012
String normDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = ar.indexOf(ch);
    b.write(i >= 0 ? i.toString() : ch);
  }
  return b.toString();
}

String firstChar(String name) => name.isEmpty ? '?' : String.fromCharCode(name.runes.first);

/// رسالة تنبيه صغيرة أسفل الشاشة
void toast(String m, {bool bad = false, bool accent = false}) {
  final st = messengerKey.currentState;
  if (st == null) return;
  st.hideCurrentSnackBar();
  st.showSnackBar(SnackBar(
    content: Text(
      m,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: accent ? const Color(0xFF1A0A00) : Colors.white,
        fontWeight: accent ? FontWeight.w800 : FontWeight.w500,
      ),
    ),
    backgroundColor: accent ? hexColor(accentHex.value) : const Color(0xCC000000),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(milliseconds: 2600),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ));
}

/// رسالة خطأ مناسبة لنوع الخطأ
void err(Object e) {
  final s = e.toString().toLowerCase();
  toast(
    s.contains('permission') ? 'غير مسموح لك بهذا الإجراء' : 'حدث خطأ، تأكد من الاتصال',
    bad: true,
  );
}
