import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'data.dart';
import 'home.dart';
import 'invite.dart' show kInviteBase;
import 'tools.dart' show uidFromPid;
import 'widgets.dart';

/// «الروابط»: رابط نشر أي عضو + منع النشر + إعادة تعيين
class LinksScreen extends StatefulWidget {
  const LinksScreen({super.key});
  @override
  State<LinksScreen> createState() => _LinksState();
}

class _LinksState extends State<LinksScreen> {
  final c = TextEditingController();
  List<MapEntry<String, String>> hits = [];
  String? uid;
  String name = '';
  Map<String, String> codes = {}; // نقابة -> رمز
  Map<dynamic, dynamic>? ban;
  int count = 0;
  bool stopAll = false;
  bool busy = false;
  bool none = false;

  @override
  void initState() {
    super.initState();
    ref('config/pubStop').get().then((s) {
      if (mounted) setState(() => stopAll = s.value == true);
    }).catchError((_) {});
  }

  Future<void> _search() async {
    final q = normDigits(c.text.trim());
    if (q.isEmpty) return;
    setState(() {
      busy = true;
      uid = null;
      hits = [];
      none = false;
    });
    try {
      final u = q.length >= 20 ? q : await uidFromPid(q);
      if (u != null) {
        await _open(u);
      } else {
        final v = (await ref('profiles').get()).value;
        final l = <MapEntry<String, String>>[];
        if (v is Map) {
          v.forEach((k, x) {
            final n = x is Map ? (x['name'] ?? '').toString() : '';
            if (n.contains(c.text.trim())) l.add(MapEntry(k.toString(), n));
          });
        }
        hits = l.take(30).toList();
        none = hits.isEmpty;
      }
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _open(String u) async {
    setState(() => busy = true);
    try {
      name = (await prof(u)).name;
      final m = <String, String>{};
      for (final g in groupsCache.keys) {
        try {
          final s = await ref('pubPerm/$g/$u').get();
          if (s.exists) m[g] = s.value.toString();
        } catch (_) {}
      }
      codes = m;
      final b = (await ref('pubBan/$u').get()).value;
      ban = b is Map ? b : null;
      final n = (await ref('pubCount/$u').get()).value;
      count = n is num ? n.toInt() : 0;
      uid = u;
      hits = [];
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _toggleBan() async {
    try {
      if (ban == null) {
        await ref('pubBan/$uid').set(<String, Object?>{'by': myUid, 'n': Session.me.name, 'ts': ServerValue.timestamp});
        toast('تم منع $name من النشر ⛔');
      } else {
        await ref('pubBan/$uid').remove();
        toast('تم السماح بالنشر ✅');
      }
      await _open(uid!);
    } catch (e) {
      err(e);
    }
  }

  Future<void> _reset() async {
    final u = uid!;
    setState(() => busy = true);
    try {
      final rnd = Random.secure();
      for (final e in codes.entries) {
        try {
          await ref('refCodes/${e.value}').remove();
        } catch (_) {}
        String nc = '';
        for (var i = 0; i < 8 && nc.isEmpty; i++) {
          final cand = (10000000 + rnd.nextInt(90000000)).toString();
          if ((await ref('refCodes/$cand').get()).exists) continue;
          await ref('refCodes/$cand').set(<String, Object?>{'u': u, 'g': e.key});
          nc = cand;
        }
        if (nc.isNotEmpty) await ref('pubPerm/${e.key}/$u').set(nc);
      }
      toast('تم تغيير رابط النشر 🔄');
      await _open(u);
    } catch (e) {
      err(e);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _stopAll(bool v) async {
    try {
      if (v) {
        await ref('config/pubStop').set(true);
      } else {
        await ref('config/pubStop').remove();
      }
      setState(() => stopAll = v);
      toast(v ? 'تم إيقاف النشر لكل النقابات ⛔' : 'تم تشغيل النشر ✅');
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الروابط')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('إيقاف النشر لكل النقابات', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('لا يدخل أحد برابط، وتظهر «النشر متوقف حاليا»', style: TextStyle(color: kMu, fontSize: 12)),
          value: stopAll,
          onChanged: _stopAll,
        ),
        const Divider(),
        TextField(
          controller: c,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(hintText: 'اكتب اللقب أو الـID', suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search)),
        ),
        if (busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (none && !busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا يوجد حساب بهذا اللقب أو الـID', style: TextStyle(color: kMu)))),
        for (final h in hits) ListTile(title: Text(h.value), subtitle: Text(h.key, style: const TextStyle(color: kMu, fontSize: 11)), onTap: () => _open(h.key)),
        if (uid != null && !busy)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .28), borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                UserAvatar(uid!, size: 42),
                const SizedBox(width: 10),
                Expanded(child: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                Text('النشر: $count', style: const TextStyle(color: kMu)),
              ]),
              const SizedBox(height: 10),
              if (ban != null)
                Text('⛔ ممنوع من النشر (بواسطة ${(ban!['n'] ?? '').toString()})', style: const TextStyle(color: kRed, fontWeight: FontWeight.w800)),
              if (codes.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('لا يوجد له رابط نشر بعد', style: TextStyle(color: kMu))),
              for (final e in codes.entries) ...[
                const SizedBox(height: 6),
                Text(groupName(e.key), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .35), borderRadius: BorderRadius.circular(10)),
                  child: Text(ban != null ? 'تم حظرك من النشر من المطور: ${(ban!['n'] ?? '').toString()}' : '$kInviteBase?c=${e.value}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
                ),
                AppButton('نسخ الرابط', kind: 'g', compact: true, onPressed: () {
                  Clipboard.setData(ClipboardData(text: '$kInviteBase?c=${e.value}'));
                  toast('تم نسخ الرابط');
                }),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: AppButton(ban == null ? 'منع النشر' : 'السماح بالنشر', kind: ban == null ? 'r' : 'g', compact: true, onPressed: _toggleBan)),
                const SizedBox(width: 8),
                Expanded(child: AppButton('إعادة تعيين', compact: true, onPressed: codes.isEmpty ? null : _reset)),
              ]),
            ]),
          ),
      ]),
    );
  }
}

