import 'servertime.dart';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'aljesi.dart';
import 'app_state.dart';
import 'lastseen.dart';
import 'config.dart';
import 'core.dart';
import 'home.dart';
import 'data.dart';
import 'widgets.dart';

/// مفتاح اللقب للمقارنة: يتجاهل الحروف المدّية والتكرار فيمنع الأسماء المتشابهة (ناروتو / نروتو / ناريتو)
String nameKey(String raw) {
  var t = raw.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640\s]'), '');
  t = t
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .toLowerCase();
  final base = t.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
  final core = base.replaceAll(RegExp('[اوي]'), '');
  final k = core.length >= 2 ? core : base;
  return k.replaceAll(RegExp(r'[.#$\[\]/]'), '_');
}

/// يسجّل آخر ظهور ونسخة التطبيق، ويحجز لقب العضو في فهرس الألقاب
/// هل التطبيق يعمل داخل بيئة مستنسخة/افتراضية؟ (كشف تقريبي لا يحظر أحداً)
/// اسم حزمة التطبيق الرسمي (org + project-name في ملف البناء). إن تغيّر عدّله هنا.
const String kPkg = 'io.github.katabump8000_beep.twa';

/// كلمات تدل على حزم برامج الاستنساخ (تُستعمل مع المسارات والمكتبات المحمّلة في العملية)
const List<String> kCloneWords = ['ludashi', 'dualspace', 'lbe.parallel', 'parallel', 'clone', 'cloner', 'virtual', 'multi.', 'multiaccounts', 'pengyou', 'lody', 'xclone', 'dualaid', 'vapp', 'sandbox'];

bool _isCloneName(String pkg) {
  final l = pkg.toLowerCase();
  return kCloneWords.any(l.contains);
}

/// فحص موسّع: يعيد {'sus': bool, 'host': اسم الحزمة المضيفة إن وُجدت, 'ind': مؤشرات}
Future<Map<String, Object>> cloneScan() async {
  final ind = <String>[];
  var sus = false;
  var host = '';
  try {
    final dirs = <String>[];
    try {
      dirs.add((await getApplicationSupportDirectory()).path);
    } catch (_) {}
    try {
      dirs.add((await getTemporaryDirectory()).path);
    } catch (_) {}
    try {
      dirs.add((await getApplicationDocumentsDirectory()).path);
    } catch (_) {}
    try {
      final e = await getExternalStorageDirectory();
      if (e != null) dirs.add(e.path);
    } catch (_) {}
    final rx = RegExp(r'/(?:data/user/(\d+)|data/data|Android/data|Android/media|Android/obb)/([^/]+)');
    for (final d in dirs) {
      final m = rx.firstMatch(d);
      if (m == null) {
        ind.add('مسار غير معتاد');
        sus = true;
        continue;
      }
      final pkg = m.group(2) ?? '';
      final u = int.tryParse(m.group(1) ?? '0') ?? 0;
      if (pkg != kPkg) {
        host = host.isEmpty ? pkg : host;
        ind.add('مسار يعود لتطبيق آخر: $pkg');
        sus = true;
      }
      if (u > 0) {
        ind.add('مستخدم أندرويد ثانوي رقم $u');
        sus = true;
      }
      final low = d.toLowerCase();
      if (low.contains('virtual') || low.contains('parallel') || low.contains('clone') || low.contains('dualspace') || low.contains('multi')) {
        ind.add('كلمات استنساخ في المسار');
        sus = true;
      }
    }
    try {
      final st = await File('/proc/self/status').readAsString();
      final m = RegExp(r'Uid:\s+(\d+)').firstMatch(st);
      if (m != null && (int.tryParse(m.group(1)!) ?? 0) >= 100000) {
        ind.add('معرّف تشغيل ثانوي (نسخة مزدوجة)');
        sus = true;
      }
    } catch (_) {}
    try {
      final cl = await File('/proc/self/cmdline').readAsString();
      final proc = cl.split('\u0000').first.trim();
      if (proc.isNotEmpty && !proc.startsWith(kPkg)) {
        ind.add('اسم العملية: $proc');
        host = host.isEmpty ? proc.split(':').first : host;
        sus = true;
      }
    } catch (_) {}
    // مكتبات/ملفات محمّلة داخل العملية: برامج الاستنساخ تحمّل حزمتها المضيفة داخل نفس العملية
    try {
      final maps = await File('/proc/self/maps').readAsString(encoding: latin1);
      final seen = <String>{};
      for (final m in RegExp(r'/data/app/(?:~~[^/]+/)?([A-Za-z0-9_.]+)-[^/\s]+/|/data/(?:user/\d+|data)/([A-Za-z0-9_.]+)/').allMatches(maps)) {
        final pkg = m.group(1) ?? m.group(2) ?? '';
        if (pkg.isEmpty || pkg == kPkg || !seen.add(pkg)) continue;
        if (_isCloneName(pkg)) {
          ind.add('مكتبات برنامج استنساخ محمّلة: $pkg');
          host = host.isEmpty ? pkg : host;
          sus = true;
        }
      }
    } catch (_) {}
  } catch (_) {}
  return <String, Object>{'sus': sus, 'host': host, 'ind': ind};
}

