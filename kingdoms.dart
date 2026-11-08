import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'chat.dart';
import 'core.dart';
import 'data.dart';
import 'home.dart';
import 'sorter.dart' show syncMulti;
import 'widgets.dart';

/// اختيار نقابات: بحث + مربعات (للإنشاء وللإضافة)
class GuildPickScreen extends StatefulWidget {
  final String title;
  final String actionLabel;
  final Set<String> exclude;
  final Future<void> Function(Set<String> sel) onDone;
  const GuildPickScreen({super.key, required this.title, required this.actionLabel, required this.onDone, this.exclude = const {}});

  @override
  State<GuildPickScreen> createState() => _GuildPickState();
}

class _GuildPickState extends State<GuildPickScreen> {
  final Set<String> sel = {};
  String q = '';
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final all = groupsCache.entries.where((e) => e.value['kind'] == 'main' && e.value['adm'] != true && !widget.exclude.contains(e.key)).map((e) => e.key).toList();
    final shown = q.isEmpty ? all : all.where((g) => groupName(g).contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث عن اسم نقابة'), onChanged: (v) => setState(() => q = v.trim())),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Align(alignment: Alignment.centerRight, child: Text('عدد النقابات: ${all.length}', style: const TextStyle(color: kMu, fontSize: 12.5)))),
        Expanded(
          child: ListView(children: [
            for (final g in shown)
              CheckboxListTile(
                value: sel.contains(g),
                secondary: GroupPhoto(g, size: 38),
                title: Text(groupName(g), style: const TextStyle(fontWeight: FontWeight.w700)),
                onChanged: (v) => setState(() => v == true ? sel.add(g) : sel.remove(g)),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AppButton(busy ? '...' : '${widget.actionLabel} (${sel.length})', glow: true, onPressed: (busy || sel.isEmpty)
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await widget.onDone(Set<String>.from(sel));
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  }),
          ),
        ),
      ]),
    );
  }
}

/// إنشاء مملكة: اختيار النقابات ثم اسم المملكة
class KingdomMakeScreen extends StatelessWidget {
  const KingdomMakeScreen({super.key});

  Future<void> _create(BuildContext context, Set<String> sel) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('اسم المملكة رجاءا...'),
        content: TextField(controller: c, maxLength: 40, decoration: const InputDecoration(hintText: 'اسم المملكة')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('التالي')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final used = <String>[];
      for (final g in sel) {
        if ((await ref('kingdomOf/$g').get()).exists) used.add(groupName(g));
      }
      if (used.isNotEmpty) {
        toast('هذه النقابات في مملكة أخرى: ${used.join('، ')}', bad: true);
        return;
      }
      final k = ref('kingdoms').push().key!;
      await db.ref().update(<String, Object?>{
        'kingdoms/$k': <String, Object?>{'name': name, 'by': myUid, 'ts': ServerValue.timestamp, 'g': <String, Object?>{for (final g in sel) g: true}},
        for (final g in sel) 'kingdomOf/$g': k,
      });
      toast('تم إنشاء مملكة $name 👑');
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) => GuildPickScreen(title: 'إنشاء مملكة', actionLabel: 'انشاء مملكة', onDone: (s) => _create(context, s));
}

/// قائمة الممالك (للمطورين والإمبراطور) + زر +
class KingdomsScreen extends StatelessWidget {
  const KingdomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الممالك 👑'), actions: [
        IconButton(tooltip: 'مملكة جديدة', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const KingdomMakeScreen())), icon: const Icon(Icons.add_circle_outline)),
      ]),
      body: const KingdomList(),
    );
  }
}

class KingdomList extends StatelessWidget {
  const KingdomList({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('kingdoms').onValue,
      builder: (c, s) {
        final v = s.data?.snapshot.value;
        final rows = <MapEntry<String, Map<dynamic, dynamic>>>[];
        if (v is Map) {
          v.forEach((k, x) {
            if (x is Map) rows.add(MapEntry(k.toString(), x));
          });
        }
        if (rows.isEmpty) return const Center(child: Text('لا توجد ممالك بعد', style: TextStyle(color: kMu)));
        return ListView(children: [
          for (final e in rows)
            ListTile(
              leading: const Text('👑', style: TextStyle(fontSize: 24)),
              title: Text((e.value['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KingdomDetail(kid: e.key))),
            ),
        ]);
      },
    );
  }
}

/// بطاقة «الممالك» في الرئيسية (للمطورين والإمبراطور): أسماء الممالك فقط
class KingdomsCard extends StatelessWidget {
  const KingdomsCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Session.isDev) return const SizedBox.shrink();
    return StreamBuilder<DatabaseEvent>(
      stream: ref('kingdoms').onValue,
      builder: (c, s) {
        final v = s.data?.snapshot.value;
        final rows = <MapEntry<String, String>>[];
        if (v is Map) {
          v.forEach((k, x) {
            if (x is Map) rows.add(MapEntry(k.toString(), (x['name'] ?? '').toString()));
          });
        }
        if (rows.isEmpty) return const SizedBox.shrink();
        return SecCard(title: 'الممالك', children: [
          for (final e in rows)
            ListTile(
              leading: const Text('👑', style: TextStyle(fontSize: 22)),
              title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KingdomDetail(kid: e.key))),
            ),
        ]);
      },
    );
  }
}

