import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'servertime.dart';
import 'widgets.dart';

// ======================================================================
// رهان كرة القدم (برشلونة × ريال مدريد). كل الرصيد والتصويت يحسمه السيرفر عبر fbReq.
// ======================================================================

const Color _grass = Color(0xFF1B8F3A);

Future<String> fbCall(String k, [Map<String, Object?> extra = const {}]) async {
  final rid = ref('fbReq').push().key!;
  final done = Completer<Map<dynamic, dynamic>>();
  final sub = ref('fbRes/$myUid').onValue.listen((e) {
    final v = e.snapshot.value;
    if (v is Map && v['id'] == rid && !done.isCompleted) done.complete(v);
  }, onError: (_) {});
  String why = '';
  try {
    await ref('fbReq/$rid').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 'k': k, ...extra}).timeout(const Duration(seconds: 8));
  } catch (e) {
    why = e.toString().toLowerCase().contains('permission') ? 'rules' : 'net';
  }
  Map<dynamic, dynamic>? r;
  if (why.isEmpty) {
    try {
      r = await done.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      r = null;
    }
  }
  await sub.cancel();
  if (r == null) return why.isNotEmpty ? why : 'timeout';
  return (r['err'] ?? '').toString();
}

void fbToast(String e) {
  switch (e) {
    case 'rules':
      toast('قواعد قاعدة البيانات لم تُحدَّث بعد (fbReq)', bad: true);
      break;
    case 'net':
      toast('لا يوجد اتصال بالإنترنت', bad: true);
      break;
    case 'timeout':
      toast('سيرفر المنصة لا يستجيب الآن، حاول بعد دقيقة', bad: true);
      break;
    case 'perm':
      toast('هذا الزر للمطورين فقط', bad: true);
      break;
    case 'busy':
      toast('هناك حدث قيد التشغيل بالفعل', bad: true);
      break;
    case 'prize':
      toast('ضع جائزة صحيحة', bad: true);
      break;
    case 'mins':
      toast('الدقائق من 1 إلى 10080', bad: true);
      break;
    case 'closed':
      toast('انتهى وقت التصويت', bad: true);
      break;
    case 'dup':
      toast('لقد صوّتّ مسبقاً', bad: true);
      break;
    case 'early':
      toast('لم ينتهِ وقت التصويت بعد', bad: true);
      break;
    default:
      toast('تعذر تنفيذ الطلب', bad: true);
  }
}

String _fmtCd(int ms) {
  var s = (ms / 1000).ceil();
  if (s < 0) s = 0;
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int x) => x.toString().padLeft(2, '0');
  return d > 0 ? '$d يوم  ${two(h)}:${two(m)}:${two(sec)}' : '${two(h)}:${two(m)}:${two(sec)}';
}

// ---------- رسم الكرة والشعارات (رسم برمجي وليس إيموجي) ----------
class _BallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width / 2;
    final c = Offset(r, r);
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    final p = Paint()..color = const Color(0xFF222222);
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      final pt = c + Offset(math.cos(a), math.sin(a)) * (r * .38);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, p);
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * (r * .38);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r * .78);
      canvas.drawLine(p1, p2, Paint()..color = const Color(0xFF222222)..strokeWidth = r * .09);
      canvas.drawCircle(c + Offset(math.cos(a + .6), math.sin(a + .6)) * (r * .86), r * .13, p);
    }
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..color = const Color(0xFFBBBBBB)..strokeWidth = r * .05);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class FootballIcon extends StatelessWidget {
  final double size;
  const FootballIcon({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _BallPainter()));
}

class _CrestPainter extends CustomPainter {
  final bool bar;
  _CrestPainter(this.bar);