Future<bool> envSuspect() async {
  try {
    return (await cloneScan())['sus'] == true;
  } catch (_) {
    return false;
  }
}

/// بعد إزالة عضو من نقابة: يحدّث علامة «تعدد» (تبقى فقط لمن هو في نقابتين أو أكثر)
Future<void> syncMulti(String u) async {
  try {
    var n = 0;
    for (final x in groupsCache.keys.where((x) => groupKind(x) == 'main')) {
      if ((await ref('members/$x/$u').get()).value == true) n++;
    }
    if (n >= 2) {
      await ref('multi/$u').set(true);
    } else {
      await ref('multi/$u').remove();
    }
  } catch (_) {}
}

Future<void> prideRegen() async {
  try {
    final p = await ref('pride/$myUid').get();
    if (!p.exists || p.value is! num) return;
    final cur = (p.value as num).toInt();
    if (cur >= 100) return;
    final t = (await ref('prideTs/$myUid').get()).value;
    if (t is num && nowMs() - t.toInt() < 10800000) return;
    await db.ref().update(<String, Object?>{'pride/$myUid': cur + 1, 'prideTs/$myUid': ServerValue.timestamp});
  } catch (_) {}
}

Future<void> markSeen() async {
  if (myUid.isEmpty) return;
  prideRegen();
  envSuspect().then((s) async {
    if (!s) return;
    try {
      await ref('flags/$myUid').set(<String, Object?>{'e': 1, 'ts': ServerValue.timestamp});
    } catch (_) {}
  });
  try {
    await ref('seen/$myUid').set(<String, Object?>{'t': ServerValue.timestamp, 'b': kBuild});
  } catch (_) {}
  final key = nameKey(Session.me.name);
  if (key.isEmpty) return;
  final scopes = <String>[...mainGroups()];
  if (Session.isDev) scopes.add('_dev');
  for (final g in scopes) {
    try {
      await ref('nameIdx/$g/$key').set(myUid);
    } catch (_) {}
  }
}

/// هل اللقب مستخدم؟ (نقابة التسجيل + ألقاب المطورين في كل مكان)
Future<bool> nameTaken(String name, String guild, String uid) async {
  final key = nameKey(name);
  // ألقاب المطورين: يُمنع المطابق والمتشابه (لقب جزئي أو أطول منه)
  try {
    final dv = (await ref('nameIdx/_dev').get()).value;
    if (dv is Map) {
      for (final e in dv.entries) {
        if (e.value.toString() == uid) continue;
        final dk = e.key.toString();
        if (dk == key) return true;
        if (key.length >= 2 && dk.length >= 2 && dk.contains(key)) return true;
        if (dk.length >= 3 && key.contains(dk)) return true;
      }
    }
  } catch (_) {}
  final paths = <String>[if (guild.isNotEmpty) 'nameIdx/$guild/$key'];
  for (final p in paths) {
    try {
      final s = await ref(p).get();
      if (s.exists && s.value.toString() != uid) return true;
    } catch (_) {}
  }
  // الأعضاء القدامى قد لا يكونون في الفهرس: نفحص أسماء أعضاء النقابة الفعلية
  if (guild.isNotEmpty) {
    try {
      final mv = (await ref('members/$guild').get()).value;
      if (mv is Map) {
        final ids = mv.entries.where((e) => e.value == true && e.key.toString() != uid).map((e) => e.key.toString()).take(500).toList();
        final names = await Future.wait(ids.map((u) async {
          try {
            return (await ref('profiles/$u/name').get()).value?.toString() ?? '';
          } catch (_) {
            return '';
          }
        }));
        for (final n in names) {
          if (n.isNotEmpty && nameKey(n) == key) return true;
        }
      }
    } catch (_) {}
  }
  return false;
}

class SorterScreen extends StatefulWidget {
  const SorterScreen({super.key});

  @override
  State<SorterScreen> createState() => _SorterScreenState();
}

