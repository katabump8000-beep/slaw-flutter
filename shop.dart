import 'dart:async';
import 'servertime.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth.dart';
import 'core.dart';
import 'data.dart';
import 'home.dart';
import 'vip.dart';
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
  _Item('sab', '💥', 'تخريب لقب', 1000, 'غيّر لقب عضو من نقابتك (عدا المشرفين). يعود لقبه تلقائياً بعد 3 أيام'),
  _Item('shield', '🛡', 'درع', 3000, 'لمدة 3 أيام لا يستطيع أحد تخريب لقبك'),
  _Item('move', '🧭', 'نقل', 5000, 'انتقل إلى نقابة أخرى فوراً'),
  _Item('war', '⚔️', 'إعلان حرب', 10000, 'للمشرفين فقط', staff: true),
  _Item('vip_galaxy', '👑', '𝑽𝑰𝑷 المجرة', 0, 'شهب ونجوم وتوهج أزرق يتدرج إلى البنفسجي'),
  _Item('vip_emerald', '🌸', '𝑽𝑰𝑷 زمردة', 0, 'أوراق ورود راقية بألوان واجهتك'),
  _Item('vip_thunder', '⚡', '𝑽𝑰𝑷 الصاعقة', 0, 'برق ورعد وأسلاك كهرباء، وألوان الواجهة زرقاء ثابتة'),
  _Item('vip_royal', '🍷', '𝑽𝑰𝑷 الملكي', 0, 'خمري ملكي بحواف ذهبية وأوراق خريف متساقطة'),
];

final Map<String, int> _ovr = {};
int _pr(_Item it) => _ovr[it.id] ?? it.p;

Future<void> loadShopPrices() async {
  try {
    final v = (await ref('shopPrices').get()).value;
    _ovr.clear();
    if (v is Map) {
      v.forEach((k, x) {
        if (x is num) _ovr[k.toString()] = x.toInt();
      });
    }
  } catch (_) {}
}