  void _text(Canvas canvas, Size s, String t, Color col, double fs, double dy) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: col, fontSize: fs, fontWeight: FontWeight.w900)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset((s.width - tp.width) / 2, dy));
  }

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    if (bar) {
      final shield = Path()
        ..moveTo(w * .06, h * .04)
        ..lineTo(w * .94, h * .04)
        ..lineTo(w * .94, h * .58)
        ..quadraticBezierTo(w * .94, h * .88, w * .5, h * .98)
        ..quadraticBezierTo(w * .06, h * .88, w * .06, h * .58)
        ..close();
      canvas.save();
      canvas.clipPath(shield);
      final stripe = w * .88 / 6;
      for (var i = 0; i < 6; i++) {
        canvas.drawRect(Rect.fromLTWH(w * .06 + stripe * i, 0, stripe, h), Paint()..color = i.isEven ? const Color(0xFF004D98) : const Color(0xFFA50044));
      }
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h * .26), Paint()..color = const Color(0xFFFFD700));
      canvas.restore();
      canvas.drawPath(shield, Paint()..style = PaintingStyle.stroke..color = const Color(0xFFFFD700)..strokeWidth = w * .045);
      _text(canvas, s, 'FCB', Colors.white, w * .24, h * .42);
    } else {
      canvas.drawCircle(Offset(w / 2, h * .58), w * .4, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(w / 2, h * .58), w * .4, Paint()..style = PaintingStyle.stroke..color = const Color(0xFFFEBE10)..strokeWidth = w * .05);
      canvas.drawRect(Rect.fromLTWH(w * .12, h * .52, w * .76, h * .13), Paint()..color = const Color(0xFF00529F));
      final crown = Path()
        ..moveTo(w * .3, h * .3)
        ..lineTo(w * .3, h * .1)
        ..lineTo(w * .4, h * .2)
        ..lineTo(w * .5, h * .06)
        ..lineTo(w * .6, h * .2)
        ..lineTo(w * .7, h * .1)
        ..lineTo(w * .7, h * .3)
        ..close();
      canvas.drawPath(crown, Paint()..color = const Color(0xFFFEBE10));
      _text(canvas, s, 'RM', const Color(0xFF00529F), w * .2, h * .68);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class Crest extends StatelessWidget {
  final bool bar;
  final double size;
  const Crest({super.key, required this.bar, this.size = 96});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        // الشعاران من الصورتين par.png (برشلونة) و real.png (ريال مدريد) المرفوعتين في المشروع؛ والرسم البرمجي احتياطي إن لم تُرفعا
        child: Image.asset(bar ? 'assets/img/par.png' : 'assets/img/real.png', fit: BoxFit.contain, errorBuilder: (c, e, s) => CustomPaint(painter: _CrestPainter(bar))),
      );
}

class _GrassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = const Color(0xFF0F6B28);
    final rnd = math.Random(7);
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * s.width;
      final hh = 14 + rnd.nextDouble() * 26;
      final path = Path()
        ..moveTo(x, s.height)
        ..quadraticBezierTo(x + 3, s.height - hh * .6, x + (rnd.nextDouble() * 8 - 4), s.height - hh)
        ..quadraticBezierTo(x - 2, s.height - hh * .5, x - 3, s.height)
        ..close();
      canvas.drawPath(path, p..color = i.isEven ? const Color(0xFF0F6B28) : const Color(0xFF168A33));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ---------- زر «حدث» في الرئيسية ----------
class FootballFab extends StatelessWidget {
  const FootballFab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('fb/cur').onValue,
      builder: (c, s) {
        final v = s.data?.snapshot.value;
        if (v is! Map) return const SizedBox.shrink();
        final st = (v['state'] ?? '').toString();
        if (st == 'cancelled') return const SizedBox.shrink();
        final done = (v['doneTs'] as num?)?.toInt() ?? 0;
        if (st == 'done' && nowMs() - done > 86400000) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FootballScreen())),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF0B2A12), border: Border.all(color: const Color(0xFF39FF88), width: 2), boxShadow: const [BoxShadow(color: Color(0xAA39FF88), blurRadius: 18, spreadRadius: 1)]),
              child: const FootballIcon(size: 34),
            ),
            const SizedBox(height: 3),
            const Text('حدث', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF39FF88))),
          ]),
        );
      },
    );
  }
}

// ---------- صفحة التصويت ----------
class FootballScreen extends StatefulWidget {
  const FootballScreen({super.key});

  @override
  State<FootballScreen> createState() => _FootballState();
}

