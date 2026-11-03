import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import 'app_state.dart';
import 'data.dart';

/// يرسل هوية الحساب للسيرفر ليسجّل عنوان IP (للمطورين فقط) — مرة كل 6 ساعات
Future<void> reportIp() async {
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (prefs.getInt('ip_t') ?? 0) < 6 * 3600 * 1000) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final base = ((await ref('config/gwUrl').get()).value ?? '').toString();
    if (!base.startsWith('https://')) return;
    final tok = await u.getIdToken();
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final r = await c.postUrl(Uri.parse('$base/gw/hello'));
    r.headers.contentType = ContentType.json;
    r.write(jsonEncode(<String, String>{'t': tok ?? ''}));
    final res = await r.close().timeout(const Duration(seconds: 12));
    await res.drain<void>();
    c.close();
    if (res.statusCode == 204) prefs.setInt('ip_t', now);
  } catch (_) {}
}
