import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import 'app_state.dart';
import 'data.dart';
import 'home.dart';

String dayKey() => DateTime.now().toIso8601String().substring(0, 10);

Future<num> balanceNow() async {
  final s = await ref('wallets/$myUid/bal').get();
  return s.value is num ? s.value as num : 0;
}

/// تعديل الرصيد. gain=true يكتب ts الخادم (شرط قاعدة الربح)
Future<void> addBal(int delta, {bool gain = false}) async {
  final cur = (await balanceNow()).toInt();
  final nb = cur + delta;
  if (nb < 0) throw 'low';
  final up = <String, Object?>{'wallets/$myUid/bal': nb};
  if (gain) up['wallets/$myUid/ts'] = ServerValue.timestamp;
  await db.ref().update(up);
}

Future<void> addBalRetry(int d) async {
  try {
    await addBal(d, gain: true);
  } catch (_) {
    await Future<void>.delayed(const Duration(milliseconds: 4500));
    await addBal(d, gain: true);
  }
}

String? feedGid(String kind) {
  for (final e in groupsCache.entries) {
    if (e.value['kind'] == kind && memCache[e.key] != null) return e.key;
  }
  return null;
}

/// رسالة من ALJESI داخل قروب (sys)
Future<void> botSay(String gid, String text, {String k = 'bot', String? img, String? d, String? pic}) async {
  try {
    final m = <String, Object?>{
      'from': myUid,
      'type': 'sys',
      'k': k,
      'f': Session.me.name,
      'text': text.length > 1900 ? text.substring(0, 1900) : text,
      'ts': ServerValue.timestamp,
    };
    if (img != null) m['img'] = img;
    if (d != null) m['d'] = d;
    if (pic != null) m['pic'] = pic;
    await ref('messages/$gid').push().set(m);
  } catch (_) {}
}

/// إشعار في قروب نظام (إعلانات/متجر/صحيفة...)
Future<void> feedNote(String kind, String text, {String k = 'note', String? d}) async {
  final g = feedGid(kind);
  if (g == null) return;
  try {
    final m = <String, Object?>{'from': myUid, 'type': 'sys', 'k': k, 'text': text, 'ts': ServerValue.timestamp};
    if (d != null) m['d'] = d;
    await ref('messages/$g').push().set(m);
  } catch (_) {}
}

Future<void> sendNotif(String to, Map<String, Object?> n) async {
  try {
    final m = Map<String, Object?>.from(n);
    m['from'] = myUid;
    m['ts'] = ServerValue.timestamp;
    await ref('notifs/$to').push().set(m);
  } catch (_) {}
}

List<String> mainGroups() => memCache.entries
    .where((e) => e.value == true && groupsCache[e.key]?['kind'] == 'main')
    .map((e) => e.key)
    .toList();
