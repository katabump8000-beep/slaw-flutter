import 'dart:async';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'ai.dart';
import 'app_state.dart';
import 'core.dart';
import 'data.dart';
import 'home.dart';
import 'events.dart';
import 'quiz.dart';
import 'sfx.dart';
import 'shop.dart';
import 'widgets.dart';

String normAr(String s) {
  var t = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
  t = t
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
  return t.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

int _lev(String a, String b) {
  final m = a.length, n = b.length;
  var prev = List<int>.generate(n + 1, (i) => i);
  for (var i = 1; i <= m; i++) {
    final cur = List<int>.filled(n + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final c = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + c);
    }
    prev = cur;
  }
  return prev[n];
}

const List<String> _cmds = [
  'تفاصيلي', 'رصيدي', 'رصيد', 'معلوماته', 'تفاصيله', 'اوامر', 'العاب', 'كريستال', 'بالونات', 'اعلام', 'كتابه', 'تفكيك', 'الغاء', 'الوان',
  'المتصدرين', 'المتجر', 'حيوانات', 'شخصيات', 'فخر',
];
const Set<String> _gameCmds = {'العاب', 'كريستال', 'بالونات', 'اعلام', 'كتابه', 'تفكيك', 'الوان', 'حيوانات', 'شخصيات'};

bool isCommandText(String t) => RegExp(r'^\s*\.\s*[\u0600-\u06FFa-zA-Z]').hasMatch(t);

Future<bool> canPlay(String gid) async {
  final gm = groupsCache[gid] ?? <String, dynamic>{};
  if (Session.isDev || gm['gamesAll'] == true) return true;
  try {
    final p = await ref('gamePerm/$gid/$myUid').get();
    final a = await ref('groupAdmins/$gid/$myUid').get();
    return p.exists || a.exists;
  } catch (_) {
    return false;
  }
}

/// ينفّذ أمر ALJESI. يتحمّل أخطاء الكتابة (مسافة، همزة، ة/ه...)
Future<void> runCommand(BuildContext ctx, String gid, String raw) async {
  final body = raw.trim().replaceFirst(RegExp(r'^\.\s*'), '');
  final m = RegExp(r'^([\u0600-\u06FFa-zA-Z]+)\s*(.*)$').firstMatch(body);
  if (m == null) return;
  final word = normAr(m.group(1)!);
  final args = (m.group(2) ?? '').trim();
  if (word == 'تحويل') {
    await botSay(gid, '🚫 تم إلغاء أمر التحويل');
    return;
  }
  String? cmd;
  var best = 99;
  for (final c in _cmds) {
    final d = _lev(word, c);
    if (d < best) {
      best = d;
      cmd = c;
    }
  }
  if (cmd == null || best > (word.length >= 5 ? 2 : 1)) {
    await botSay(gid, '❌ الأمر غير موجود. اكتب ‎.اوامر‎ لعرض القائمة');
    return;
  }
  if (_gameCmds.contains(cmd) && !(await canPlay(gid))) {
    await botSay(gid, '🎮 ليس لديك صلاحية الألعاب. اطلب من مشرف منحك إياها.');
    return;
  }
  if (!ctx.mounted) return;
  void push(Widget w) => Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => w));
  switch (cmd) {
    case 'اوامر':
      await botSay(gid,
          '╮─❖『 أوامر ALJESI 』❖─╭\n.تفاصيلي — بطاقتك\n.رصيدي — رصيدك\n.العاب — قائمة الألعاب\n.معلوماته @اسم — ملف عضو (إن كان عاماً)\n.كريستال [مبلغ]\n.بالونات\n.اعلام\n.كتابة\n.تفكيك\n.الوان\n.حيوانات — فعالية الحيوانات\n.شخصيات — تخمين الشخصيات\n.الغاء — إلغاء الفعالية الجارية\n.المتصدرين — متصدرو اليوم\n.فخر — درجة الفخر\n.المتجر\n╰─❖『 ALJESI 』❖─╯');
      break;
    case 'رصيدي':
    case 'رصيد':
      if (args.contains('@') && Session.isDev) {
        await _giveBalance(gid, args);
      } else if (args.contains('@')) {
        await botSay(gid, '🔒 هذا الأمر لرتب المطورين فقط');
      } else {
        await botSay(gid, '💰 رصيدك الحالي: ${fmtN(await balanceNow())}');
      }
      break;
    case 'معلوماته':
    case 'تفاصيله':
      if (args.isEmpty) {
        await botSay(gid, '❌ الصيغة: ‎.معلوماته @اسم');
      } else {
        await _detailsOf(gid, args);
      }
      break;
    case 'فخر':
      await botSay(gid, '🛡 درجة فخرك: ${await prideOf(myUid)}%');
      break;
    case 'تفاصيلي':
      if (args.isNotEmpty) {
        await _detailsOf(gid, args);
      } else {
        await _details(gid);
      }
      break;
    case 'المتصدرين':
      await _board(gid);
      break;
    case 'العاب':
      await botSay(gid, '🎮 الألعاب:\n💎 .كريستال [مبلغ]\n🎈 .بالونات\n🏳️ .اعلام\n⌨️ .كتابة\n🧩 .تفكيك\n🎨 .الوان\n🐾 .حيوانات\n🎭 .شخصيات');
      break;
    case 'كريستال':
      push(CrystalScreen(gid: gid, preset: int.tryParse(normDigits(args)) ?? 50));
      break;
    case 'بالونات':
      push(BalloonScreen(gid: gid));
      break;
    case 'اعلام':
      push(QuickQuizScreen(gid: gid, kind: 'flags'));
      break;
    case 'كتابه':
      await EventsHost.start(gid, 'type');
      break;
    case 'تفكيك':
      await EventsHost.start(gid, 'scramble');
      break;
    case 'الوان':
      await EventsHost.start(gid, 'colors');
      break;
    case 'الغاء':
      EventsHost.cancel(gid);
      QuizHost.cancel(gid);
      break;
    case 'المتجر':
      push(const ShopRoute());
      break;
    case 'حيوانات':
      await QuizHost.start(ctx, gid, 'animals');
      break;
    case 'شخصيات':
      await QuizHost.start(ctx, gid, 'chars');
      break;
  }
}

