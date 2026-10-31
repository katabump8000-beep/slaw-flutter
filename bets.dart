import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'aljesi.dart';
import 'app_state.dart';
import 'core.dart';
import 'data.dart';
import 'widgets.dart';

/// إضافة رصيد على دفعات (القواعد تسمح بـ 1000 كحد أقصى للمرة الواحدة)
Future<void> creditChunks(int total) async {
  var left = total;
  while (left > 0) {
    final c = left > 1000 ? 1000 : left;
    try {
      await addBalRetry(c);
    } catch (_) {
      break;
    }
    left -= c;
  }
}

class BetPlayer {
  final String uid;
  final int bet;
  String mask;
  BetPlayer(this.uid, this.bet, this.mask);
  int get alive => mask.split('').where((c) => c == '1').length;
}

/// حالة بطاقة الرهانات (تُخزَّن كنص في رسالة البطاقة)
class BetState {
  String phase = 'lobby';
  int t0 = 0;
  String creator = '';
  int maxBet = 0;
  int seed = 1;
  final List<BetPlayer> players = [];
  int pinN = 0;
  String pinUid = '';
  int pinIdx = 0;
  String outName = '';
  String winUid = '';
  int pot = 0;

  int get total => players.fold<int>(0, (a, p) => a + p.bet);
  int get minBet => players.isEmpty ? 10 : players.first.bet;

  String encode() {
    final b = StringBuffer('BET|$phase|$t0|$creator|$maxBet|$seed');
    for (final p in players) {
      b.write('\nP|${p.uid}|${p.bet}|${p.mask}');
    }
    if (pinN > 0) b.write('\nPIN|$pinN|$pinUid|$pinIdx');
    if (outName.isNotEmpty) b.write('\nOUT|$outName');
    if (winUid.isNotEmpty) b.write('\nWIN|$winUid|$pot');
    return b.toString();
  }

  static BetState? parse(String text) {
    if (!text.startsWith('BET|')) return null;
    final s = BetState();
    for (final l in text.split('\n')) {
      final f = l.split('|');
      if (f.isEmpty) continue;
      switch (f[0]) {
        case 'BET':
          if (f.length >= 6) {
            s.phase = f[1];
            s.t0 = int.tryParse(f[2]) ?? 0;
            s.creator = f[3];
            s.maxBet = int.tryParse(f[4]) ?? 0;
            s.seed = int.tryParse(f[5]) ?? 1;
          }
          break;
        case 'P':
          if (f.length >= 4) s.players.add(BetPlayer(f[1], int.tryParse(f[2]) ?? 0, f[3]));
          break;
        case 'PIN':
          if (f.length >= 4) {
            s.pinN = int.tryParse(f[1]) ?? 0;
            s.pinUid = f[2];
            s.pinIdx = int.tryParse(f[3]) ?? 0;
          }
          break;
        case 'OUT':
          if (f.length >= 2) s.outName = f.sublist(1).join('|');
          break;
        case 'WIN':
          if (f.length >= 3) {
            s.winUid = f[1];
            s.pot = int.tryParse(f[2]) ?? 0;
          }
          break;
      }
    }
    return s;
  }
}

/// فعالية الرهانات: يديرها جهاز من أنشأها
class BetHost {
  static final Map<String, BetHost> _active = {};
  final String gid;
  final String starter;
  String key = '';
  bool stopped = false;
  bool startReq = false;
  final BetState st = BetState();
  StreamSubscription<DatabaseEvent>? _sub;
  BetHost(this.gid, this.starter);

  static bool isActive(String gid) => _active.containsKey(gid);

  static void cancel(String gid) {
    _active[gid]?.stopped = true;
  }

  static Future<void> start(String gid) async {
    if (_active.containsKey(gid)) {
      toast('هناك فعالية رهانات قيد التشغيل', bad: true);
      return;
    }
    final mx = (await balanceNow()).toInt();
    if (mx < 10) {
      toast('رصيدك لا يكفي لإنشاء الفعالية', bad: true);
      return;
    }
    final h = BetHost(gid, myUid);
    h.st.creator = myUid;
    h.st.maxBet = mx;
    h.st.t0 = DateTime.now().millisecondsSinceEpoch;
    h.st.seed = Random().nextInt(1000000) + 1;
    _active[gid] = h;
    h._run();
  }