class _FootballState extends State<FootballScreen> with SingleTickerProviderStateMixin {
  late final AnimationController anim = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  Timer? tk;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    tk = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tk?.cancel();
    anim.dispose();
    super.dispose();
  }

  Future<void> _vote(String t) async {
    if (busy) return;
    setState(() => busy = true);
    final e = await fbCall('vote', {'t': t});
    if (!mounted) return;
    setState(() => busy = false);
    if (e.isNotEmpty) fbToast(e);
  }

  void _info(String title, Map<dynamic, dynamic> team) {
    final names = team.values.map((e) => e.toString()).toList();
    showAppSheet<void>(context, (sc) => [
          Text('مصوّتو $title (${names.length})', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          if (names.isEmpty) const Text('لا أحد بعد', textAlign: TextAlign.center, style: TextStyle(color: kMu)),
          for (final n in names) Text('• $n', style: const TextStyle(fontSize: 14, height: 1.7)),
        ]);
  }

  Widget _side(String t, bool bar, Map<dynamic, dynamic> voters, bool canVote, bool voted, String? mine, String? winner) {
    final label = bar ? 'برشلونة' : 'ريال مدريد';
    final team = voters[t] is Map ? voters[t] as Map : <dynamic, dynamic>{};
    final isMine = mine == t;
    final isWin = winner == t;
    return Expanded(
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [if (isMine || isWin) BoxShadow(color: (isWin ? const Color(0xFFFFD54A) : Colors.white).withAlpha(160), blurRadius: 22, spreadRadius: 2)]),
          child: Crest(bar: bar, size: 100),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 8),
        if (canVote && !voted)
          SizedBox(width: 110, child: AppButton(busy ? '...' : 'تصويت', compact: true, glow: true, onPressed: busy ? null : () => _vote(t)))
        else
          SizedBox(width: 110, child: AppButton('معلومات', kind: 'g', compact: true, onPressed: () => _info(label, team))),
        if (isMine) const Padding(padding: EdgeInsets.only(top: 6), child: Text('اختيارك ✅', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('رهان كرة القدم ⚽'), backgroundColor: const Color(0xFF0B4A1E)),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref('fb/cur').onValue,
        builder: (c, s) {
          final cur = s.data?.snapshot.value;
          if (cur is! Map || (cur['state'] ?? '') == 'cancelled') {
            return Center(child: Text('لا يوجد حدث الآن', style: TextStyle(color: c.accent2)));
          }
          final id = (cur['id'] ?? '').toString();
          final st = (cur['state'] ?? '').toString();
          final start = (cur['startTs'] as num?)?.toInt() ?? 0;
          final prize = (cur['prize'] as num?)?.toInt() ?? 0;
          final winner = (cur['winner'] ?? '').toString();
          final left = start - nowMs();
          final canVote = st == 'open' && left > 0;
          return StreamBuilder<DatabaseEvent>(
            stream: ref('fb/voters/$id').onValue,
            builder: (c2, s2) {
              final vv = s2.data?.snapshot.value;
              final voters = vv is Map ? vv : <dynamic, dynamic>{};
              String? mine;
              for (final t in ['rm', 'bar']) {
                final tm = voters[t];
                if (tm is Map && tm[myUid] != null) mine = t;
              }
              final voted = mine != null;
              return Stack(children: [
                Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B4A1E), _grass, Color(0xFF0F6B28)])))),
                Positioned(left: 0, right: 0, bottom: 0, height: 90, child: CustomPaint(painter: _GrassPainter())),
                // كرات تتحرك في الخلفية
                for (var i = 0; i < 5; i++)
                  AnimatedBuilder(
                    animation: anim,
                    builder: (_, __) {
                      final t = (anim.value + i / 5) % 1.0;
                      final w = MediaQuery.of(context).size.width;
                      return Positioned(
                        left: (w - 30) * ((i * 0.23 + .1) % 1.0),
                        bottom: 20 + 260 * math.sin(t * math.pi).abs(),
                        child: Opacity(opacity: .55, child: Transform.rotate(angle: t * 6.28, child: FootballIcon(size: 18.0 + (i % 3) * 8))),
                      );
                    },
                  ),
                ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 110), children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(14)),
                    child: const Text('عزيز المستخدم قم بالتصويت على الفريق الذي تظنه سيربح وإن ربح فعلا في المبارة ستحصل على الجائزة.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.7, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 14),
                  Center(child: Text('الجائزة: $prize رصيد', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFFFFD54A)))),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      st == 'done' ? 'انتهت المباراة' : (left > 0 ? 'يبدأ بعد: ${_fmtCd(left)}' : 'انتهى وقت التصويت'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _side('rm', false, voters, canVote, voted, mine, st == 'done' ? winner : null),
                    const Padding(padding: EdgeInsets.only(top: 36), child: Text('VS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white))),
                    _side('bar', true, voters, canVote, voted, mine, st == 'done' ? winner : null),
                  ]),
                  const SizedBox(height: 22),
                  if (st != 'done' && !canVote)
                    const Center(child: Text('جاري الكشف عن النتيجة...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white))),
                  if (st == 'done') _result(winner, prize, mine, id),
                ]),
              ]);
            },
          );
        },
      ),
    );
  }

  Widget _result(String winner, int prize, String? mine, String id) {
    final bar = winner == 'bar';
    final won = mine != null && mine == winner;
    final msg = mine == null
        ? 'تم إعلان الفائز'
        : (won ? 'تم اضافة الرصيد الى رصيدك $prize لانه قد فاز فريقك!' : 'فريقك خسر المباراة لم تحصل على شيء!');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(18), border: Border.all(color: won ? const Color(0xFFFFD54A) : Colors.white24, width: 2), boxShadow: [if (won) const BoxShadow(color: Color(0x88FFD54A), blurRadius: 24)]),
      child: Column(children: [
        Text(won ? '🏆 الفائز' : 'الفريق الفائز', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFFFFD54A))),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(tween: Tween<double>(begin: .3, end: 1), duration: const Duration(milliseconds: 700), curve: Curves.elasticOut, builder: (_, v, ch) => Transform.scale(scale: v, child: ch), child: Crest(bar: bar, size: 110)),
        const SizedBox(height: 8),
        Text(bar ? 'برشلونة' : 'ريال مدريد', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 10),
        Text(msg, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w800, color: won ? const Color(0xFF4CE07A) : Colors.white70)),
        const SizedBox(height: 10),
        FutureBuilder<DataSnapshot>(
          future: ref('fb/res/$id').get(),
          builder: (c, s) {
            final r = s.data?.value;
            if (r is! Map) return const SizedBox.shrink();
            final names = (r['winners'] is List) ? (r['winners'] as List).map((e) => e.toString()).toList() : <String>[];
            return Column(children: [
              Text('الفائزون: ${r['wcount'] ?? 0}   •   الخاسرون: ${r['lcount'] ?? 0}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
              if (names.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(names.join(' • '), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: Colors.white60, height: 1.6))),
            ]);
          },
        ),
      ]),
    );
  }
}

