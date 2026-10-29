import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'home.dart';
import 'war.dart';
import 'widgets.dart';

List<String> _mains() => groupsCache.keys.where((g) => groupKind(g) == 'main').toList();

/// تعديل مستوى هجوم/دفاع نقابة (للإمبراطور)
Future<void> editGuildLevels(BuildContext context) async {
  final ids = _mains();
  if (ids.isEmpty) {
    toast('لا توجد نقابات', bad: true);
    return;
  }
  var g = ids.first;
  final a = TextEditingController();
  final d = TextEditingController();
  Future<void> load(String id) async {
    try {
      final v = (await ref('guildStats/$id').get()).value;
      if (v is Map) {
        a.text = '${(v['atk'] as num?)?.toInt() ?? 1}';
        d.text = '${(v['def'] as num?)?.toInt() ?? 1}';
      }
    } catch (_) {}
  }
  await load(g);
  if (!context.mounted) return;
  await showAppSheet<void>(context, (sc) => [
        StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('تعديل مستوى النقابة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            DropdownButton<String>(
              isExpanded: true,
              value: g,
              items: [for (final x in ids) DropdownMenuItem(value: x, child: Text(groupName(x)))],
              onChanged: (v) async {
                if (v == null) return;
                g = v;
                await load(v);
                set(() {});
              },
            ),
            TextField(controller: a, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'مستوى الهجوم')),
            const SizedBox(height: 8),
            TextField(controller: d, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'مستوى الدفاع')),
            const SizedBox(height: 12),
            AppButton('حفظ', onPressed: () async {
              final x = int.tryParse(normDigits(a.text)), y = int.tryParse(normDigits(d.text));
              if (x == null || y == null || x < 0 || y < 0 || x > 9999 || y > 9999) {
                toast('أرقام من 0 إلى 9999', bad: true);
                return;
              }
              try {
                await db.ref().update(<String, Object?>{'guildStats/$g/atk': x, 'guildStats/$g/def': y});
                if (sc.mounted) Navigator.of(sc).pop();
                toast('تم التعديل ✅');
              } catch (e) {
                err(e);
              }
            }),
          ]);
        }),
      ]);
}

/// دمج نقابتين أو أكثر في نقابة واحدة باسم جديد (للإمبراطور)
Future<void> mergeGuilds(BuildContext context) async {
  final ids = _mains();
  if (ids.length < 2) {
    toast('تحتاج نقابتين على الأقل', bad: true);
    return;
  }
  final sel = <String>{};
  final nm = TextEditingController();
  await showAppSheet<void>(context, (sc) => [
        StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('دمج نقابات', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const Text('اختر نقابتين أو ثلاث. تُنقل كل الأعضاء والمشرفين إلى النقابة الأولى المحددة وتُحذف الباقية.', style: TextStyle(color: kMu, fontSize: 12, height: 1.6)),
            for (final g in ids)
              CheckboxListTile(
                dense: true,
                value: sel.contains(g),
                title: Text(groupName(g)),
                onChanged: (v) => set(() => v == true ? sel.add(g) : sel.remove(g)),
              ),
            TextField(controller: nm, maxLength: 40, decoration: const InputDecoration(hintText: 'الاسم الجديد للنقابة', counterText: '')),
            const SizedBox(height: 8),
            AppButton('دمج', kind: 'r', onPressed: () async {
              final name = nm.text.trim();
              if (sel.length < 2 || sel.length > 3 || name.isEmpty) {
                toast('اختر 2 أو 3 نقابات واكتب الاسم', bad: true);
                return;
              }
              final list = sel.toList();
              final t = list.first;
              try {
                final up = <String, Object?>{'groups/$t/name': name};
                for (final g in list.skip(1)) {
                  final ms = (await ref('members/$g').get()).value;
                  if (ms is Map) {
                    ms.forEach((u, v) {
                      up['members/$t/$u'] = v;
                      up['members/$g/$u'] = null;
                    });
                  }
                  final ad = (await ref('groupAdmins/$g').get()).value;
                  if (ad is Map) {
                    ad.forEach((u, v) {
                      up['groupAdmins/$t/$u'] = true;
                      up['groupAdmins/$g/$u'] = null;
                    });
                  }
                  up['guildStats/$g'] = null;
                  up['groups/$g'] = null;
                }
                await db.ref().update(up);
                if (sc.mounted) Navigator.of(sc).pop();
                toast('تم الدمج ✅');
              } catch (e) {
                err(e);
              }
            }),
          ]);
        }),
      ]);
}