Future<void> editShopPrices(BuildContext context) async {
  await loadShopPrices();
  final cs = <String, TextEditingController>{for (final it in _items) it.id: TextEditingController(text: '${_pr(it)}')};
  if (!context.mounted) return;
  await showAppSheet<void>(context, (sc) => [
        const Text('أسعار المتجر', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        for (final it in _items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text('${it.e} ${it.n}')),
              SizedBox(width: 110, child: TextField(controller: cs[it.id], keyboardType: TextInputType.number, textAlign: TextAlign.center)),
            ]),
          ),
        const SizedBox(height: 10),
        AppButton('حفظ', onPressed: () async {
          final up = <String, Object?>{};
          for (final it in _items) {
            final n = int.tryParse(normDigits(cs[it.id]!.text));
            if (n != null && n >= 0) up['shopPrices/${it.id}'] = n;
          }
          try {
            await db.ref().update(up);
            await loadShopPrices();
            toast('تم حفظ الأسعار ✅');
            if (sc.mounted) Navigator.of(sc).pop();
          } catch (e) {
            err(e);
          }
        }),
      ]);
}

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
    loadShopPrices().then((_) {
      if (mounted) setState(() {});
    });
    initVip().then((_) {
      if (mounted) setState(() {});
    });
    loadShield();
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
      if ((await balanceNow()) < _pr(it)) {
        toast('رصيدك لا يكفي', bad: true);
        return;
      }
      if (it.id.startsWith('vip_')) return _buyVip(it);
      const w = 'wallets';
      final W = '$w/$myUid/bal';
      switch (it.id) {
        case 'upg':
          await db.ref().update(<String, Object?>{'inv/$myUid/upg': ServerValue.increment(1), W: ServerValue.increment(-_pr(it))});
          toast('تم شراء بطاقة ترقية ✅');
          break;
        case 'x2':
          if ((await ref('boost/$myUid').get()).exists) {
            toast('المضاعفة مفعّلة بالفعل', bad: true);
            return;
          }
          await db.ref().update(<String, Object?>{'boost/$myUid': true, W: ServerValue.increment(-_pr(it))});
          toast('تم تفعيل مضاعفة الرسائل، اذهب وتفاعل ✅');
          break;
        case 'nick':
          return _nick(it);
        case 'sab':
          return _sab(it);
        case 'shield':
          return _shield(it);
        case 'move':
          return _move(it);
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

  /// شراء VIP عبر السيرفر (يخصم الرصيد ويسجّل الملكية بشكل آمن)
  Future<void> _buyVip(_Item it) async {
    final id = it.id.substring(4);
    if (vipOwned.contains(id)) {
      toast('تملك هذا التأثير بالفعل، فعّله من ممتلكاتي', bad: true);
      return;
    }
    final rid = ref('vipReq').push().key!;
    try {
      await ref('vipReq/$rid').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 'id': id}).timeout(const Duration(seconds: 8));
    } catch (e) {
      err(e);
      return;
    }
    var ok = false;
    for (var i = 0; i < 16 && !ok; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        ok = (await ref('vips/$myUid/$id').get()).exists;
      } catch (_) {}
    }
    if (!mounted) return;
    if (!ok) {
      toast('تعذر إتمام الشراء (تحقق من رصيدك)', bad: true);
      return;
    }
    vipOwned.add(id);
    showAppSheet<void>(context, (sc) => [
          const Text('تم شراء التأثير يمكنك رؤيته في الاعدادات في ممتلكاتي!', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, height: 1.8)),
          AppButton('ممتلكاتي', onPressed: () {
            Navigator.of(sc).pop();
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyVipsScreen()));
          }),
        ]);
    setState(() {});
  }

  /// طلب للسيرفر (shopReq) وانتظار الرد (shopRes). يرجع '' عند النجاح أو رمز الخطأ
  Future<String> _shopCall(String k, Map<String, Object?> extra) async {
    final rid = ref('shopReq').push().key!;
    try {
      await ref('shopReq/$rid').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 'k': k, ...extra}).timeout(const Duration(seconds: 8));
    } catch (e) {
      err(e);
      return 'net';
    }
    for (var i = 0; i < 24; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      try {
        final v = (await ref('shopRes/$myUid').get()).value;
        if (v is Map && v['id'] == rid) return v['ok'] == true ? '' : (v['err'] ?? 'err').toString();
      } catch (_) {}
    }
    return 'timeout';
  }

  String _errText(String e) {
    switch (e) {
      case 'low':
        return 'رصيدك لا يكفي';
      case 'dup':
        return 'الدرع فعّال بالفعل';
      case 'shield':
        return 'هذا العضو محمي بدرع 🛡';
      case 'prot':
        return 'لا يمكن تخريب لقب المشرفين أو الرتب';
      case 'bad':
        return 'اللقب غير صالح';
      case 'group':
        return 'النقابة غير متاحة';
      case 'same':
        return 'أنت في هذه النقابة بالفعل';
      case 'timeout':
        return 'السيرفر لا يستجيب، حاول لاحقاً';
      default:
        return 'تعذر التنفيذ';
    }
  }

  Future<void> _shield(_Item it) async {
    final e = await _shopCall('shield', {});
    if (e.isNotEmpty) {
      toast(_errText(e), bad: true);
      return;
    }
    toast('تم تفعيل الدرع لمدة 3 أيام 🛡');
    await loadShield();
  }

  int shieldUntil = 0;
  Future<void> loadShield() async {
    try {
      final v = (await ref('shield/$myUid/until').get()).value;
      if (mounted) setState(() => shieldUntil = v is num ? v.toInt() : 0);
    } catch (_) {}
  }

  void _move(_Item it) {
    final home = mainGroups();
    final others = groupsCache.keys.where((g) => groupKind(g) == 'main' && !home.contains(g)).toList();
    if (others.isEmpty) {
      toast('لا توجد نقابات أخرى', bad: true);
      return;
    }
    var q = '';
    showAppSheet<void>(context, (sc) => [
          StatefulBuilder(builder: (c, set) {
            final list = others.where((g) => groupName(g).contains(q)).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('🧭 اختر النقابة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              TextField(decoration: const InputDecoration(hintText: 'ابحث عن نقابة', prefixIcon: Icon(Icons.search)), onChanged: (v) => set(() => q = v.trim())),
              const SizedBox(height: 6),
              ...list.map((g) => ListTile(
                    title: Text(groupName(g)),
                    onTap: () async {
                      final sure = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          content: const Text('هل انت واثق من أنك تريد الانتقال الى هذه النقابة والخروج من نقابتك؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('الغاء')),
                            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('نعم')),
                          ],
                        ),
                      );
                      if (sure != true) return;
                      if (sc.mounted) Navigator.of(sc).pop();
                      final e = await _shopCall('move', {'g': g});
                      if (e.isNotEmpty) {
                        toast(_errText(e), bad: true);
                        return;
                      }
                      memCache.clear();
                      toast('تم نقلك إلى ${groupName(g)} ✅ — اسحب الصفحة الرئيسية للتحديث');
                      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                  )),
            ]);
          }),
        ]);
  }

  /// فقاعة شرح (!): تظهر النص تدريجياً
  void _info(_Item it) {
    final long = <String, String>{
      'upg': 'بطاقة الترقية تُستخدم من وصف نقابتك لرفع هجوم نقابتك أو دفاعها بمقدار +1 في كل مرة.',
      'x2': 'مضاعفة الرسائل: كل رسالة ترسلها تُحسب رسالتين في الحسبة إلى أن تنزل الحسبة التالية، فيزيد تصدّرك وتفاعلك.',
      'nick': 'تغيير اللقب: تغيّر لقبك بلقب عربي جديد غير مستخدم. يبقى كل شيء آخر كما هو.',
      'sab': 'تخريب لقب: تغيّر لقب عضو من نقابتك (عدا المشرفين والرتب) لمدة 3 أيام ثم يعود لقبه تلقائياً. لا يعمل على من يملك درعاً.',
      'shield': 'الدرع: لمدة 3 أيام لا يستطيع أي عضو تخريب لقبك. يظهر لك عدّاد الأيام المتبقية.',
      'move': 'نقل: تنتقل فوراً إلى أي نقابة تختارها وتغادر نقابتك. تبقى ألقابك ورتبك كما هي ويصل ترحيب في نقابتك الجديدة ووداع في القديمة.',
      'war': 'إعلان حرب: للمشرفين فقط. تبدأ الحرب بعد ساعة وتُحسم تلقائياً.',
    };
    final text = it.id.startsWith('vip_') ? 'تأثير VIP يغيّر مظهر التطبيق عندك. يمكنك تجربته مرة واحدة لمدة 3 دقائق بزر العين، وبعد الشراء تفعّله من الإعدادات ← ممتلكاتي.' : (long[it.id] ?? it.d);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (d) => Align(
        alignment: Alignment.center,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF14171C), borderRadius: BorderRadius.circular(16), border: Border.all(color: kMu.withAlpha(120))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${it.e} ${it.n}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 8),
              _TypeText(text),
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () => Navigator.pop(d), child: const Text('حسناً'))),
            ]),
          ),
        ),
      ),
    );
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
          await db.ref().update(<String, Object?>{'profiles/$myUid/name': n, 'wallets/$myUid/bal': ServerValue.increment(-_pr(it))});
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
                  final e = await _shopCall('sab', {'x': ok[i], 't': n});
                  if (e.isNotEmpty) {
                    toast(_errText(e), bad: true);
                    return;
                  }
                  dropProf(ok[i]);
                  toast('تم تخريب لقبه لمدة 3 أيام ✅');
                  await feedNote('shop', '💥 ${Session.me.name} خرّب لقب ${ps[i].name}', k: 'buy');
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
                    'visit/$myUid': <String, Object?>{'g': g, 'home': home.first, 'until': nowMs() + 3 * 86400000},
                    'wallets/$myUid/bal': ServerValue.increment(-_pr(it)),
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
      appBar: AppBar(title: const Text('🛒 المتجر'), actions: [
        if (Session.isDev)
          IconButton(
            icon: const Icon(Icons.edit_note),
            onPressed: () async {
              await editShopPrices(context);
              if (mounted) setState(() {});
            },
          ),
        const Padding(padding: EdgeInsets.all(10), child: BalanceChip()),
      ]),
      body: ListView(children: [
        if (shieldUntil > nowMs())
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF0E2A44), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF4FC3F7))),
              child: Row(children: [
                const Icon(Icons.shield, color: Color(0xFF4FC3F7)),
                const SizedBox(width: 8),
                Text('الدرع فعّال — باقي ${((shieldUntil - nowMs()) / 3600000).ceil()} ساعة', style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        for (final it in _items)
          if (!it.staff || staff) ...[
            if (it.id == 'vip_galaxy')
              const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('✨ تأثيرات VIP (4)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: kMu))),
            ListTile(
              leading: GestureDetector(
                onTap: () => _info(it),
                child: Stack(clipBehavior: Clip.none, children: [
                  CircleAvatar(backgroundColor: accentA(context, .18), child: Text(it.e, style: const TextStyle(fontSize: 18))),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(width: 17, height: 17, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black, border: Border.all(color: kMu, width: 1.2)), child: const Text('!', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                  ),
                ]),
              ),
              title: it.id.startsWith('vip_') ? Align(alignment: AlignmentDirectional.centerStart, child: VipName(it.id.substring(4))) : Text(it.n, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(it.d, style: const TextStyle(color: kMu, fontSize: 12)),
              trailing: it.id.startsWith('vip_')
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'تجربة 3 دقائق',
                        icon: const Text('👁', style: TextStyle(fontSize: 20)),
                        onPressed: () => toast(startVipTrial(it.id.substring(4)) ? 'تجربة لمدة 3 دقائق ✨' : 'جرّبت هذا التأثير من قبل', bad: false),
                      ),
                      SizedBox(width: 92, child: AppButton(vipOwned.contains(it.id.substring(4)) ? 'مملوك' : (_pr(it) == 0 ? 'مجاني' : fmtN(_pr(it))), compact: true, onPressed: () => _buy(it))),
                    ])
                  : SizedBox(width: 92, child: AppButton(fmtN(_pr(it)), compact: true, onPressed: () => _buy(it))),
            ),
          ],
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
    if (until < nowMs()) {
      await db.ref().update(<String, Object?>{'members/${v['g']}/$myUid': null, 'visit/$myUid': null});
      memCache.remove((v['g'] ?? '').toString());
      toast('انتهت زيارتك، عدت إلى نقابتك');
    }
  } catch (_) {}
}


class _TypeText extends StatefulWidget {
  final String text;
  const _TypeText(this.text);
  @override
  State<_TypeText> createState() => _TypeTextState();
}

class _TypeTextState extends State<_TypeText> {
  int n = 0;
  Timer? t;
  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(milliseconds: 28), (_) {
      if (n >= widget.text.length) {
        t?.cancel();
        return;
      }
      if (mounted) setState(() => n++);
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.text.substring(0, n), style: const TextStyle(height: 1.8, fontSize: 14));
}