// ---------- أداة المطور: رهان كرة القدم ----------
class FootballAdminScreen extends StatefulWidget {
  const FootballAdminScreen({super.key});

  @override
  State<FootballAdminScreen> createState() => _FootballAdminState();
}

class _FootballAdminState extends State<FootballAdminScreen> {
  final TextEditingController prize = TextEditingController(text: '500');
  final TextEditingController mins = TextEditingController(text: '60');
  Timer? tk;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    tk = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tk?.cancel();
    prize.dispose();
    mins.dispose();
    super.dispose();
  }

  Future<void> _do(String k, [Map<String, Object?> extra = const {}]) async {
    if (busy) return;
    setState(() => busy = true);
    final e = await fbCall(k, extra);
    if (!mounted) return;
    setState(() => busy = false);
    if (e.isNotEmpty) {
      fbToast(e);
    } else {
      toast('تم ✅');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('رهان كرة القدم ⚽')),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref('fb/cur').onValue,
        builder: (c, s) {
          final cur = s.data?.snapshot.value;
          final active = cur is Map && cur['state'] != 'done' && cur['state'] != 'cancelled';
          if (!active) {
            return ListView(padding: const EdgeInsets.all(18), children: [
              const Text('أنشئ حدثاً جديداً: يظهر لكل الأعضاء زر «حدث» ليصوّتوا على الفريق الفائز (برشلونة أو ريال مدريد).', style: TextStyle(color: kMu, height: 1.7, fontSize: 13)),
              const SizedBox(height: 14),
              TextField(controller: prize, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد المكسب (الجائزة لكل فائز)')),
              const SizedBox(height: 12),
              TextField(controller: mins, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رجاءا ضع عدد الدقائق المتبقية حتى تبدأ المباراة')),
              const SizedBox(height: 16),
              AppButton(busy ? '...' : 'ابدأ', glow: true, onPressed: busy ? null : () => _do('create', {'p': int.tryParse(normDigits(prize.text.trim())) ?? 0, 'm': int.tryParse(normDigits(mins.text.trim())) ?? 0})),
              if (cur is Map && cur['state'] == 'done') const Padding(padding: EdgeInsets.only(top: 16), child: Text('آخر حدث انتهى ✅', textAlign: TextAlign.center, style: TextStyle(color: kMu))),
            ]);
          }
          final st = (cur['state'] ?? '').toString();
          final start = (cur['startTs'] as num?)?.toInt() ?? 0;
          final left = start - nowMs();
          return ListView(padding: const EdgeInsets.all(18), children: [
            Center(child: Text('الجائزة: ${cur['prize']} رصيد', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            const SizedBox(height: 8),
            Center(child: Text(left > 0 ? 'يبدأ بعد: ${_fmtCd(left)}' : 'انتهى وقت الحسم — أعلن الفائز', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: left > 0 ? c.accent2 : const Color(0xFFFFD54A)))),
            const SizedBox(height: 18),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [const Crest(bar: false, size: 90), const SizedBox(height: 6), const Text('ريال مدريد', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 8), if (left <= 0 || st == 'closed') AppButton('الفائز', compact: true, glow: true, onPressed: busy ? null : () => _do('result', {'t': 'rm'}))])),
              Expanded(child: Column(children: [const Crest(bar: true, size: 90), const SizedBox(height: 6), const Text('برشلونة', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 8), if (left <= 0 || st == 'closed') AppButton('الفائز', compact: true, glow: true, onPressed: busy ? null : () => _do('result', {'t': 'bar'}))])),
            ]),
            const SizedBox(height: 22),
            AppButton('إلغاء الحدث', kind: 'r', compact: true, onPressed: busy ? null : () => _do('cancel')),
          ]);
        },
      ),
    );
  }
}