Future<List<List<String>>> _roster(String g, bool admins) async {
  final out = <List<String>>[];
  try {
    final ad = (await ref('groupAdmins/$g').get()).value;
    final admSet = ad is Map ? ad.keys.map((e) => e.toString()).toSet() : <String>{};
    final ms = (await ref('members/$g').get()).value;
    if (ms is Map) {
      final ids = ms.keys.map((e) => e.toString()).where((u) => ms[u] == true && u != Session.emp && admSet.contains(u) == admins).take(12).toList();
      final ps = await Future.wait(ids.map(prof));
      for (var i = 0; i < ids.length; i++) {
        out.add([ids[i], ps[i].name]);
      }
    }
  } catch (_) {}
  return out;
}

/// زر «تجارب»: يعرض عرض إعلان الحرب والعرض الأسطوري محلياً عندك فقط
Future<void> warTrial(BuildContext context) async {
  final ids = _mains();
  if (ids.length < 2) {
    toast('تحتاج نقابتين على الأقل', bad: true);
    return;
  }
  var a = ids[0], d = ids[1];
  var attackWins = true;
  await showAppSheet<void>(context, (sc) => [
        StatefulBuilder(builder: (c, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('تجربة عرض الحرب (لا يظهر لأحد غيرك)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('النقابة المهاجمة', style: TextStyle(color: kMu, fontSize: 12)),
            DropdownButton<String>(isExpanded: true, value: a, items: [for (final x in ids) DropdownMenuItem(value: x, child: Text(groupName(x)))], onChanged: (v) => set(() => a = v ?? a)),
            const Text('النقابة المدافعة', style: TextStyle(color: kMu, fontSize: 12)),
            DropdownButton<String>(isExpanded: true, value: d, items: [for (final x in ids) DropdownMenuItem(value: x, child: Text(groupName(x)))], onChanged: (v) => set(() => d = v ?? d)),
            SwitchListTile(value: attackWins, title: const Text('فوز المهاجم'), onChanged: (v) => set(() => attackWins = v)),
            AppButton('تشغيل التجربة', onPressed: () async {
              if (a == d) {
                toast('اختر نقابتين مختلفتين', bad: true);
                return;
              }
              Navigator.of(sc).pop();
              final now = DateTime.now().millisecondsSinceEpoch;
              final f = <String, dynamic>{
                'ag': a,
                'dg': d,
                'an': groupName(a),
                'dn': groupName(d),
                'by': myUid,
                'bn': Session.me.name,
                'ts': now,
                'rs': now,
                'res': attackWins ? 'a' : 'd',
                'win': groupName(attackWins ? a : d),
                'lose': groupName(attackWins ? d : a),
                'rA': <String, dynamic>{'adm': await _roster(a, true), 'mem': await _roster(a, false), 'roy': <List<String>>[if (Session.emp.isNotEmpty) [Session.emp, 'الإمبراطور']]},
                'rD': <String, dynamic>{'adm': await _roster(d, true), 'mem': await _roster(d, false)},
              };
              if (!context.mounted) return;
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WarIntroScreen(f: f)));
              if (!context.mounted) return;
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WarEpicScreen(f: Map<String, dynamic>.from(jsonDecode(jsonEncode(f)) as Map))));
            }),
          ]);
        }),
      ]);
}
