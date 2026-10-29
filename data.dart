import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/painting.dart';

FirebaseDatabase get db => FirebaseDatabase.instance;
DatabaseReference ref(String path) => db.ref(path);
String get myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

/// الملف الشخصي (profiles/{uid})
class Prof {
  final String name, color, gender;
  final int ts;
  const Prof(this.name, this.color, this.gender, this.ts);

  static const Prof fallback = Prof('عضو', '#888888', 'm', 0);

  factory Prof.fromMap(Map<String, dynamic> m) => Prof(
        (m['name'] ?? 'عضو').toString(),
        (m['color'] ?? '#888888').toString(),
        (m['gender'] ?? 'm').toString(),
        m['ts'] is num ? (m['ts'] as num).toInt() : 0,
      );
}

final Map<String, Future<Prof>> _profs = {};
final Map<String, Future<String>> _avs = {};
final Map<String, Future<String?>> _roles = {};
final Map<String, MemoryImage> _avImgs = {};
final Map<String, String> _avSrc = {};

/// يقرأ ملف العضو مرة واحدة ويحفظه
Future<Prof> prof(String u) => _profs.putIfAbsent(u, () async {
      try {
        final s = await ref('profiles/$u').get();
        final v = s.value;
        if (v is Map) return Prof.fromMap(Map<String, dynamic>.from(v));
        return Prof.fallback;
      } catch (_) {
        _profs.remove(u);
        return Prof.fallback;
      }
    });

void dropProf(String u) => _profs.remove(u);
void dropRole(String u) => _roles.remove(u);
void setProfCache(String u, Prof p) => _profs[u] = Future.value(p);

/// الصورة الشخصية كنص data:image (avatars/{uid})
Future<String> avOf(String u) => _avs.putIfAbsent(u, () async {
      try {
        final s = await ref('avatars/$u').get();
        return s.value?.toString() ?? '';
      } catch (_) {
        _avs.remove(u);
        return '';
      }
    });

void setAvCache(String u, String d) {
  _avs[u] = Future.value(d);
  _avImgs.remove(u);
  _avSrc.remove(u);
}

/// يحوّل data:image إلى صورة جاهزة للعرض
MemoryImage? avImage(String u, String data) {
  if (data.isEmpty) return null;
  final old = _avImgs[u];
  if (old != null && _avSrc[u] == data) return old;
  try {
    final i = data.indexOf(',');
    final img = MemoryImage(base64Decode(data.substring(i + 1)));
    _avImgs[u] = img;
    _avSrc[u] = data;
    return img;
  } catch (_) {
    return null;
  }
}

/// رتبة العضو: emp (الإمبراطور) أو dev أو null
Future<String?> roleOf(String u) {
  if (u.isNotEmpty && u == Session.emp) return Future.value('emp');
  return _roles.putIfAbsent(u, () async {
    try {
      final s = await ref('roles/$u').get();
      return s.value?.toString();
    } catch (_) {
      return null;
    }
  });
}

/// بيانات جلسة المستخدم الحالي
class Session {
  static Prof me = Prof.fallback;
  static String emp = '';
  static String? role;
  static String pid = '';

  static bool get isEmp => emp.isNotEmpty && myUid == emp;
  static bool get isDev => isEmp || role == 'dev';

  static void reset() {
    _profs.clear();
    _avs.clear();
    _roles.clear();
    _avImgs.clear();
    _avSrc.clear();
    me = Prof.fallback;
    emp = '';
    role = null;
    pid = '';
  }

  /// يرجع: ok أو noprofile أو banned أو error
  static Future<String> load() async {
    reset();
    final u = myUid;
    if (u.isEmpty) return 'error';
    try {
      final res = await Future.wait([
        ref('profiles/$u').get(),
        ref('config/emperorUid').get(),
        ref('roles/$u').get(),
        ref('banned/$u').get(),
      ]);
      final p = res[0];
      if (!p.exists || p.value is! Map) return 'noprofile';
      if (res[3].exists) return 'banned';
      me = Prof.fromMap(Map<String, dynamic>.from(p.value as Map));
      emp = res[1].value?.toString() ?? '';
      role = res[2].value?.toString();
      _profs[u] = Future.value(me);
      return 'ok';
    } catch (_) {
      return 'error';
    }
  }

  /// معرّف الـ ID المكوّن من 9 أرقام (pdata/{uid}/pid و pids/{pid})
  static Future<void> ensurePid() async {
    try {
      final u = myUid;
      final s = await ref('pdata/$u/pid').get();
      if (s.exists) {
        pid = s.value.toString();
        return;
      }
      final rnd = Random.secure();
      for (var i = 0; i < 8; i++) {
        final p = (100000000 + rnd.nextInt(900000000)).toString();
        if ((await ref('pids/$p').get()).exists) continue;
        await db.ref().update(<String, Object?>{'pdata/$u/pid': p, 'pids/$p': u});
        pid = p;
        return;
      }
    } catch (_) {}
  }
}


/// تسجيل خسارة في الألعاب (للمتصدرين)
Future<void> addLoss(int n) async {
  try {
    if (n <= 0 || Session.isEmp) return;
    await ref('loss/$myUid').set(ServerValue.increment(n));
  } catch (_) {}
}
