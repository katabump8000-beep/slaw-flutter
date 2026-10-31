import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'aljesi.dart';
import 'app_state.dart';
import 'config.dart';
import 'core.dart';
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
Future<void> markSeen() async {
  if (myUid.isEmpty) return;
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
  final paths = <String>['nameIdx/_dev/$key', if (guild.isNotEmpty) 'nameIdx/$guild/$key'];
  for (final p in paths) {
    try {
      final s = await ref(p).get();
      if (s.exists && s.value.toString() != uid) return true;
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
      final r = await Future.wait<DataSnapshot>([ref('profiles').get(), ref('seen').get(), ref('presence').get()]);
      final pv = r[0].value;
      final sv = r[1].value;
      final ov = r[2].value;
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
    if (online.contains(u)) return 'متصل الآن';
    final s = seen[u];
    if (s is! Map || s['t'] is! num) return 'آخر ظهور: غير معروف';
    final d = (DateTime.now().millisecondsSinceEpoch - (s['t'] as num).toInt()) ~/ 86400000;
    return d <= 0 ? 'آخر ظهور: اليوم' : 'آخر ظهور: منذ $d يوم';
  }

  Widget _ver(String u) {
    final s = seen[u];
    final b = s is Map && s['b'] is num ? (s['b'] as num).toInt() : null;
    final latest = b != null && b >= kBuild;
    final txt = b == null ? 'غير معروف' : (latest ? 'أحدث نسخة' : 'نسخة قديمة');
    final col = b == null ? kMu : (latest ? const Color(0xFF2EE07A) : const Color(0xFFFF6B6B));
    return Text(txt, style: TextStyle(color: col, fontSize: 11.5, fontWeight: FontWeight.w800));
  }

  Future<void> _delete(String uid, Prof p) async {
    final r = await roleOf(uid);
    if (r != null) {
      toast('لا يمكن حذف مطور أو إمبراطور', bad: true);
      return;
    }
    final ok = await showAppSheet<bool>(context, (sc) => [
          Text('حذف «${p.name}» نهائياً؟', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 8),
          const Text('سيُحذف اللقب والصورة ويُزال من النقابات ولن يعود إلا بإنشاء حساب جديد.', style: TextStyle(color: kMu, height: 1.6)),
          const SizedBox(height: 14),
          AppButton('نعم، احذف', kind: 'r', onPressed: () => Navigator.of(sc).pop(true)),
          const SizedBox(height: 8),
          AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(sc).pop(false)),
        ]);
    if (ok != true) return;
    final key = nameKey(p.name);
    final gs = <String>[...groupsCache.keys, '_dev'];
    for (final g in gs) {
      try {
        if (g != '_dev') await ref('members/$g/$uid').remove();
      } catch (_) {}
      try {
        final s = await ref('nameIdx/$g/$key').get();
        if (s.exists && s.value.toString() == uid) await ref('nameIdx/$g/$key').remove();
      } catch (_) {}
    }
    for (final path in ['avatars/$uid', 'seen/$uid', 'profiles/$uid']) {
      try {
        await ref(path).remove();
      } catch (_) {}
    }
    try {
      await ref('banned/$uid').set(true);
    } catch (_) {}
    toast('تم حذف ${p.name}');
    setState(() => users.removeWhere((e) => e.key == uid));
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
                      title: Text(e.value.name, style: const TextStyle(fontWeight: FontWeight.w800)),
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