Future<void> _details(String gid) async {
  final mg = groupKind(gid) == 'main' ? gid : (mainGroups().isNotEmpty ? mainGroups().first : gid);
  Future<Object?> g(String p) async {
    try {
      return (await ref(p).get()).value;
    } catch (_) {
      return null;
    }
  }
  final r = await Future.wait<Object?>([
    g('stats/$mg/$myUid'), g('inv/$myUid/upg'), g('boost/$myUid'), g('msgTotal/$myUid'),
    g('wins/$myUid'), g('likeCount/$myUid'), g('visit/$myUid'), g('groupAdmins/$mg/$myUid'),
  ]);
  final pr = await prideOf(myUid);
  final role = await roleOf(myUid);
  final rank = role == 'emp' ? 'الإمبراطور ∞' : role == 'dev' ? 'رتبة عليا' : (r[7] != null ? 'مشرف' : 'عضو');
  final v = r[6];
  await botSay(
      gid,
      [
        '╮─❖『 تفاصيلي 』❖─╭',
        '👤 اللقب: ${Session.me.name}',
        '🎖 الرتبة: $rank',
        '🏰 النقابة: ${groupName(mg)}',
        '💰 الرصيد: ${fmtN(await balanceNow())}',
        '💬 رسائل اليوم: ${r[0] ?? 0}  •  الإجمالي: ${r[3] ?? 0}',
        '🎫 بطاقات الترقية: ${r[1] ?? 0}',
        '✖️2 المضاعفة: ${r[2] != null ? 'مفعّلة ✅' : 'غير مفعّلة'}',
        '🏆 الفوز بالفعاليات: ${r[4] ?? 0}',
        '👍 الإعجابات: ${r[5] ?? 0}',
        '🛡 درجة الفخر: $pr%',
        if (v is Map) '✈️ زائر في: ${groupName((v['g'] ?? '').toString())}',
        '╰─❖『 ALJESI 』❖─╯',
      ].join('\n'));
}

Future<String?> _uidByName(String gid, String raw) async {
  final n = normAr(raw.replaceFirst('@', '').trim());
  if (n.isEmpty) return null;
  final tries = <String>[gid];
  for (final g in mainGroups()) {
    if (!tries.contains(g)) tries.add(g);
  }
  for (final g in tries) {
    try {
      final v = (await ref('members/$g').get()).value;
      if (v is! Map) continue;
      final ids = v.keys.map((e) => e.toString()).toList();
      final ps = await Future.wait(ids.map(prof));
      for (var i = 0; i < ids.length; i++) {
        if (normAr(ps[i].name) == n) return ids[i];
      }
    } catch (_) {}
  }
  return null;
}

