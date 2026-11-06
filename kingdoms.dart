import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'chat.dart';
import 'core.dart';
import 'data.dart';
import 'home.dart';
import 'sorter.dart' show syncMulti;
import 'widgets.dart';

/// إنشاء مملكة من عدة نقابات (للإمبراطور فقط)
class KingdomMakeScreen extends StatefulWidget {
  const KingdomMakeScreen({super.key});

  @override
  State<KingdomMakeScreen> createState() => _KingdomMakeState();
}

class _KingdomMakeState extends State<KingdomMakeScreen> {
  final TextEditingController nm = TextEditingController();
  final Set<String> sel = {};
  bool busy = false;

  @override
  void dispose() {
    nm.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    final name = nm.text.trim();
    if (name.isEmpty) {
      toast('اكتب اسم المملكة', bad: true);
      return;
    }
    if (sel.length < 2) {
      toast('اختر نقابتين على الأقل', bad: true);
      return;
    }
    setState(() => busy = true);
    try {
      final k = ref('kingdoms').push().key!;
      final up = <String, Object?>{
        'kingdoms/$k': <String, Object?>{
          'name': name,
          'by': myUid,
          'ts': ServerValue.timestamp,
          'g': <String, Object?>{for (final g in sel) g: true},
        },
        for (final g in sel) 'kingdomOf/$g': k,
      };
      await db.ref().update(up);
      toast('تم إنشاء مملكة $name 👑');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      err(e);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gs = groupsCache.entries.where((e) => e.value['kind'] == 'main').map((e) => e.key).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('دمج / إنشاء مملكة')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        TextField(controller: nm, maxLength: 40, decoration: const InputDecoration(hintText: 'اسم المملكة', counterText: '')),
        const SizedBox(height: 8),
        const Text('اختر النقابات التي ستنتمي للمملكة:', style: TextStyle(color: kMu)),
        for (final g in gs)
          CheckboxListTile(
            value: sel.contains(g),
            title: Text(groupName(g)),
            onChanged: (v) => setState(() => v == true ? sel.add(g) : sel.remove(g)),
          ),
        const SizedBox(height: 10),
        AppButton(busy ? '...' : 'مملكة', onPressed: busy ? null : _make),
      ]),
    );
  }
}

/// قائمة الممالك للمطورين والإمبراطور
class KingdomsScreen extends StatefulWidget {
  const KingdomsScreen({super.key});

  @override
  State<KingdomsScreen> createState() => _KingdomsState();
}

class _KingdomsState extends State<KingdomsScreen> {
  List<MapEntry<String, Map<String, dynamic>>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = (await ref('kingdoms').get()).value;
      final l = <MapEntry<String, Map<String, dynamic>>>[];
      if (v is Map) {
        v.forEach((k, x) {
          if (x is Map) l.add(MapEntry(k.toString(), Map<String, dynamic>.from(x)));
        });
      }
      rows = l;
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الممالك 👑')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? const Center(child: Text('لا توجد ممالك بعد', style: TextStyle(color: kMu)))
              : ListView(children: [
                  for (final e in rows)
                    ListTile(
                      leading: const Text('👑', style: TextStyle(fontSize: 24)),
                      title: Text((e.value['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text('${(e.value['g'] is Map ? (e.value['g'] as Map).length : 0)} نقابات', style: const TextStyle(color: kMu)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KingdomDetail(name: (e.value['name'] ?? '').toString(), guilds: e.value['g'] is Map ? (e.value['g'] as Map).keys.map((x) => x.toString()).toList() : <String>[]))),
                    ),
                ]),
    );
  }
}

class KingdomDetail extends StatelessWidget {
  final String name;
  final List<String> guilds;
  const KingdomDetail({super.key, required this.name, required this.guilds});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('مملكة $name')),
      body: ListView(children: [
        for (final g in guilds)
          ListTile(
            leading: GroupPhoto(g, size: 44),
            title: Text(groupName(g), style: const TextStyle(fontWeight: FontWeight.w800)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(gid: g))),
          ),
      ]),
    );
  }
}

/// سطر «أنت تنتمي إلى مملكة …» لوصف النقابة
class KingdomLine extends StatelessWidget {
  final String gid;
  const KingdomLine({super.key, required this.gid});

  Future<String> _name() async {
    try {
      final k = (await ref('kingdomOf/$gid').get()).value?.toString() ?? '';
      if (k.isEmpty) return '';
      return (await ref('kingdoms/$k/name').get()).value?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _name(),
      builder: (c, s) {
        final n = s.data ?? '';
        if (n.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Center(child: Text('👑 أنت تنتمي إلى مملكة $n', style: const TextStyle(color: Color(0xFFFFD54A), fontWeight: FontWeight.w900))),
        );
      },
    );
  }
}

/// إنشاء (أو تحديث) جروب ADMINS: كل المشرفين والمطورين والإمبراطور أعضاء فيه
Future<void> createAdminsGroup() async {
  const nm = '𝑨𝑫𝑴𝑰𝑵𝑺';
  try {
    toast('جارٍ تجهيز الجروب...');
    String? gid;
    for (final e in groupsCache.entries) {
      if ((e.value['name'] ?? '') == nm) gid = e.key;
    }
    final isNew = gid == null;
    gid ??= ref('groups').push().key!;
    final uids = <String>{if (Session.emp.isNotEmpty) Session.emp, myUid};
    for (final g in groupsCache.keys) {
      try {
        final v = (await ref('groupAdmins/$g').get()).value;
        if (v is Map) uids.addAll(v.keys.map((e) => e.toString()));
      } catch (_) {}
    }
    try {
      final pv = (await ref('profiles').get()).value;
      if (pv is Map) {
        for (final u in pv.keys.map((e) => e.toString())) {
          if (uids.contains(u)) continue;
          if (await roleOf(u) != null) uids.add(u);
        }
      }
    } catch (_) {}
    final up = <String, Object?>{};
    if (isNew) {
      up['groups/$gid'] = <String, Object?>{'name': nm, 'kind': 'main', 'adm': true, 'locked': false, 'desc': 'جروب الإدارة', 'ts': ServerValue.timestamp, 'by': myUid};
    }
    for (final u in uids) {
      up['members/$gid/$u'] = true;
      up['groupAdmins/$gid/$u'] = true;
    }
    await db.ref().update(up);
    for (final u in uids) {
      await syncMulti(u);
    }
    toast('تم تجهيز جروب ADMINS (${uids.length} عضو) ✅');
  } catch (e) {
    err(e);
  }
}