class _SorterScreenState extends State<SorterScreen> {
  final TextEditingController q = TextEditingController();
  bool loading = true;
  List<MapEntry<String, Prof>> users = [];
  Map<String, dynamic> seen = {};
  Set<String> online = {};
  Set<String> flagged = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final r = await Future.wait<DataSnapshot>([ref('profiles').get(), ref('seen').get(), ref('presence').get(), ref('flags').get()]);
      final pv = r[0].value;
      final sv = r[1].value;
      final ov = r[2].value;
      final fv = r[3].value;
      flagged = fv is Map ? fv.keys.map((e) => e.toString()).toSet() : {};
      final l = <MapEntry<String, Prof>>[];
      if (pv is Map) {
        pv.forEach((k, v) {
          if (v is Map) l.add(MapEntry(k.toString(), Prof.fromMap(Map<String, dynamic>.from(v))));
        });
      }
      seen = sv is Map ? Map<String, dynamic>.from(sv) : {};
      online = ov is Map ? ov.keys.map((e) => e.toString()).toSet() : {};
      int t(String u) {
        final s = seen[u];
        return s is Map && s['t'] is num ? (s['t'] as num).toInt() : 0;
      }
      l.sort((a, b) => t(b.key).compareTo(t(a.key)));
      users = l;
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => loading = false);
  }

  String _lastSeen(String u) {
    final sv = seen[u];
    final st = sv is Map && sv['t'] is num ? (sv['t'] as num).toInt() : 0;
    var join = 0;
    for (final e in users) {
      if (e.key == u) {
        join = e.value.ts;
        break;
      }
    }
    return lastSeenText(online: online.contains(u), seenTs: st, joinTs: join);
  }

  Widget _ver(String u) {
    final s = seen[u];
    final b = s is Map && s['b'] is num ? (s['b'] as num).toInt() : null;
    final latest = b != null && b >= kBuild;
    final txt = b == null ? 'نسخة قديمة' : (latest ? 'أحدث نسخة' : 'نسخة قديمة');
    final col = b == null ? const Color(0xFFFF6B6B) : (latest ? const Color(0xFF2EE07A) : const Color(0xFFFF6B6B));
    return Text(txt, style: TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.w800));
  }

  Future<void> _delete(String uid, Prof p) async {
    if (uid == Session.emp) {
      toast('لا يمكن حذف الإمبراطور', bad: true);
      return;
    }
    if (uid == myUid) {
      toast('لا يمكنك حذف حسابك', bad: true);
      return;
    }
    final isStaff = (await roleOf(uid)) != null;
    if (!mounted) return;
    final ok = await showAppSheet<bool>(context, (sc) => [
          Text('حذف «${p.name}» نهائياً؟', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 8),
          Text(isStaff ? 'هذا الحساب مطوّر! سيُحذف حسابه وكل بياناته ولن يعود إلا بإنشاء حساب جديد.' : 'سيُحذف اللقب والصورة ويُزال من النقابات ولن يعود إلا بإنشاء حساب جديد.', style: const TextStyle(color: kMu, height: 1.6)),
          const SizedBox(height: 14),
          AppButton('نعم، احذف', kind: 'r', onPressed: () => Navigator.of(sc).pop(true)),
          const SizedBox(height: 8),
          AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(sc).pop(false)),
        ]);
    if (ok != true) return;
    try {
      await ref('banned/$uid').set(true);
    } catch (_) {}
    try {
      // يتولى السيرفر مسح الحساب وكل بياناته (يشمل المطورين)
      await ref('delQueue/$uid').set(<String, Object?>{'by': myUid, 'ts': ServerValue.timestamp});
    } catch (e) {
      err(e);
      return;
    }
    toast('تم إرسال حذف ${p.name} ✅');
    if (mounted) setState(() => users.removeWhere((e) => e.key == uid));
  }

  @override
  Widget build(BuildContext context) {
    final f = normAr(q.text);
    final shown = users.where((e) => f.isEmpty || normAr(e.value.name).contains(f)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('الفرز (${users.length})'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(controller: q, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'بحث بالاسم', prefixIcon: Icon(Icons.search))),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (c, i) {
                    final e = shown[i];
                    return ListTile(
                      leading: UserAvatar(e.key, size: 42),
                      title: Text('${e.value.name}${flagged.contains(e.key) ? '  ⚠️' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Row(children: [_ver(e.key), const SizedBox(width: 10), Flexible(child: Text(_lastSeen(e.key), style: const TextStyle(color: kMu, fontSize: 11.5)))]),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)), onPressed: () => _delete(e.key, e.value)),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