/// .رصيد @اسم 50  (للإمبراطور والمطورين)
Future<void> _giveBalance(String gid, String args) async {
  final m = RegExp(r'^(.*?)\s*([0-9\u0660-\u0669]+)\s*$').firstMatch(args.trim());
  if (m == null) {
    await botSay(gid, '❌ الصيغة: ‎.رصيد @اسم 50');
    return;
  }
  final n = int.tryParse(normDigits(m.group(2)!)) ?? 0;
  final u = await _uidByName(gid, m.group(1)!);
  if (u == null || n <= 0) {
    await botSay(gid, '❌ لم أجد العضو أو المبلغ غير صحيح');
    return;
  }
  try {
    await ref('wallets/$u/bal').set(ServerValue.increment(n));
    final p = await prof(u);
    final after = (await ref('wallets/$u/bal').get()).value;
    final mg = groupKind(gid) == 'main' ? gid : (mainGroups().isNotEmpty ? mainGroups().first : gid);
    final txt = '💸 ${Session.me.name} حوّل ${fmtN(n)} رصيد إلى ${p.name}';
    await botSay(gid, '╮─❖『 بطاقة تحويل 』❖─╭\n📥 المستلم: ${p.name}\n🏰 النقابة: ${groupName(mg)}\n📤 المحوِّل: ${Session.me.name}\n💰 المبلغ: ${fmtN(n)}\n🧾 رصيده بعد التحويل: ${after is num ? fmtN(after) : '-'}\n╰─❖『 ALJESI 』❖─╯');
    await feedNote('shop', txt, k: 'tr');
    await sendNotif(u, {'t': 'tr', 'a': n, 'g': mg, 'm': groupName(mg)});
  } catch (e) {
    err(e);
  }
}

Future<void> _detailsOf(String gid, String raw) async {
  final u = await _uidByName(gid, raw);
  if (u == null) {
    await botSay(gid, '❌ لم أجد هذا العضو في هذه الدردشة');
    return;
  }
  Future<Object?> g(String p) async {
    try {
      return (await ref(p).get()).value;
    } catch (_) {
      return null;
    }
  }
  final mg = groupKind(gid) == 'main' ? gid : (mainGroups().isNotEmpty ? mainGroups().first : gid);
  final priv = (await g('pdata/$u/priv')) == true;
  if (priv && u != myUid && !Session.isDev && (await g('groupAdmins/$mg/$myUid')) == null) {
    await botSay(gid, '🔒 الملف التعريفي لهذا العضو خاص');
    return;
  }
  final r = await Future.wait<Object?>([g('msgTotal/$u'), g('wins/$u'), g('likeCount/$u'), g('groupAdmins/$mg/$u'), g('pdata/$u/note'), g('wallets/$u/bal')]);
  final p = await prof(u);
  final role = await roleOf(u);
  final pr = await prideOf(u);
  final rank = role == 'emp' ? 'الإمبراطور ∞' : role == 'dev' ? 'رتبة عليا' : (r[3] != null ? 'مشرف' : 'عضو');
  await botSay(
      gid,
      [
        '╮─❖『 تفاصيل ${p.name} 』❖─╭',
        '🎖 الرتبة: $rank',
        '🏰 النقابة: ${groupName(mg)}',
        if (r[5] is num) '💰 الرصيد: ${fmtN(r[5] as num)}',
        '💬 الرسائل: ${r[0] ?? 0}',
        '🏆 الفوز بالفعاليات: ${r[1] ?? 0}',
        '👍 الإعجابات: ${r[2] ?? 0}',
        '🛡 درجة الفخر: $pr%',
        if ((r[4] ?? '').toString().isNotEmpty) '📝 ${r[4]}',
        '╰─❖『 ALJESI 』❖─╯',
      ].join('\n'));
}

Future<void> _board(String gid) async {
  final mg = groupKind(gid) == 'main' ? gid : (mainGroups().isNotEmpty ? mainGroups().first : gid);
  try {
    final s = await ref('stats/$mg').get();
    final v = s.value;
    final ents = <MapEntry<String, int>>[];
    if (v is Map) v.forEach((k, x) => ents.add(MapEntry(k.toString(), x is num ? x.toInt() : 0)));
    ents.sort((a, b) => b.value.compareTo(a.value));
    final top = ents.take(10).toList();
    if (top.isEmpty) {
      await botSay(gid, 'لا يوجد تفاعل اليوم بعد');
      return;
    }
    final names = await Future.wait(top.map((e) => prof(e.key)));
    final medals = ['🥇', '🥈', '🥉'];
    await botSay(gid, '🏆 متصدرو ${groupName(mg)} اليوم:\n${[for (var i = 0; i < top.length; i++) '${i < 3 ? medals[i] : '${i + 1}.'} ${names[i].name} — ${top[i].value}'].join('\n')}');
  } catch (_) {}
}

