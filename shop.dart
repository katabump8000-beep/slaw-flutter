import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth.dart';
import 'core.dart';
import 'data.dart';
import 'home.dart';
import 'war.dart';
import 'widgets.dart';

class _Item {
  final String id, e, n, d;
  final int p;
  final bool staff;
  const _Item(this.id, this.e, this.n, this.p, this.d, {this.staff = false});
}

const List<_Item> _items = [
  _Item('upg', '🎫', 'بطاقة ترقية', 500, 'تُستخدم من وصف نقابتك لرفع الهجوم أو الدفاع +1'),
  _Item('x2', '✖️2', 'مضاعفة الرسائل', 1500, 'كل رسالة تُحسب رسالتين حتى نزول الحسبة'),
  _Item('nick', '🏷', 'تغيير اللقب', 1000, 'غيّر لقبك (عربي فقط)'),
  _Item('sab', '💥', 'تخريب لقب', 1000, 'غيّر لقب عضو من نقابتك (عدا المشرفين)'),
  _Item('visit', '✈️', 'زيارة', 10000, 'زر نقابة أخرى لمدة 3 أيام'),
  _Item('war', '⚔️', 'إعلان حرب', 20000, 'للمشرفين فقط', staff: true),
];

class ShopRoute extends StatelessWidget {
  const ShopRoute({super.key});
  @override
  Widget build(BuildContext context) => const ShopScreen();
}

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  bool staff = false;

  @override
  void initState() {
    super.initState();
    _staff();
  }

  Future<void> _staff() async {
    var s = Session.isDev;
    if (!s) {
      for (final g in mainGroups()) {
        try {
          if ((await ref('groupAdmins/$g/$myUid').get()).exists) s = true;
        } catch (_) {}
      }
    }
    if (mounted) setState(() => staff = s);
  }

  Future<void> _buy(_Item it) async {
    try {
      if ((await balanceNow()) < it.p) {
        toast('رصيدك لا يكفي', bad: true);
        return;
      }
      const w = 'wallets';
      final W = '$w/$myUid/bal';
      switch (it.id) {
        case 'upg':
          await db.ref().update(<String, Object?>{'inv/$myUid/upg': ServerValue.increment(1), W: ServerValue.increment(-it.p)});
          toast('تم شراء بطاقة ترقية ✅');
          break;
        case 'x2':
          if ((await ref('boost/$myUid').get()).exists) {
            toast('المضاعفة مفعّلة بالفعل', bad: true);
            return;
          }
          await db.ref().update(<String, Object?>{'boost/$myUid': true, W: ServerValue.increment(-it.p)});
          toast('تم تفعيل مضاعفة الرسائل، اذهب وتفاعل ✅');
          break;
        case 'nick':
          return _nick(it);
        case 'sab':
          return _sab(it);
        case 'visit':
          return _visit(it);
        case 'war':
          return declareWarSheet(context);
      }
      await feedNote('shop', '🛒 ${Session.me.name} اشترى «${it.n}»', k: 'buy');
      if (mounted) setState(() {});
    } catch (e) {
      err(e);
    }
  }

  void _nameSheet(String title, Future<void> Function(String) ok) {
    final t = TextEditingController();
    String er = '';
    showAppSheet<void>(context, (sc) => [
          StatefulBuilder(builder: (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                TextField(controller: t, maxLength: 20, decoration: const InputDecoration(hintText: 'اللقب الجديد (عربي فقط)', counterText: '')),
                if (er.isNotEmpty) Text(er, style: const TextStyle(color: kRed)),
                const SizedBox(height: 8),
                AppButton('تأكيد', onPressed: () async {
                  final m = nameError(t.text);
                  if (m.isNotEmpty) {
                    set(() => er = m);
                    return;
                  }
                  Navigator.of(sc).pop();
                  await ok(t.text.trim().replaceAll(RegExp(r'\s+'), ' '));
                }),
              ])),
        ]);
  }

  void _nick(_Item it) => _nameSheet('🏷 تغيير لقبك', (n) async {
        try {
          await db.ref().update(<String, Object?>{'profiles/$myUid/name': n, 'wallets/$myUid/bal': ServerValue.increment(-it.p)});
          Session.me = Prof(n, Session.me.color, Session.me.gender, Session.me.ts);
          setProfCache(myUid, Session.me);
          toast('تم تغيير لقبك ✅');
          await feedNote('shop', '🏷 ${Session.me.name} غيّر لقبه', k: 'buy');
        } catch (e) {
          err(e);
        }
      });

  Future<void> _sab(_Item it) async {
    final mg = mainGroups();
    if (mg.isEmpty) {
      toast('تحتاج نقابة أولاً', bad: true);
      return;
    }
    Map<dynamic, dynamic> ms = {}, ad = {};
    try {
      final a = await ref('members/${mg.first}').get();
      final b = await ref('groupAdmins/${mg.first}').get();
      if (a.value is Map) ms = a.value as Map;
      if (b.value is Map) ad = b.value as Map;
    } catch (e) {
      err(e);
      return;
    }
    final ok = <String>[];
    for (final k in ms.keys) {
      final u = k.toString();
      if (u == myUid || ms[k] != true || ad[u] == true) continue;
      if (await roleOf(u) != null) continue;
      ok.add(u);
    }
    final ps = await Future.wait(ok.map(prof));
    if (!mounted) return;
    showAppSheet<void>(context, (sc) => [
          const Text('💥 اختر العضو', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ...[for (var i = 0; i < ok.length; i++) ListTile(leading: UserAvatar(ok[i], size: 34), title: Text(ps[i].name), onTap: () {
                Navigator.of(sc).pop();
                _nameSheet('اللقب الجديد لـ ${ps[i].name}', (n) async {
                  try {
                    await db.ref().update(<String, Object?>{'profiles/${ok[i]}/name': n, 'wallets/$myUid/bal': ServerValue.increment(-it.p)});
                    dropProf(ok[i]);
                    toast('تم ✅');
                    await feedNote('shop', '💥 ${Session.me.name} خرّب لقب ${ps[i].name}', k: 'buy');
                  } catch (e) {
                    err(e);
                  }
                });
              })],
        ]);
  }

  void _visit(_Item it) {
    final home = mainGroups();
    if (home.isEmpty) {
      toast('تحتاج نقابة أولاً', bad: true);
      return;
    }
    final others = groupsCache.keys.where((g) => groupKind(g) == 'main' && memCache[g] == null).toList();
    if (others.isEmpty) {
      toast('لا توجد نقابات أخرى', bad: true);
      return;
    }
    showAppSheet<void>(context, (sc) => [
          const Text('✈️ اختر النقابة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ...others.map((g) => AppButton(groupName(g), kind: 'g', onPressed: () async {
                Navigator.of(sc).pop();
                try {
                  await db.ref().update(<String, Object?>{
                    'members/$g/$myUid': 'v',
                    'visit/$myUid': <String, Object?>{'g': g, 'home': home.first, 'until': DateTime.now().millisecondsSinceEpoch + 3 * 86400000},
                    'wallets/$myUid/bal': ServerValue.increment(-it.p),
                  });
                  memCache[g] = 'v';
                  await ref('messages/$g').push().set(<String, Object?>{
                    'from': myUid, 'type': 'sys', 'k': 'visit',
                    'text': '✈️ لقد انضم ${Session.me.name} من نقابة ${groupName(home.first)} — زائر',
                    'ts': ServerValue.timestamp,
                  });
                  await feedNote('news', '✈️ ${Session.me.name} يزور نقابة ${groupName(g)}', k: 'buy');
                  toast('تمت الزيارة لمدة 3 أيام ✅');
                } catch (e) {
                  err(e);
                }
              })),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🛒 المتجر'), actions: const [Padding(padding: EdgeInsets.all(10), child: BalanceChip())]),
      body: ListView(children: [
        for (final it in _items)
          if (!it.staff || staff)
            ListTile(
              leading: CircleAvatar(backgroundColor: accentA(context, .18), child: Text(it.e, style: const TextStyle(fontSize: 18))),
              title: Text(it.n, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(it.d, style: const TextStyle(color: kMu, fontSize: 12)),
              trailing: SizedBox(width: 92, child: AppButton(fmtN(it.p), compact: true, onPressed: () => _buy(it))),
            ),
      ]),
    );
  }
}

/// عودة الزائر لنقابته بعد انتهاء المدة
Future<void> checkVisitExpiry() async {
  try {
    final v = (await ref('visit/$myUid').get()).value;
    if (v is! Map) return;
    final until = (v['until'] as num?)?.toInt() ?? 0;
    if (until < DateTime.now().millisecondsSinceEpoch) {
      await db.ref().update(<String, Object?>{'members/${v['g']}/$myUid': null, 'visit/$myUid': null});
      memCache.remove((v['g'] ?? '').toString());
      toast('انتهت زيارتك، عدت إلى نقابتك');
    }
  } catch (_) {}
}