/// «العالقون»: حسابات سُجّلت ولم تدخل أي نقابة — حظر أو إدخال لنقابة
class StuckScreen extends StatefulWidget {
  const StuckScreen({super.key});
  @override
  State<StuckScreen> createState() => _StuckState();
}

class _StuckState extends State<StuckScreen> {
  List<MapEntry<String, Map<dynamic, dynamic>>> list = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final p = (await ref('profiles').get()).value;
      final inG = <String>{};
      for (final g in groupsCache.keys) {
        try {
          final m = (await ref('members/$g').get()).value;
          if (m is Map) m.forEach((k, v) {
            if (v != null && v != false) inG.add(k.toString());
          });
        } catch (_) {}
      }
      final roles = (await ref('roles').get()).value;
      final dev = roles is Map ? roles.keys.map((e) => e.toString()).toSet() : <String>{};
      final out = <MapEntry<String, Map<dynamic, dynamic>>>[];
      if (p is Map) {
        p.forEach((k, v) {
          final u = k.toString();
          if (v is! Map || inG.contains(u) || dev.contains(u) || u == Session.emp) return;
          out.add(MapEntry(u, v));
        });
      }
      out.sort((a, b) => ((b.value['ts'] as num?) ?? 0).compareTo((a.value['ts'] as num?) ?? 0));
      list = out;
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _ban(String u, String n) async {
    try {
      await ref('banned/$u').set(true);
      toast('تم حظر $n ⛔');
      setState(() => list.removeWhere((e) => e.key == u));
    } catch (e) {
      err(e);
    }
  }

  Future<void> _enter(String u, String n) async {
    final gs = groupsCache.keys.toList()..sort((a, b) => groupName(a).compareTo(groupName(b)));
    final pick = await showAppSheet<String>(context, (sc) => [
          Text('إدخال «$n» إلى نقابة', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          for (final g in gs) AppButton(groupName(g), kind: 'g', compact: true, onPressed: () => Navigator.of(sc).pop(g)),
        ]);
    if (pick == null) return;
    try {
      await ref('members/$pick/$u').set(true);
      toast('تم إدخال $n إلى ${groupName(pick)} ✅');
      setState(() => list.removeWhere((e) => e.key == u));
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('العالقون (${list.length})'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(child: Text('لا يوجد عالقون', style: TextStyle(color: kMu)))
              : ListView(children: [
                  const Padding(padding: EdgeInsets.all(12), child: Text('حسابات سُجّلت ولم تدخل أي نقابة', style: TextStyle(color: kMu, fontSize: 12))),
                  for (final e in list)
                    ListTile(
                      leading: UserAvatar(e.key, size: 40),
                      title: Text((e.value['name'] ?? '—').toString()),
                      subtitle: Text(e.key.substring(0, min(8, e.key.length)), style: const TextStyle(color: kMu, fontSize: 11)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(onPressed: () => _ban(e.key, (e.value['name'] ?? '').toString()), child: const Text('حظر', style: TextStyle(color: kRed))),
                        TextButton(onPressed: () => _enter(e.key, (e.value['name'] ?? '').toString()), child: const Text('إدخال')),
                      ]),
                    ),
                ]),
    );
  }
}

/// «الحماية القصوى»: تشغيل/إيقاف
Future<void> toggleMaxGuard() async {
  try {
    final on = (await ref('config/maxGuard').get()).value == true;
    if (on) {
      await ref('config/maxGuard').remove();
    } else {
      await ref('config/maxGuard').set(true);
    }
    toast(on ? 'تم إيقاف الحماية القصوى' : 'تم تشغيل الحماية القصوى 🛡 — حظر مباشر للمشتبه بهم');
  } catch (e) {
    err(e);
  }
}