// ---------- التحويل ----------
Future<void> transferSheet(BuildContext ctx, String gid) async {
  final mg = groupKind(gid) == 'main' ? gid : (mainGroups().isNotEmpty ? mainGroups().first : '');
  if (mg.isEmpty || memCache[mg] != true) {
    toast('التحويل داخل النقابة فقط', bad: true);
    return;
  }
  Map<dynamic, dynamic> ms = {};
  try {
    final s = await ref('members/$mg').get();
    if (s.value is Map) ms = s.value as Map;
  } catch (e) {
    err(e);
    return;
  }
  final ids = ms.keys.map((e) => e.toString()).where((u) => u != myUid && ms[u] == true).toList();
  final ps = await Future.wait(ids.map(prof));
  if (!ctx.mounted) return;
  final amt = TextEditingController();
  final q = TextEditingController();
  showAppSheet<void>(ctx, (sc) => [
        const Text('💸 تحويل رصيد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        TextField(controller: amt, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'المبلغ (10 فما فوق)')),
        StatefulBuilder(builder: (c, set) {
          final f = q.text.trim();
          final list = <int>[for (var i = 0; i < ids.length; i++) if (f.isEmpty || ps[i].name.contains(f)) i];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: q, onChanged: (_) => set(() {}), decoration: const InputDecoration(hintText: 'ابحث بالاسم')),
            ...list.take(30).map((i) => ListTile(
                  dense: true,
                  leading: UserAvatar(ids[i], size: 34),
                  title: Text(ps[i].name),
                  onTap: () async {
                    final n = int.tryParse(normDigits(amt.text)) ?? 0;
                    if (n < 10) {
                      toast('اكتب المبلغ أولاً', bad: true);
                      return;
                    }
                    try {
                      if ((await balanceNow()) < n) {
                        toast('رصيدك لا يكفي', bad: true);
                        return;
                      }
                      await db.ref().update(<String, Object?>{
                        'wallets/$myUid/bal': ServerValue.increment(-n),
                        'wallets/${ids[i]}/bal': ServerValue.increment(n),
                      });
                      if (sc.mounted) Navigator.of(sc).pop();
                      toast('تم التحويل ✅');
                      await botSay(gid, '💸 ${Session.me.name} حوّل ${fmtN(n)} رصيد إلى ${ps[i].name}');
                      await feedNote('ads', '💸 ${Session.me.name} حوّل ${fmtN(n)} رصيد إلى ${ps[i].name}', k: 'tr');
                      await sendNotif(ids[i], {'t': 'tr', 'a': n, 'g': mg, 'm': groupName(mg)});
                    } catch (e) {
                      err(e);
                    }
                  },
                )),
          ]);
        }),
      ]);
}

// ---------- لعبة الكريستال ----------
class _Pat {
  final List<String> p;
  final double m;
  final String r;
  final int w;
  const _Pat(this.p, this.m, this.r, this.w);
}

const List<_Pat> _pats = [
  _Pat(['💎', '💎', '💎', '💎'], 5, 'win', 2),
  _Pat(['⭐', '⭐', '⭐', '⭐'], 4, 'win', 3),
  _Pat(['👑', '👑', '👑', '👑'], 3, 'win', 5),
  _Pat(['💎', '💎', '💎', '⭐'], 2, 'win', 8),
  _Pat(['⭐', '⭐', '🍒', '🍒'], 1.5, 'win', 10),
  _Pat(['🍀', '🍀', '💰', '💰'], 1.3, 'win', 10),
  _Pat(['💎', '⭐', '💎', '⭐'], 1, 'retry', 12),
  _Pat(['🔥', '🔥', '💣', '💎'], 0, 'lose', 25),
  _Pat(['💣', '💣', '🍒', '⭐'], 0, 'lose', 25),
];
const List<String> _em = ['💎', '⭐', '🍒', '💣', '🔥', '🍀', '👑', '💰'];

_Pat _pick() {
  final t = _pats.fold<int>(0, (s, x) => s + x.w);
  var r = Random().nextInt(t);
  for (final x in _pats) {
    r -= x.w;
    if (r < 0) return x;
  }
  return _pats.last;
}