  /// يبحث عن آخر بطاقة رهانات في القروب
  static Future<MapEntry<String, BetState>?> findCard(String gid) async {
    try {
      final s = await ref('messages/$gid').limitToLast(80).get();
      final v = s.value;
      if (v is! Map) return null;
      final keys = v.keys.map((e) => e.toString()).toList()..sort();
      for (final k in keys.reversed) {
        final m = v[k];
        if (m is! Map) continue;
        if (!(m['d'] ?? '').toString().contains('"bet"')) continue;
        final st = BetState.parse((m['text'] ?? '').toString());
        if (st != null) return MapEntry(k, st);
      }
    } catch (_) {}
    return null;
  }

  /// مشاركة: تحقق ثم خصم الرصيد ثم رسالة مشاركة يقرؤها المضيف
  static Future<void> join(String gid, int amt) async {
    final c = await findCard(gid);
    if (c == null || c.value.phase != 'lobby') {
      toast('لا توجد فعالية رهانات مفتوحة', bad: true);
      return;
    }
    final st = c.value;
    if (st.players.any((p) => p.uid == myUid)) {
      toast('أنت مشارك بالفعل', bad: true);
      return;
    }
    if (st.players.length >= 20) {
      toast('اكتمل عدد المشاركين', bad: true);
      return;
    }
    if (amt < st.minBet) {
      toast('الرهان يجب أن يكون ${fmtN(st.minBet)} أو أكثر', bad: true);
      return;
    }
    if (amt > st.maxBet) {
      toast('الحد الأعلى للرهان ${fmtN(st.maxBet)} (رصيد صاحب الفعالية)', bad: true);
      return;
    }
    try {
      await addBal(-amt);
    } catch (_) {
      toast('رصيدك لا يكفي', bad: true);
      return;
    }
    try {
      await ref('messages/$gid').push().set(<String, Object?>{
        'from': myUid,
        'type': 'sys',
        'k': 'bot',
        'f': Session.me.name,
        'text': '🎈 ${Session.me.name} شارك برهان ${fmtN(amt)}',
        'd': jsonEncode(<String, Object?>{'bj': amt}),
        'ts': ServerValue.timestamp,
      });
      toast('تمت المشاركة 🎈');
    } catch (e) {
      await creditChunks(amt);
      err(e);
    }
  }

  Future<bool> _canControl(String uid) async {
    if (uid == starter) return true;
    try {
      final r = await roleOf(uid);
      if (r == 'emp' || r == 'dev') return true;
      return (await ref('groupAdmins/$gid/$uid').get()).exists;
    } catch (_) {
      return false;
    }
  }

  bool get _late => DateTime.now().millisecondsSinceEpoch - st.t0 >= 360000;

  Future<void> _push() async {
    try {
      await ref('messages/$gid/$key/text').set(st.encode());
    } catch (_) {}
  }

  Future<void> _refundOne(String uid, int amt) async {
    await botSay(gid, '↩️ تم استرجاع ${fmtN(amt)} رصيد', d: jsonEncode(<String, Object?>{'rf': <String, Object?>{uid: amt}}));
  }