/// تفاصيل مملكة: نقاباتها + قلم التعديل في الزاوية
class KingdomDetail extends StatelessWidget {
  final String kid;
  const KingdomDetail({super.key, required this.kid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('kingdoms/$kid').onValue,
      builder: (c, s) {
        final v = s.data?.snapshot.value;
        final m = v is Map ? v : <dynamic, dynamic>{};
        final guilds = m['g'] is Map ? (m['g'] as Map).keys.map((x) => x.toString()).toList() : <String>[];
        return Scaffold(
          appBar: AppBar(title: Text('مملكة ${m['name'] ?? ''}'), actions: [
            if (Session.isDev) IconButton(tooltip: 'تعديل', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KingdomEditScreen(kid: kid))), icon: const Icon(Icons.edit_outlined)),
          ]),
          body: guilds.isEmpty
              ? const Center(child: Text('لا توجد نقابات في هذه المملكة', style: TextStyle(color: kMu)))
              : ListView(children: [
                  for (final g in guilds)
                    ListTile(
                      leading: GroupPhoto(g, size: 44),
                      title: Text(groupName(g), style: const TextStyle(fontWeight: FontWeight.w800)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(gid: g))),
                    ),
                ]),
        );
      },
    );
  }
}

/// تعديل مملكة: فصل / اضافة نقابة / ابلاغ لمشرفيها
class KingdomEditScreen extends StatelessWidget {
  final String kid;
  const KingdomEditScreen({super.key, required this.kid});

  Future<void> _detach(BuildContext context, String g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('فصل ${groupName(g)}؟'),
        content: const Text('ستصبح النقابة مفصولة ومعزولة ولن تظهر في المملكة إلى أن تُضمّ مجدداً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('فصل')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.ref().update(<String, Object?>{'kingdoms/$kid/g/$g': null, 'kingdomOf/$g': null});
      toast('تم فصل النقابة ✅');
    } catch (e) {
      err(e);
    }
  }

  Future<void> _add(BuildContext context, Set<String> cur) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GuildPickScreen(
        title: 'اضافة نقابة',
        actionLabel: 'اضافة',
        exclude: cur,
        onDone: (sel) async {
          try {
            final used = <String>[];
            for (final g in sel) {
              if ((await ref('kingdomOf/$g').get()).exists) used.add(groupName(g));
            }
            if (used.isNotEmpty) {
              toast('هذه النقابات في مملكة أخرى: ${used.join('، ')}', bad: true);
              return;
            }
            await db.ref().update(<String, Object?>{for (final g in sel) 'kingdoms/$kid/g/$g': true, for (final g in sel) 'kingdomOf/$g': kid});
            toast('تمت الإضافة ✅');
            if (context.mounted) Navigator.of(context).pop();
          } catch (e) {
            err(e);
          }
        },
      ),
    ));
  }

  Future<void> _report(BuildContext context) async {
    final c = TextEditingController();
    final txt = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('ابلاغ'),
        content: TextField(controller: c, maxLength: 300, maxLines: 4, decoration: const InputDecoration(hintText: 'رجاءا قم بوضع الرسالة التي سوف تصل لجميع مشرفين هذه المملكة.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('تم')),
        ],
      ),
    );
    if (txt == null || txt.isEmpty) return;
    try {
      await ref('kingdomReq/${ref('kingdomReq').push().key}').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 'kid': kid, 't': txt});
      toast('تم إرسال الرسالة لمشرفي المملكة ✅', accent: true);
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('kingdoms/$kid').onValue,
      builder: (c, s) {
        final v = s.data?.snapshot.value;
        final m = v is Map ? v : <dynamic, dynamic>{};
        final guilds = m['g'] is Map ? (m['g'] as Map).keys.map((x) => x.toString()).toList() : <String>[];
        return Scaffold(
          appBar: AppBar(title: Text('تعديل ${m['name'] ?? ''}')),
          body: ListView(padding: const EdgeInsets.all(14), children: [
            const Text('يمكنك فصل النقابة عن هذه المملكة من خلال زر: فصل.', style: TextStyle(color: kMu, height: 1.7, fontSize: 13)),
            const SizedBox(height: 8),
            for (final g in guilds)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
                child: Row(children: [
                  GroupPhoto(g, size: 40),
                  const SizedBox(width: 10),
                  Expanded(child: Text(groupName(g), style: const TextStyle(fontWeight: FontWeight.w800))),
                  SizedBox(width: 80, child: AppButton('فصل', kind: 'r', compact: true, onPressed: () => _detach(context, g))),
                ]),
              ),
            const SizedBox(height: 10),
            AppButton('اضافة نقابة', kind: 'g', onPressed: () => _add(context, guilds.toSet())),
            const SizedBox(height: 8),
            AppButton('ابلاغ', glow: true, onPressed: () => _report(context)),
          ]),
        );
      },
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