class CrystalScreen extends StatefulWidget {
  final String gid;
  final int preset;
  const CrystalScreen({super.key, required this.gid, this.preset = 50});

  @override
  State<CrystalScreen> createState() => _CrystalScreenState();
}

class _CrystalScreenState extends State<CrystalScreen> {
  late final TextEditingController bet = TextEditingController(text: '${widget.preset.clamp(10, 200)}');
  List<String> slots = ['❔', '❔', '❔', '❔'];
  final List<bool> done = [false, false, false, false];
  bool busy = false;
  String info = 'الرهان من 10 إلى 200 • ربح حتى ×5';
  num bal = 0;
  Timer? iv;

  @override
  void initState() {
    super.initState();
    _bal();
  }

  @override
  void dispose() {
    iv?.cancel();
    super.dispose();
  }

  Future<void> _bal() async {
    final b = await balanceNow();
    if (mounted) setState(() => bal = b);
  }

  Future<void> _play() async {
    if (busy) return;
    final b = int.tryParse(normDigits(bet.text)) ?? 0;
    if (b < 10 || b > 200) {
      toast('الرهان من 10 إلى 200', bad: true);
      return;
    }
    setState(() => busy = true);
    try {
      await addBal(-b);
    } catch (_) {
      toast('رصيدك لا يكفي', bad: true);
      setState(() => busy = false);
      return;
    }
    await _bal();
    Sfx.start('wheel.wav');
    final res = _pick();
    for (var i = 0; i < 4; i++) {
      done[i] = false;
    }
    iv = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < 4; i++) {
          if (!done[i]) slots[i] = _em[Random().nextInt(_em.length)];
        }
      });
    });
    for (var i = 0; i < 4; i++) {
      Future<void>.delayed(Duration(milliseconds: 2000 + i * 900), () {
        if (!mounted) return;
        setState(() {
          done[i] = true;
          slots[i] = res.p[i];
        });
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 5300));
    iv?.cancel();
    final pay = res.r == 'win' ? (b * res.m).round() : (res.r == 'retry' ? b : 0);
    if (pay > 0) {
      try {
        await addBalRetry(pay);
      } catch (_) {
        toast('تعذر إضافة الربح، تواصل مع مطور', bad: true);
      }
    }
    final net = pay - b;
    if (net < 0) await addLoss(-net);
    await _bal();
    final line = res.p.join(' ');
    final txt = res.r == 'win' ? '🎉 ربح ${fmtN(net)} رصيد (×${res.m})' : (res.r == 'retry' ? '↩️ استرجع رهانه' : '💥 خسر ${fmtN(b)} رصيد');
    if (mounted) setState(() {
      info = txt;
      busy = false;
    });
    await botSay(widget.gid, '💎 كريستال — ${Session.me.name}\n[ $line ]\n$txt');
    if (net >= 300) {
      await feedNote('ads', '🎉 ${Session.me.name} ربح ${fmtN(net)} رصيد في الكريستال!', k: 'win');
    } else if (net <= -150) {
      await feedNote('ads', '💥 ${Session.me.name} خسر ${fmtN(-net)} رصيد في الكريستال', k: 'lose');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('💎 كريستال')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: Text('💰 ${fmtN(bal)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            textDirection: TextDirection.ltr,
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  width: 70,
                  height: 92,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF26120A), Color(0xFF0E0603)]),
                    border: Border.all(color: done[i] ? const Color(0xFFFFD54A) : context.accent, width: 2),
                    boxShadow: done[i] ? const [BoxShadow(color: Color(0xAAFF9A1F), blurRadius: 14)] : null,
                  ),
                  child: Text(slots[i], style: const TextStyle(fontSize: 38)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(controller: bet, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: 'الرهان')),
          const SizedBox(height: 12),
          AppButton(busy ? '...' : 'ابدأ اللف 🎰', glow: true, onPressed: busy ? null : _play),
          const SizedBox(height: 14),
          Center(child: Text(info, style: TextStyle(color: context.accent2, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

// ---------- لعبة البالونات ----------
class BalloonScreen extends StatefulWidget {
  final String gid;
  const BalloonScreen({super.key, required this.gid});

  @override
  State<BalloonScreen> createState() => _BalloonScreenState();
}

class _BalloonScreenState extends State<BalloonScreen> with SingleTickerProviderStateMixin {
  final bet = TextEditingController(text: '60');
  late final AnimationController fl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
  String state = 'idle';
  int stake = 0;
  List<List<Object>> vals = [];
  final List<int> picks = [];
  String info = 'اختر 3 بالونات. احذر الدبوس 📌';
  num bal = 0;
  bool paid = false;
  static const _out = [
    ['📌', 0.0, 35],
    ['🥈', 0.5, 30],
    ['🥇', 1.5, 25],
    ['🌈', 3.0, 10],
  ];
  static const _cols = [Color(0xFFFF5A4D), Color(0xFFFFB04A), Color(0xFF6EE787), Color(0xFF7FB2FF), Color(0xFFC792FF), Color(0xFFFF7EB6)];

  @override
  void initState() {
    super.initState();
    _bal();
  }

  @override
  void dispose() {
    fl.dispose();
    if (state == 'play' && !paid) _finish(silent: true);
    super.dispose();
  }

  Future<void> _bal() async {
    final b = await balanceNow();
    if (mounted) setState(() => bal = b);
  }

  List<Object> _draw() {
    var r = Random().nextInt(100);
    for (final o in _out) {
      r -= o[2] as int;
      if (r < 0) return o;
    }
    return _out.first;
  }

  Future<void> _start() async {
    if (state == 'play') return;
    final b = int.tryParse(normDigits(bet.text)) ?? 0;
    if (b < 30 || b > 200) {
      toast('الرهان من 30 إلى 200', bad: true);
      return;
    }
    try {
      await addBal(-b);
    } catch (_) {
      toast('رصيدك لا يكفي', bad: true);
      return;
    }
    await _bal();
    setState(() {
      stake = b;
      state = 'play';
      picks.clear();
      paid = false;
      vals = List.generate(12, (_) => _draw());
      info = 'اختر 3 بالونات (0/3)';
    });
  }

  Future<void> _pop(int i) async {
    if (state != 'play' || picks.contains(i)) return;
    setState(() {
      picks.add(i);
      info = 'اخترت ${picks.length}/3';
    });
    if (picks.length >= 3) await _finish();
  }

  Future<void> _finish({bool silent = false}) async {
    if (paid) return;
    paid = true;
    state = 'done';
    final shot = stake / 3;
    var pay = 0.0;
    for (final i in picks) {
      pay += shot * (vals[i][1] as double);
    }
    final p = pay.round();
    final net = p - stake;
    if (net < 0) await addLoss(-net);
    if (p > 0) {
      try {
        await addBalRetry(p);
      } catch (_) {}
    }
    if (!silent && mounted) {
      await _bal();
      setState(() => info = net > 0 ? '🎉 ربحت ${fmtN(net)}' : (net == 0 ? '↩️ تعادل' : '💥 خسرت ${fmtN(-net)}'));
    }
    final txt = net > 0 ? '🎉 ربح ${fmtN(net)} رصيد' : (net == 0 ? '↩️ تعادل' : '💥 خسر ${fmtN(-net)} رصيد');
    await botSay(widget.gid, '🎈 البالونات — ${Session.me.name}\n[ ${picks.map((i) => vals[i][0]).join(' ')} ]\n$txt');
    if (net >= 200) await feedNote('ads', '🎈 ${Session.me.name} ربح ${fmtN(net)} رصيد في البالونات!', k: 'win');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎈 البالونات')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Center(child: Text('💰 ${fmtN(bal)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          const SizedBox(height: 10),
          TextField(controller: bet, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: 'الرهان (30-200)')),
          const SizedBox(height: 10),
          AppButton(state == 'play' ? '...' : 'ابدأ اللعب 🎈', glow: true, onPressed: state == 'play' ? null : _start),
          const SizedBox(height: 12),
          Center(child: Text(info, style: TextStyle(color: context.accent2, fontWeight: FontWeight.w700))),
          const SizedBox(height: 14),
          if (vals.isNotEmpty)
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: .8,
              children: [
                for (var i = 0; i < 12; i++)
                  AnimatedBuilder(
                    animation: fl,
                    builder: (c, child) => Transform.translate(offset: Offset(0, picks.contains(i) ? 0 : -9 * ((fl.value + i % 5 * .2) % 1)), child: child),
                    child: GestureDetector(
                      onTap: () => _pop(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: picks.contains(i) ? const Color(0x1FFFFFFF) : _cols[i % 6],
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(60), bottom: Radius.circular(40)),
                        ),
                        child: Text(picks.contains(i) ? '${vals[i][0]}' : '🎈', style: TextStyle(fontSize: picks.contains(i) ? 34 : 30)),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