  void _onMsg(Map<dynamic, dynamic> v) {
    final from = (v['from'] ?? '').toString();
    final type = (v['type'] ?? '').toString();
    if (type == 'text') {
      final t = normAr((v['text'] ?? '').toString());
      if (t == '.بدء') {
        _canControl(from).then((ok) {
          if ((ok || _late) && st.players.length >= 3 && st.phase == 'lobby') startReq = true;
        });
      } else if (t == '.الغاء') {
        _canControl(from).then((ok) {
          if (ok || (_late && st.phase == 'lobby')) stopped = true;
        });
      }
      return;
    }
    if (type == 'sys' && st.phase == 'lobby') {
      try {
        final j = jsonDecode((v['d'] ?? '{}').toString());
        if (j is Map && j['bj'] is num) {
          final amt = (j['bj'] as num).toInt();
          final bad = st.players.any((p) => p.uid == from) || st.players.length >= 20 || amt < st.minBet || amt > st.maxBet;
          if (bad) {
            _refundOne(from, amt);
          } else {
            st.players.add(BetPlayer(from, amt, '111'));
            _push();
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _close({bool refund = false}) async {
    await _sub?.cancel();
    if (refund && st.players.isNotEmpty) {
      final m = <String, Object?>{for (final p in st.players) p.uid: p.bet};
      await botSay(gid, '🛑 أُلغيت فعالية الرهانات وأُعيدت الرهانات لأصحابها.', d: jsonEncode(<String, Object?>{'rf': m}));
    } else if (refund) {
      await botSay(gid, '🛑 أُلغيت فعالية الرهانات.');
    }
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      await ref('messages/$gid/$key').remove();
    } catch (_) {}
    _active.remove(gid);
  }

  Future<void> _run() async {
    key = ref('messages/$gid').push().key!;
    try {
      await ref('messages/$gid/$key').set(<String, Object?>{
        'from': myUid,
        'type': 'sys',
        'k': 'bot',
        'f': Session.me.name,
        'text': st.encode(),
        'd': jsonEncode(<String, Object?>{'bet': 1}),
        'ts': ServerValue.timestamp,
      });
    } catch (e) {
      err(e);
      _active.remove(gid);
      return;
    }
    _sub = ref('messages/$gid').orderByKey().startAfter(key).onChildAdded.listen((e) {
      final v = e.snapshot.value;
      if (v is Map) _onMsg(v);
    });
    // غرفة الانتظار
    while (!stopped && !startReq) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_late && st.players.length < 3) {
        stopped = true;
      }
    }
    if (stopped) {
      await _close(refund: true);
      return;
    }
    st.phase = 'play';
    for (final p in st.players) {
      p.mask = '111';
    }
    await _push();
    await Future<void>.delayed(const Duration(seconds: 3));
    final rnd = Random();
    while (!stopped) {
      final alive = st.players.where((p) => p.alive > 0).toList();
      if (alive.length <= 1) break;
      final flat = <MapEntry<String, int>>[];
      for (final p in alive) {
        for (var i = 0; i < p.mask.length; i++) {
          if (p.mask[i] == '1') flat.add(MapEntry(p.uid, i));
        }
      }
      final t = flat[rnd.nextInt(flat.length)];
      st.pinN++;
      st.pinUid = t.key;
      st.pinIdx = t.value;
      st.outName = '';
      await _push();
      await Future<void>.delayed(const Duration(milliseconds: 5400));
      if (stopped) break;
      final pl = st.players.firstWhere((p) => p.uid == t.key);
      final ch = pl.mask.split('');
      ch[t.value] = '0';
      pl.mask = ch.join();
      if (pl.alive == 0) {
        st.outName = (await prof(pl.uid)).name;
      }
      await _push();
      await Future<void>.delayed(Duration(milliseconds: st.outName.isNotEmpty ? 3600 : 1600));
    }
    if (stopped) {
      await _close(refund: true);
      return;
    }
    final w = st.players.firstWhere((p) => p.alive > 0, orElse: () => st.players.first);
    st.phase = 'over';
    st.winUid = w.uid;
    st.pot = st.total;
    st.outName = '';
    await _push();
    final n = (await prof(w.uid)).name;
    await botSay(gid, '🏆 فاز $n بفعالية الرهانات!\n💰 ${fmtN(st.pot)} رصيد أُضيفت إلى رصيده', d: jsonEncode(<String, Object?>{'win': w.uid, 'amt': st.pot}));
    await Future<void>.delayed(const Duration(seconds: 8));
    await _close();
  }
}

const List<Color> _pc = [
  Color(0xFFFF4D4D), Color(0xFF3B9BFF), Color(0xFF2EE07A), Color(0xFFFFD83B), Color(0xFFA64BFF), Color(0xFFFF8A1F),
  Color(0xFF19C7B0), Color(0xFFFF4FA0), Color(0xFF9AA4B2), Color(0xFF8BE04A),
];

/// بطاقة الرهانات داخل الشات
class BetCard extends StatefulWidget {
  final String gid;
  final String text;
  const BetCard({super.key, required this.gid, required this.text});

  @override
  State<BetCard> createState() => _BetCardState();
}

class _BetCardState extends State<BetCard> with SingleTickerProviderStateMixin {
  late final AnimationController pin = AnimationController(vsync: this, duration: const Duration(milliseconds: 4600));
  final TextEditingController amt = TextEditingController();
  final Map<String, String> names = {};
  Timer? tick;
  bool perm = false;
  late BetState st = BetState.parse(widget.text) ?? BetState();

  @override
  void initState() {
    super.initState();
    _names();
    _perm();
    tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant BetCard old) {
    super.didUpdateWidget(old);
    final n = BetState.parse(widget.text) ?? BetState();
    if (n.pinN != st.pinN && n.pinN > 0 && n.phase == 'play') pin.forward(from: 0);
    st = n;
    _names();
  }

  @override
  void dispose() {
    tick?.cancel();
    pin.dispose();
    amt.dispose();
    super.dispose();
  }

  Future<void> _names() async {
    var ch = false;
    for (final p in st.players) {
      if (!names.containsKey(p.uid)) {
        names[p.uid] = (await prof(p.uid)).name;
        ch = true;
      }
    }
    if (ch && mounted) setState(() {});
  }

  Future<void> _perm() async {
    try {
      var ok = Session.isDev || st.creator == myUid;
      if (!ok) ok = (await ref('groupAdmins/${widget.gid}/$myUid').get()).exists;
      if (mounted) setState(() => perm = ok);
    } catch (_) {}
  }

  Future<void> _post(String t) async {
    try {
      await ref('messages/${widget.gid}').push().set(<String, Object?>{'from': myUid, 'type': 'text', 'text': t, 'ts': ServerValue.timestamp});
    } catch (e) {
      err(e);
    }
  }

  Color _col(String uid) {
    final i = st.players.indexWhere((p) => p.uid == uid);
    return _pc[(i < 0 ? 0 : i) % _pc.length];
  }

  static const String _rules = 'فعالية تعتمد على الحظ، إما تربح أو تخسر 🎲\n'
      'يجب أن يمتلك المشارك رصيدًا ويضع رهانًا.\n'
      'بعد أول رهان ينتظر صاحب رهان آخر بنفس القيمة أو أعلى بشرط ألا يتجاوز رصيد صاحب الفعالية.\n'
      'لكل شخص 🎈🎈🎈 ثلاث بالونات؛ تُفقع بالحظ، ومن تُفقع بالوناته كلها يخسر رهانه، والصامد يربح.\n'
      'الفائز يحصل على مجموع كل الرهانات. (حتى 20 مشاركاً)';

  @override
  Widget build(BuildContext context) {
    final mine = st.players.any((p) => p.uid == myUid);
    final late = DateTime.now().millisecondsSinceEpoch - st.t0 >= 360000;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0x99FFD54A))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('╮─❖『 الرهانات 』❖─╭', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFFFD54A), fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 8),
        if (st.phase == 'lobby') ...[
          const Text(_rules, style: TextStyle(color: Colors.white, height: 1.7, fontSize: 12.5)),
          const SizedBox(height: 6),
          Text('الحد الأدنى ${fmtN(st.minBet)} • الحد الأعلى ${fmtN(st.maxBet)} • الإجمالي ${fmtN(st.total)}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFD54A), fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final p in st.players)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                UserAvatar(p.uid, size: 30),
                const SizedBox(width: 8),
                Expanded(child: Text(names[p.uid] ?? '...', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                Text(fmtN(p.bet), style: const TextStyle(color: Color(0xFF4CE07A), fontWeight: FontWeight.w900)),
              ]),
            ),
          if (st.players.isEmpty) const Center(child: Text('لا مشاركين بعد', style: TextStyle(color: Colors.white54))),
          const SizedBox(height: 8),
          if (!mine)
            Row(children: [
              Expanded(child: TextField(controller: amt, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'مبلغ الرهان'))),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: AppButton('شارك', compact: true, onPressed: () {
                  final n = int.tryParse(normDigits(amt.text)) ?? 0;
                  if (n <= 0) {
                    toast('اكتب مبلغ الرهان', bad: true);
                    return;
                  }
                  BetHost.join(widget.gid, n);
                }),
              ),
            ])
          else
            const Center(child: Text('✅ أنت مشارك — بانتظار البدء', style: TextStyle(color: Color(0xFF4CE07A), fontWeight: FontWeight.w800))),
          if (st.players.length >= 3 && (perm || late))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(child: AppButton('بدء', compact: true, onPressed: () => _post('.بدء'))),
                const SizedBox(width: 8),
                Expanded(child: AppButton('إلغاء', kind: 'r', compact: true, onPressed: () => _post('.الغاء'))),
              ]),
            ),
        ] else if (st.phase == 'play') _play() else _over(),
      ]),
    );
  }

  Widget _play() {
    final all = <MapEntry<String, int>>[];
    for (final p in st.players) {
      for (var i = 0; i < 3; i++) {
        all.add(MapEntry(p.uid, i));
      }
    }
    all.shuffle(Random(st.seed));
    const cols = 6;
    return LayoutBuilder(builder: (c, box) {
      final w = box.maxWidth;
      final cell = w / cols;
      const sky = 70.0;
      final rows = (all.length / cols).ceil();
      final h = sky + rows * cell;
      Offset pos(String uid, int idx) {
        final s = all.indexWhere((e) => e.key == uid && e.value == idx);
        final k = s < 0 ? 0 : s;
        return Offset((k % cols) * cell + cell / 2, sky + (k ~/ cols) * cell + cell * .25);
      }
      final tgt = pos(st.pinUid, st.pinIdx);
      return Column(children: [
        Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
          for (final p in st.players)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: _col(p.uid), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('${names[p.uid] ?? '...'} ${p.alive}🎈', style: TextStyle(color: p.alive > 0 ? Colors.white : Colors.white30, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: h,
          child: Stack(children: [
            const Positioned(top: 0, left: 8, child: Text('☁️', style: TextStyle(fontSize: 30))),
            const Positioned(top: 10, right: 20, child: Text('☁️', style: TextStyle(fontSize: 26))),
            const Positioned(top: 4, left: 120, child: Text('☁️', style: TextStyle(fontSize: 22))),
            for (var k = 0; k < all.length; k++)
              Positioned(
                left: (k % cols) * cell,
                top: sky + (k ~/ cols) * cell,
                width: cell,
                height: cell,
                child: Center(
                  child: Builder(builder: (_) {
                    final pl = st.players.firstWhere((p) => p.uid == all[k].key);
                    final alive = all[k].value < pl.mask.length && pl.mask[all[k].value] == '1';
                    return alive
                        ? Container(width: cell * .56, height: cell * .68, decoration: BoxDecoration(color: _col(pl.uid), borderRadius: BorderRadius.circular(cell), boxShadow: [BoxShadow(color: _col(pl.uid).withAlpha(120), blurRadius: 8)]))
                        : Text('💥', style: TextStyle(fontSize: cell * .5));
                  }),
                ),
              ),
            if (st.pinN > 0)
              AnimatedBuilder(
                animation: pin,
                builder: (_, __) {
                  final e = Curves.easeIn.transform(pin.value);
                  return Positioned(left: tgt.dx - 14, top: -26 + (tgt.dy - 6) * e, child: const Text('📌', style: TextStyle(fontSize: 28)));
                },
              ),
            if (st.outName.isNotEmpty)
              Positioned(
                left: 10,
                right: 10,
                top: h / 2 - 22,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xEE000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFF4D4D))),
                  child: Text('${st.outName} ودّع المونديال 👋', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ),
          ]),
        ),
        Text('الجائزة: ${fmtN(st.total)}', style: const TextStyle(color: Color(0xFFFFD54A), fontWeight: FontWeight.w900)),
      ]);
    });
  }

  Widget _over() {
    return Column(children: [
      const SizedBox(height: 6),
      UserAvatar(st.winUid, size: 80),
      const SizedBox(height: 8),
      Text(names[st.winUid] ?? '...', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
      const Text('🏆 الرابح', style: TextStyle(color: Color(0xFFFFD54A), fontSize: 20, fontWeight: FontWeight.w900)),
      Text('${fmtN(st.pot)} رصيد', style: const TextStyle(color: Color(0xFF4CE07A), fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 6),
    ]);
  }
}
