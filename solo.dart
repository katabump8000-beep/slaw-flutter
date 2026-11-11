import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'servertime.dart';
import 'sfx.dart';
import 'widgets.dart';

// ======================================================================
// اللعب المنفرد وكازينو الرهانات — كل النتائج والرصيد يحسمها السيرفر.
// التطبيق يرسل طلباً إلى gameReq ثم ينتظر الرد من gameRes/{uid}.
// ======================================================================

/// يرسل طلب لعبة ويرجع الرد. عند الفشل يرجع {'err': 'net' | 'rules' | 'timeout'}
Future<Map<dynamic, dynamic>> gameCall(String g, String a, [Map<String, Object?> extra = const {}]) async {
  final rid = ref('gameReq').push().key!;
  final done = Completer<Map<dynamic, dynamic>>();
  final sub = ref('gameRes/$myUid').onValue.listen((e) {
    final v = e.snapshot.value;
    if (v is Map && v['id'] == rid && !done.isCompleted) done.complete(v);
  }, onError: (_) {});
  String why = '';
  try {
    await ref('gameReq/$rid').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 'g': g, 'a': a, ...extra}).timeout(const Duration(seconds: 8));
  } catch (e) {
    why = e.toString().toLowerCase().contains('permission') ? 'rules' : 'net';
  }
  Map<dynamic, dynamic>? res;
  if (why.isEmpty) {
    try {
      res = await done.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      res = null;
    }
  }
  await sub.cancel();
  if (res != null) return res;
  return <dynamic, dynamic>{'err': why.isNotEmpty ? why : 'timeout'};
}

/// مؤثر صوتي قصير (يُحرَّر المشغّل بعد انتهائه)
void _sfx(String name, {double volume = 1}) {
  Sfx.start(name, volume: volume).then((p) {
    Future<void>.delayed(const Duration(seconds: 7), () {
      try {
        p.dispose();
      } catch (_) {}
    });
  }).catchError((_) {});
}

/// بطاقة نتيجة واضحة بزر إغلاق (بدل الرسائل الصغيرة)
Future<void> showResultCard(BuildContext context, {required String emoji, required String title, required List<String> lines, required Color color}) {
  return showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color, width: 2),
          boxShadow: [BoxShadow(color: color.withAlpha(110), blurRadius: 26)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 6),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 10),
          for (final l in lines.where((x) => x.isNotEmpty))
            Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.4))),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: AppButton('إغلاق', onPressed: () => Navigator.of(c).pop())),
        ]),
      ),
    ),
  );
}

String _fmtLeft(int ms) {
  final s = (ms / 1000).ceil();
  if (s >= 3600) return '${s ~/ 3600} ساعة و${(s % 3600) ~/ 60} دقيقة';
  if (s >= 60) return '${s ~/ 60} دقيقة و${s % 60} ثانية';
  return '$s ثانية';
}

/// رسالة مناسبة لخطأ اللعبة. ترجع true إن كان الخطأ يوقف اللعب
bool soloErr(Map<dynamic, dynamic> r) {
  final e = r['err'];
  if (e == null) return false;
  final l = (r['left'] as num?)?.toInt() ?? 0;
  switch (e) {
    case 'rules':
      toast('قواعد قاعدة البيانات لم تُحدَّث بعد (gameReq) — انشر ملف القواعد في Firebase', bad: true);
      break;
    case 'net':
      toast('لا يوجد اتصال بالإنترنت', bad: true);
      break;
    case 'timeout':
      toast('سيرفر المنصة لا يستجيب الآن (قد يكون نائماً)، حاول بعد دقيقة', bad: true);
      break;
    case 'banned':
      toast('حسابك محظور', bad: true);
      break;
    case 'off':
      toast('عذرا قام أحد المطورين بإيقاف هذه!', bad: true);
      break;
    case 'wait':
      toast('تقدر تلعب مجدداً بعد ${_fmtLeft(l)}', bad: true);
      break;
    case 'daily':
      toast('انتهت أدوارك لليوم، عد غداً', bad: true);
      break;
    case 'low':
      toast('رصيدك لا يكفي', bad: true);
      break;
    case 'bet':
      toast('الرهان من ${r['min'] ?? 10} إلى ${r['max'] ?? 500}', bad: true);
      break;
    case 'fast':
      break;
    case 'early':
      toast('انتظر انتهاء الخلط', bad: true);
      break;
    case 'busy':
      toast('لديك جولة مفتوحة، أكملها أولاً', bad: true);
      break;
    default:
      toast(Session.isDev ? 'تعذر تنفيذ الطلب [$e]' : 'تعذر تنفيذ الطلب، حاول مجدداً', bad: true);
  }
  return true;
}

// ---------------------------------------------------------------------
// القائمة الرئيسية
// ---------------------------------------------------------------------
class SoloHubScreen extends StatelessWidget {
  const SoloHubScreen({super.key});

  Widget _tile(BuildContext c, String emoji, String title, String sub, Widget Function() page, {bool off = false}) {
    return GestureDetector(
      onTap: () {
        if (off) {
          toast('عذرا قام أحد المطورين بإيقاف هذه!', bad: true);
          return;
        }
        Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => page()));
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: off ? const Color(0x33C0C8D2) : kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: off ? const Color(0xFFC0C8D2) : kLine),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 11.5, color: kMu)),
            ]),
          ),
          const Icon(Icons.chevron_left_rounded, color: kMu),
        ]),
      ),
    );
  }

  Widget _head(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(t, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c.accent2)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎮 الألعاب')),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref('config/off').onValue,
        builder: (c, snap) {
          final v = snap.data?.snapshot.value;
          final off = v is Map ? v : const {};
          bool o(String k) => off[k] == true;
          return ListView(padding: const EdgeInsets.all(16), children: [
            _head(context, 'لعب منفرد'),
            const SizedBox(height: 8),
            _tile(context, '🏳️', 'الأعلام', '5 أسئلة • 10 رصيد لكل إجابة • 3 مرات كل 16 دقيقة', () => const FlagsGameScreen(), off: o('flags')),
            const SizedBox(height: 8),
            _tile(context, '🎈', 'البالونات', '3 جولات كل 3 ساعات • احذر القنبلتين', () => const BalloonGameScreen(), off: o('balloon')),
            const SizedBox(height: 8),
            _tile(context, '❓', 'بطاقة الحظ', '3 مرات كل ساعتين', () => const LuckyCardScreen(), off: o('lucky')),
            const SizedBox(height: 18),
            _head(context, 'كازينو رهانات'),
            const SizedBox(height: 8),
            _tile(context, '💎', 'الكريستال', 'رهان حتى 500 • اضغط ! لمعرفة النسب', () => const CrystalGameScreen(), off: o('crystal')),
            const SizedBox(height: 8),
            _tile(context, '🥤', 'الأكواب', 'رهان حتى 500 • دوران يومياً', () => const CupsGameScreen(), off: o('cups')),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// الأعلام
// ---------------------------------------------------------------------
class FlagsGameScreen extends StatefulWidget {
  const FlagsGameScreen({super.key});

  @override
  State<FlagsGameScreen> createState() => _FlagsState();
}

class _FlagsState extends State<FlagsGameScreen> {
  bool busy = false;
  bool started = false;
  bool finished = false;
  int n = 5;
  int idx = 0;
  int ok = 0;
  int win = 0;
  String flag = '';
  List<String> opts = [];
  int picked = -1;
  int answer = -1;

  void _load(Map<dynamic, dynamic> q) {
    flag = (q['f'] ?? '').toString();
    opts = ((q['o'] as List?) ?? const []).map((e) => e.toString()).toList();
    picked = -1;
    answer = -1;
  }

  Future<void> _start() async {
    if (busy) return;
    setState(() => busy = true);
    final r = await gameCall('flags', 'start');
    if (!mounted) return;
    if (soloErr(r)) {
      setState(() => busy = false);
      return;
    }
    n = (r['n'] as num?)?.toInt() ?? 5;
    _load(Map<dynamic, dynamic>.from(r['q'] as Map));
    setState(() {
      started = true;
      finished = false;
      idx = 0;
      ok = 0;
      win = 0;
      busy = false;
    });
  }

  Future<void> _pick(int i) async {
    if (busy || picked >= 0) return;
    setState(() {
      busy = true;
      picked = i;
    });
    final r = await gameCall('flags', 'ans', {'i': i});
    if (!mounted) return;
    if (soloErr(r)) {
      setState(() {
        busy = false;
        picked = -1;
      });
      return;
    }
    answer = (r['answer'] as num?)?.toInt() ?? -1;
    ok = (r['ok'] as num?)?.toInt() ?? ok;
    win = (r['win'] as num?)?.toInt() ?? win;
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    if (r['done'] == true) {
      setState(() {
        finished = true;
        busy = false;
      });
      return;
    }
    idx = (r['i'] as num?)?.toInt() ?? idx + 1;
    _load(Map<dynamic, dynamic>.from(r['q'] as Map));
    setState(() => busy = false);
  }

  Color _optCol(int i) {
    if (answer < 0) return kCard;
    if (i == answer) return const Color(0xFF1F8A4C);
    if (i == picked) return const Color(0xFF9A2A2A);
    return kCard;
  }

  @override
  Widget build(BuildContext context) {
    final w = <Widget>[];
    if (!started || finished) {
      if (finished) {
        w.add(Center(child: Text(win > 0 ? '🎉 ربحت $win رصيد' : '💥 لم تربح هذه المرة', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))));
        w.add(Center(child: Text('إجابات صحيحة: $ok من $n', style: const TextStyle(color: kMu))));
      } else {
        w.add(const Center(child: Text('🏳️', style: TextStyle(fontSize: 80))));
        w.add(const Center(child: Text('خمّن اسم الدولة من علمها\n5 أسئلة، كل إجابة صحيحة = 10 رصيد', textAlign: TextAlign.center, style: TextStyle(color: kMu, height: 1.6))));
      }
      w.add(const SizedBox(height: 16));
      w.add(AppButton(busy ? '...' : (finished ? 'العب مجدداً' : 'ابدأ'), glow: true, onPressed: busy ? null : _start));
    } else {
      w.add(Center(child: Text('السؤال ${idx + 1} / $n   •   صحيح: $ok', style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800))));
      w.add(Center(child: Text(flag, style: const TextStyle(fontSize: 96))));
      for (var i = 0; i < opts.length; i++) {
        w.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GestureDetector(
            onTap: () => _pick(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _optCol(i), borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine)),
              child: Text(opts[i], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ));
      }
    }
    return Scaffold(appBar: AppBar(title: const Text('🏳️ الأعلام')), body: ListView(padding: const EdgeInsets.all(18), children: w));
  }
}

// ---------------------------------------------------------------------
// البالونات
// ---------------------------------------------------------------------
class BalloonGameScreen extends StatefulWidget {
  const BalloonGameScreen({super.key});

  @override
  State<BalloonGameScreen> createState() => _BalloonState();
}

class _BalloonState extends State<BalloonGameScreen> {
  static const int cells = 9;
  bool busy = false;
  bool active = false;
  bool over = false;
  String msg = 'اضغط ابدأ ثم افقع 3 بالونات. يوجد قنبلتان مخفيتان!';
  final Map<int, String> shown = {};
  final Set<int> bombs = {};
  final List<String> pops = [];
  int sum = 0;

  Future<void> _start() async {
    if (busy) return;
    setState(() => busy = true);
    final r = await gameCall('balloon', 'start');
    if (!mounted) return;
    if (soloErr(r)) {
      setState(() => busy = false);
      return;
    }
    setState(() {
      shown.clear();
      bombs.clear();
      pops.clear();
      sum = 0;
      active = true;
      over = false;
      busy = false;
      msg = 'افقع 3 بالونات (0/3)';
    });
  }

  Future<void> _pop(int i) async {
    if (busy || !active || shown.containsKey(i) || bombs.contains(i)) return;
    setState(() => busy = true);
    final r = await gameCall('balloon', 'pop', {'i': i});
    if (!mounted) return;
    if (soloErr(r)) {
      setState(() => busy = false);
      return;
    }
    if (r['bomb'] == true) {
      for (final b in (r['bombs'] as List?) ?? const []) {
        bombs.add((b as num).toInt());
      }
      bombs.add(i);
      _sfx('boom.wav');
      setState(() {
        active = false;
        over = true;
        busy = false;
        msg = '💥 قنبلة! خسرت جولتك';
      });
      await showResultCard(context, emoji: '💥', title: 'انفجرت القنبلة!', color: const Color(0xFFFF3B3B), lines: [
        if (pops.isNotEmpty) 'ضاعت مكاسب هذه الجولة: ${r['lost'] ?? sum}',
        'حاول مجدداً في الجولة القادمة',
      ]);
      return;
    }
    _sfx('pop.wav');
    shown[i] = '${r['e']}\n+${r['v']}';
    pops.add('${r['e']}  +${r['v']}');
    sum = (r['sum'] as num?)?.toInt() ?? (r['win'] as num?)?.toInt() ?? sum;
    if (r['done'] == true) {
      setState(() {
        active = false;
        over = true;
        busy = false;
        msg = '🎉 ربحت $sum رصيد!';
      });
      _sfx('win.wav');
      await showResultCard(context, emoji: '🎈', title: 'أحسنت! ربحت', color: const Color(0xFF39FF88), lines: [...pops, 'الجائزة: $sum']);
      return;
    }
    setState(() {
      busy = false;
      msg = 'افقع 3 بالونات (${shown.length}/3) — المجموع $sum';
    });
  }

  Widget _cell(int i) {
    final isBomb = bombs.contains(i);
    final txt = isBomb ? '💣' : shown[i];
    return GestureDetector(
      onTap: () => _pop(i),
      child: Container(
        decoration: BoxDecoration(
          color: txt != null ? kCard : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: txt != null ? kLine : Colors.transparent),
        ),
        alignment: Alignment.center,
        child: txt != null
            ? TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: .3, end: 1),
                duration: const Duration(milliseconds: 380),
                curve: Curves.elasticOut,
                builder: (_, v, ch) => Transform.scale(scale: v, child: ch),
                child: Text(txt, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.2)),
              )
            : const FittedBox(child: Padding(padding: EdgeInsets.all(2), child: Text('🎈', style: TextStyle(fontSize: 92)))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎈 البالونات')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Center(child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800, fontSize: 15))),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: .86,
          children: [for (var i = 0; i < cells; i++) _cell(i)],
        ),
        const SizedBox(height: 14),
        if (!active) AppButton(busy ? '...' : (over ? 'جولة جديدة' : 'ابدأ'), glow: true, onPressed: busy ? null : _start),
        const SizedBox(height: 10),
        const Center(child: Text('☘️ +10    ⭐ +20    💎 +50', style: TextStyle(color: kMu, fontSize: 13))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// بطاقة الحظ: بطاقة فوسفورية تمسحها بإصبعك فيظهر الإيموجي تدريجياً
// ---------------------------------------------------------------------
class LuckyCardScreen extends StatefulWidget {
  const LuckyCardScreen({super.key});

  @override
  State<LuckyCardScreen> createState() => _LuckyState();
}

class _LuckyState extends State<LuckyCardScreen> {
  static const int cols = 8;
  static const int rows = 10;
  bool busy = false;
  bool hasCard = false;
  bool done = false;
  String emoji = '';
  int value = 0;
  int left = -1;
  final List<List<Offset>> strokes = [];
  final Set<int> hit = {};
  int _lastSfx = 0;

  Future<void> _get() async {
    if (busy) return;
    // أخفِ البطاقة السابقة فوراً: لا يجب أن يظهر أي إيموجي قبل أن تكون البطاقة الجديدة مغطّاة
    setState(() {
      busy = true;
      hasCard = false;
      done = false;
      emoji = '';
      strokes.clear();
      hit.clear();
    });
    final r = await gameCall('lucky', 'play');
    if (!mounted) return;
    if (soloErr(r)) {
      setState(() => busy = false);
      return;
    }
    setState(() {
      emoji = (r['e'] ?? '').toString();
      value = (r['v'] as num?)?.toInt() ?? 0;
      left = (r['left'] as num?)?.toInt() ?? 0;
      hasCard = true;
      busy = false;
    });
  }

  void _touch(Offset p, Size sz, {bool start = false}) {
    if (done || !hasCard) return;
    if (start) strokes.add(<Offset>[]);
    strokes.last.add(p);
    // الخلايا التي مركزها داخل نصف قطر الفرشاة تُحسب ممسوحة
    final cw = sz.width / cols;
    final chh = sz.height / rows;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final c = Offset((x + .5) * cw, (y + .5) * chh);
        if ((c - p).distance <= 30) hit.add(y * cols + x);
      }
    }
    final n = nowMs();
    if (n - _lastSfx > 210) {
      _lastSfx = n;
      _sfx('scratch.wav', volume: .55);
    }
    // يظهر الربح عندما تُمسح منطقة الإيموجي (وسط البطاقة) لا كل البطاقة
    var center = 0;
    for (var y = 2; y <= 7; y++) {
      for (var x = 1; x <= 6; x++) {
        if (hit.contains(y * cols + x)) center++;
      }
    }
    if (center >= 24) {
      done = true;
      _sfx('win.wav');
      setState(() {});
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          showResultCard(context, emoji: emoji, title: 'بطاقة الحظ', color: const Color(0xFFD4FF00), lines: ['ظهر لك $emoji', 'الجائزة: $value رصيد']);
        }
      });
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final w = math.min(MediaQuery.of(context).size.width - 36, 360.0);
    final h = w * 1.28;
    final sz = Size(w, h);
    return Scaffold(
      appBar: AppBar(title: const Text('❓ بطاقة الحظ')),
      body: ListView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(18), children: [
        Center(
          child: SizedBox(
            width: w,
            height: h,
            child: !hasCard
                ? Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(22), border: Border.all(color: kLine)),
                    child: const Text('اضغط «بطاقة جديدة»\nثم امسحها بإصبعك', textAlign: TextAlign.center, style: TextStyle(color: kMu, fontSize: 16, height: 1.7)),
                  )
                : Stack(children: [
                    // الجائزة تحت الطبقة
                    Container(
                      width: w,
                      height: h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: const Color(0xFF0B1A0E), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF39FF14), width: 2)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(emoji, style: const TextStyle(fontSize: 120)),
                        Text('+$value', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Color(0xFFD4FF00))),
                      ]),
                    ),
                    // طبقة المسح الفوسفورية
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: done ? 0 : 1,
                        duration: done ? const Duration(milliseconds: 500) : Duration.zero,
                        // Listener (أحداث اللمس الخام) لا يدخل مسابقة الإيماءات: البطاقة ثابتة ولا تتحرك مع الإصبع
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (e) => _touch(e.localPosition, sz, start: true),
                          onPointerMove: (e) => _touch(e.localPosition, sz),
                          child: CustomPaint(size: sz, painter: _ScratchPainter(strokes, 26)),
                        ),
                      ),
                    ),
                  ]),
          ),
        ),
        const SizedBox(height: 16),
        const Center(child: Text('💎 20   ⭐ 10   🏆 30', style: TextStyle(color: kMu))),
        const SizedBox(height: 12),
        if (!hasCard || done) AppButton(busy ? '...' : 'بطاقة جديدة', glow: true, onPressed: busy ? null : _get),
        if (left >= 0) Padding(padding: const EdgeInsets.only(top: 10), child: Center(child: Text('متبقي لك $left من 3', style: const TextStyle(color: kMu, fontSize: 12)))),
      ]),
    );
  }
}

class _ScratchPainter extends CustomPainter {
  _ScratchPainter(this.strokes, this.r);
  final List<List<Offset>> strokes;
  final double r;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    canvas.drawRRect(
      rr,
      Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF39FF14), Color(0xFFD4FF00), Color(0xFF00FFAA)]).createShader(rect),
    );
    final tp = TextPainter(
      text: const TextSpan(text: '؟', style: TextStyle(fontSize: 170, fontWeight: FontWeight.w900, color: Color(0x5500330A))),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = r * 2;
    final dot = Paint()..blendMode = BlendMode.clear;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, r, dot);
      } else {
        final path = Path()..moveTo(s.first.dx, s.first.dy);
        for (final p in s.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, clear);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScratchPainter old) => true;
}

// ---------------------------------------------------------------------
// الكريستال
// ---------------------------------------------------------------------
class CrystalGameScreen extends StatefulWidget {
  const CrystalGameScreen({super.key});

  @override
  State<CrystalGameScreen> createState() => _CrystalState();
}

class _CrystalState extends State<CrystalGameScreen> with SingleTickerProviderStateMixin {
  late final AnimationController glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  final TextEditingController bet = TextEditingController(text: '50');
  bool busy = false;
  List<String> syms = ['', '', '', ''];
  List<bool> pop = [false, false, false, false];
  String hit = '';
  String msg = 'ضع رهانك (10 - 500) ثم لِف';
  Timer? spinT;
  dynamic spinP;

  @override
  void dispose() {
    spinT?.cancel();
    try {
      spinP?.stop();
    } catch (_) {}
    glow.dispose();
    bet.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (busy) return;
    final b = int.tryParse(normDigits(bet.text.trim()));
    if (b == null || b < 10 || b > 500) {
      toast('الرهان من 10 إلى 500', bad: true);
      return;
    }
    setState(() {
      busy = true;
      hit = '';
      msg = '...';
      syms = ['', '', '', ''];
    });
    final r = await gameCall('crystal', 'play', {'bet': b});
    if (!mounted) return;
    if (soloErr(r)) {
      setState(() {
        busy = false;
        msg = 'ضع رهانك (10 - 500) ثم لِف';
      });
      return;
    }
    final fin = ((r['s'] as List?) ?? const []).map((e) => e.toString()).toList();
    if (fin.length != 4) {
      setState(() => busy = false);
      return;
    }
    // لفّة 5.5 ثانية: الخانات تتوقف واحدة بعد الأخرى على رموز عشوائية ثم الرمز النهائي
    const pool = ['⭐', '🍒', '💣', '💎', '💠'];
    const stops = [2200, 3200, 4300, 5500];
    final rr = math.Random();
    final done = List<bool>.filled(4, false);
    final t0 = nowMs();
    setState(() => msg = 'جاري اللف...');
    _sfx('spin.wav', volume: .8);
    final c = Completer<void>();
    spinT = Timer.periodic(const Duration(milliseconds: 85), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final el = nowMs() - t0;
      setState(() {
        for (var i = 0; i < 4; i++) {
          if (el < stops[i]) {
            syms[i] = pool[rr.nextInt(pool.length)];
          } else if (!done[i]) {
            done[i] = true;
            syms[i] = fin[i];
            pop[i] = true;
            _sfx('reel_stop.wav', volume: .7);
            Future<void>.delayed(const Duration(milliseconds: 180), () {
              if (mounted) setState(() => pop[i] = false);
            });
          }
        }
      });
      if (el >= stops[3] + 60 && !c.isCompleted) {
        t.cancel();
        c.complete();
      }
    });
    await c.future;
    if (!mounted) return;
    final out = (r['out'] ?? '').toString();
    final back = (r['back'] as num?)?.toInt() ?? 0;
    final mult = r['mult'];
    final left = (r['left'] as num?)?.toInt();
    setState(() {
      hit = out == 'win' ? (r['hit'] ?? '').toString() : '';
      busy = false;
      msg = out == 'win' ? '🎉 فزت!' : (out == 'refund' ? 'تم استرجاع رصيدك' : '💥 لم تربح');
    });
    final tail = left == null ? '' : 'متبقي لك $left لفّات';
    if (out == 'win') {
      _sfx('win.wav');
      await showResultCard(context, emoji: hit, title: 'ربحت!', color: const Color(0xFF39FF88), lines: ['$hit  ×$mult', '$b × $mult = $back', 'الجائزة: $back', tail]);
    } else if (out == 'refund') {
      await showResultCard(context, emoji: '↩️', title: 'تم استرجاع رصيدك', color: const Color(0xFFFFD54A), lines: ['ظهرت قنبلة واحدة بلا 💎 أو 💠', 'لا توجد خسارة أو ربح', tail]);
    } else {
      _sfx('lose.wav');
      final bombs = (r['bombs'] as num?)?.toInt() ?? 0;
      await showResultCard(context, emoji: '💥', title: 'خسرت', color: const Color(0xFFFF3B3B), lines: [bombs >= 2 ? 'ظهرت $bombs قنابل 💣' : 'لا يوجد تكرار — لم تربح شيئاً', 'خسرت رهانك: $b', tail]);
    }
  }

  void _info() {
    showAppSheet<void>(context, (sc) => [
          const Text('💎 جدول الكريستال', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Text('⭐ ظهور 25٪ — ×2\n🍒 ظهور 30٪ — ×1.5\n💣 ظهور 30٪ — خسارة الرهان\n💎 ظهور 10٪ — ×3.5\n💠 ظهور 5٪ — ×6', style: TextStyle(height: 1.9, fontSize: 14)),
          const Text(
            'يُحسب أكثر إيموجي تكراراً (مرتان فأكثر) ويتوهج.\n'
            '• قنبلتان أو أكثر = خسارة الرهان.\n'
            '• قنبلة واحدة بلا 💎 أو 💠 = استرجاع الرهان.\n'
            '• 💎 أو 💠 تُبطل أثر القنبلة الواحدة.\n'
            '• بلا تكرار = لا ربح (تخسر رهانك).\n'
            '• الحد 7 لفّات كل 12 ساعة، والرهان حتى 500.',
            style: TextStyle(color: kMu, height: 1.7, fontSize: 12.5),
          ),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('💎 الكريستال'), actions: [IconButton(onPressed: _info, icon: const Icon(Icons.info_outline_rounded))]),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Center(child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800, fontSize: 15))),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: glow,
          builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 4; i++)
              AnimatedScale(
                scale: pop[i] ? 1.18 : 1,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  width: 70,
                  height: 84,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: hit.isNotEmpty && syms[i] == hit ? const Color(0xFFFFD54A) : kLine, width: hit.isNotEmpty && syms[i] == hit ? 2 : 1),
                    boxShadow: hit.isNotEmpty && syms[i] == hit ? [BoxShadow(color: const Color(0xFFFFB000).withAlpha(120 + (90 * glow.value).toInt()), blurRadius: 10 + 14 * glow.value)] : null,
                  ),
                  child: Text(syms[i], style: const TextStyle(fontSize: 38)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: bet,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(labelText: 'الرهان (حتى 500)'),
        ),
        const SizedBox(height: 14),
        AppButton(busy ? '...' : 'لِف 💎', glow: true, onPressed: busy ? null : _play),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// الأكواب (Three Cups)
// ---------------------------------------------------------------------
class CupsGameScreen extends StatefulWidget {
  const CupsGameScreen({super.key});

  @override
  State<CupsGameScreen> createState() => _CupsState();
}

class _CupsState extends State<CupsGameScreen> with TickerProviderStateMixin {
  static const List<String> lvNames = ['سهل ×1.1', 'متوسط ×1.3', 'صعب ×2', 'جننوني ×3'];
  final TextEditingController bet = TextEditingController(text: '100');
  int lv = 1;
  bool busy = false;
  String phase = 'idle'; // idle | show | shuffle | pick | done
  String msg = 'احفظ مكان الكرة 🟢 ثم تابع الأكواب';
  // slot[i] = رقم الكوب الذي يقف الآن في الخانة i
  List<int> slotOf = [0, 1, 2]; // cup -> slot
  int revealCup = -1;
  late AnimationController lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  AnimationController? swapC;
  int swapA = -1;
  int swapB = -1;
  bool cancelled = false;
  bool _alive = true;

  @override
  void initState() {
    super.initState();
    lift.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _alive = false;
    cancelled = true;
    swapC?.dispose();
    lift.dispose();
    bet.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (busy) return;
    final b = int.tryParse(normDigits(bet.text.trim()));
    if (b == null || b < 10 || b > 500) {
      toast('الرهان من 10 إلى 500', bad: true);
      return;
    }
    setState(() {
      busy = true;
      msg = '...';
    });
    final r = await gameCall('cups', 'start', {'bet': b, 'lv': lv + 1});
    if (!mounted) return;
    if (soloErr(r)) {
      setState(() {
        busy = false;
        msg = 'احفظ مكان الكرة 🟢 ثم تابع الأكواب';
      });
      return;
    }
    final pos = (r['pos'] as num?)?.toInt() ?? 0;
    final swaps = ((r['swaps'] as List?) ?? const []).map((e) => (e as List).map((x) => (x as num).toInt()).toList()).toList();
    slotOf = [0, 1, 2];
    revealCup = pos;
    lift.value = 0;
    setState(() {
      phase = 'show';
      msg = 'احفظ مكان الكرة 🟢';
    });
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!_alive) return;
    await lift.forward(from: 0); // غطاء ينزل
    if (!_alive) return;
    revealCup = -1;
    setState(() {
      phase = 'shuffle';
      msg = 'تابع الكرة...';
    });
    for (final s in swaps) {
      if (!_alive || cancelled) return;
      await _swap(s[0], s[1], s[2]);
    }
    if (!_alive) return;
    setState(() {
      phase = 'pick';
      busy = false;
      msg = 'أين الكرة؟';
    });
  }

  // تبديل محتوى الخانتين a و b (مواقع على الشاشة)
  Future<void> _swap(int a, int b, int ms) async {
    swapA = a;
    swapB = b;
    swapC?.dispose();
    swapC = AnimationController(vsync: this, duration: Duration(milliseconds: ms));
    swapC!.addListener(() {
      if (mounted) setState(() {});
    });
    await swapC!.forward();
    // بعد الحركة: نبدّل الكوبين اللذين كانا في الخانتين
    final ca = slotOf.indexOf(a);
    final cb = slotOf.indexOf(b);
    slotOf[ca] = b;
    slotOf[cb] = a;
    swapA = -1;
    swapB = -1;
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  // موضع الكوب (الخانة الحالية) أثناء الحركة
  double _slotX(int cup) {
    var s = slotOf[cup].toDouble();
    if (swapA >= 0 && swapC != null) {
      final t = Curves.easeInOut.transform(swapC!.value);
      if (slotOf[cup] == swapA) s = swapA + (swapB - swapA) * t;
      if (slotOf[cup] == swapB) s = swapB + (swapA - swapB) * t;
    }
    return s;
  }

  Future<void> _pickCup(int cup) async {
    if (phase != 'pick' || busy) return;
    setState(() => busy = true);
    final slot = slotOf[cup];
    final r = await gameCall('cups', 'pick', {'i': slot});
    if (!mounted) return;
    if (soloErr(r)) {
      setState(() => busy = false);
      return;
    }
    final win = r['win'] == true;
    final ballSlot = (r['ball'] as num?)?.toInt() ?? 0;
    revealCup = slotOf.indexOf(ballSlot);
    final net = (r['net'] as num?)?.toInt() ?? 0;
    setState(() {
      phase = 'done';
      busy = false;
      msg = win ? '🎉 أصبت! ربحت ${fmtN(net)} رصيد' : '💥 أخطأت! خسرت رهانك';
    });
  }

  Widget _cup(int cup, double w) {
    final x = _slotX(cup) * (w / 3) + (w / 3 - 70) / 2;
    final reveal = revealCup == cup;
    final up = (phase == 'show' || phase == 'done') && reveal;
    final dy = phase == 'show' ? (-40 * (1 - lift.value)) * (reveal ? 1 : 0) : (up ? -40.0 : 0.0);
    return Positioned(
      left: x,
      top: 60,
      child: GestureDetector(
        onTap: () => _pickCup(cup),
        child: SizedBox(
          width: 70,
          height: 100,
          child: Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
            if (reveal && (phase == 'show' || phase == 'done')) const Positioned(bottom: 2, child: Text('🟢', style: TextStyle(fontSize: 30))),
            Transform.translate(
              offset: Offset(0, dy),
              child: Container(
                width: 66,
                height: 90,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE04B4B), Color(0xFF8E1F1F)]),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10), bottom: Radius.circular(24)),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4))],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playing = phase == 'show' || phase == 'shuffle' || phase == 'pick';
    return Scaffold(
      appBar: AppBar(title: const Text('🥤 الأكواب')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Center(child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800, fontSize: 15))),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (c, cs) {
          final w = cs.maxWidth;
          return SizedBox(height: 190, child: Stack(children: [for (var i = 0; i < 3; i++) _cup(i, w)]));
        }),
        if (!playing) ...[
          const SizedBox(height: 8),
          TextField(controller: bet, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(labelText: 'الرهان (حتى 500)')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (var i = 0; i < lvNames.length; i++)
              ChoiceChip(label: Text(lvNames[i]), selected: lv == i, onSelected: (_) => setState(() => lv = i)),
          ]),
          const SizedBox(height: 14),
          AppButton(busy ? '...' : 'ابدأ الرهان', glow: true, onPressed: busy ? null : _start),
          const SizedBox(height: 8),
          const Center(child: Text('دوران فقط كل يوم', style: TextStyle(color: kMu, fontSize: 12))),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// الفعاليات الجماعية: السيرفر يديرها، والتطبيق يرسل طلب البدء فقط
// ---------------------------------------------------------------------
Future<String> evCall(String gid, String kind, [Map<String, Object?> extra = const {}]) async {
  final rid = ref('evReq').push().key!;
  final done = Completer<Map<dynamic, dynamic>>();
  final sub = ref('evRes/$myUid').onValue.listen((e) {
    final v = e.snapshot.value;
    if (v is Map && v['id'] == rid && !done.isCompleted) done.complete(v);
  }, onError: (_) {});
  String why = '';
  try {
    await ref('evReq/$rid').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 'g': gid, 'k': kind, ...extra}).timeout(const Duration(seconds: 8));
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
  final err = (r['err'] ?? '').toString();
  if (err == 'bet' && r['max'] != null) return 'bet:${r['max']}';
  if (err == 'min' && r['min'] != null) return 'min:${r['min']}';
  if (err == 'server' && r['m'] != null) return 'server:${r['m']}';
  return err;
}

void evToastPublic(String err) => _evToast(err);

void _evToast(String err) {
  final e = err.split(':').first;
  final n = err.contains(':') ? err.split(':').last : '';
  switch (e) {
    case 'rules':
      toast('قواعد قاعدة البيانات لم تُحدَّث بعد (evReq)', bad: true);
      break;
    case 'net':
      toast('لا يوجد اتصال بالإنترنت', bad: true);
      break;
    case 'timeout':
      toast('سيرفر المنصة لا يستجيب الآن، حاول بعد دقيقة', bad: true);
      break;
    case 'off':
      toast('عذرا قام أحد المطورين بإيقاف هذه!', bad: true);
      break;
    case 'busy':
      toast('هناك فعالية قيد التشغيل في هذا القروب', bad: true);
      break;
    case 'perm':
      toast('ليس لديك صلاحية الألعاب', bad: true);
      break;
    case 'low':
      toast('رصيدك لا يكفي', bad: true);
      break;
    case 'bet':
      toast('الرهان من 10 إلى ${n.isEmpty ? 5000 : n}', bad: true);
      break;
    case 'min':
      toast('رهانك لا يقل عن رهان المنشئ ($n)', bad: true);
      break;
    case 'turn':
      toast('ليس دورك الآن', bad: true);
      break;
    case 'illegal':
      toast('حركة غير مسموحة', bad: true);
      break;
    case 'self':
      toast('لا يمكنك قبول تحديك أنت', bad: true);
      break;
    case 'taken':
      toast('سبقك أحد في قبول التحدي', bad: true);
      break;
    case 'wait':
      toast('لحظة...', bad: true);
      break;
    case 'dup':
      toast('سبق أن شاركت أو اخترت', bad: true);
      break;
    case 'full':
      toast('اكتمل عدد المشاركين', bad: true);
      break;
    case 'few':
      toast('يجب أن يشارك 3 أعضاء على الأقل', bad: true);
      break;
    case 'notpart':
      toast('عذرا انت لست مشاركا!', bad: true);
      break;
    case 'none':
      toast('انتهت هذه الفعالية', bad: true);
      break;
    case 'group':
      toast('الفعاليات تعمل داخل النقابات فقط', bad: true);
      break;
    case 'banned':
      toast('حسابك محظور', bad: true);
      break;
    case 'bad':
      toast('بيانات الطلب غير صحيحة', bad: true);
      break;
    case 'server':
      toast(Session.isDev ? 'خطأ في السيرفر: ${n.isEmpty ? '' : n}' : 'تعذر تنفيذ الطلب، حاول مجدداً', bad: true);
      break;
    default:
      toast(Session.isDev ? 'تعذر تنفيذ الطلب [$e]' : 'تعذر تنفيذ الطلب', bad: true);
  }
}

Future<void> startEvent(String gid, String kind) async {
  final e = await evCall(gid, kind);
  if (e.isNotEmpty) _evToast(e);
}

/// أزرار بطاقات الفعاليات (مشاركة / بدأ / اختيار قلب)
Future<void> evAct(String gid, String act, Map<String, Object?> extra) async {
  final e = await evCall(gid, act, extra);
  if (e.isNotEmpty) _evToast(e);
}

/// «الحدس»: يسأل المنشئ عن الرهان (حتى 5000) ثم يطلب من السيرفر إنشاء الفعالية
Future<void> startHeart(BuildContext context, String gid) async {
  final c = TextEditingController(text: '100');
  final b = await showDialog<int>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('رهان الحدس'),
      content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رهانك (حتى 5000)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(d, int.tryParse(normDigits(c.text.trim()))), child: const Text('إنشاء')),
      ],
    ),
  );
  if (b == null) return;
  final e = await evCall(gid, 'heart', {'bet': b});
  if (e.isNotEmpty) _evToast(e);
}

/// «تحدي الشطرنج»: لا يحتاج إذناً. يحدد المنشئ الرهان ثم تظهر بطاقة بانتظار خصم
Future<void> startChess(BuildContext context, String gid) async {
  final c = TextEditingController(text: '100');
  final b = await showDialog<int>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('♟ تحدي الشطرنج'),
      content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'قيمة الرهان (حتى 5000)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(d, int.tryParse(normDigits(c.text.trim()))), child: const Text('إنشاء')),
      ],
    ),
  );
  if (b == null) return;
  final e = await evCall(gid, 'chess', {'bet': b});
  if (e.isNotEmpty) _evToast(e);
}

/// «رهان البالونات» الجماعي (غير لعبة البالونات الفردية): المنشئ يحدد الرهان ثم السيرفر ينشئ البطاقة
Future<void> startBalloonBet(BuildContext context, String gid) async {
  final c = TextEditingController(text: '100');
  final b = await showDialog<int>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('رهان البالونات'),
      content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رهانك (حتى 5000)')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(d, int.tryParse(normDigits(c.text.trim()))), child: const Text('إنشاء')),
      ],
    ),
  );
  if (b == null) return;
  final e = await evCall(gid, 'balloon', {'bet': b});
  if (e.isNotEmpty) _evToast(e);
}

/// «تعديل جوائز»: جائزة كل فعالية جماعية (للمطورين والإمبراطور)
class EventPrizesScreen extends StatefulWidget {
  const EventPrizesScreen({super.key});

  @override
  State<EventPrizesScreen> createState() => _EventPrizesState();
}

class _EventPrizesState extends State<EventPrizesScreen> {
  static const items = <List<String>>[
    ['colors', 'فعالية الألوان 🎨'],
    ['type', 'فعالية الكتابة ⌨️'],
    ['scramble', 'فعالية التفكيك 🧩'],
    ['emoji', 'فعالية الايموجي 😀'],
  ];
  final Map<String, TextEditingController> cs = {for (final i in items) i[0]: TextEditingController(text: '40')};
  bool saving = false;

  @override
  void initState() {
    super.initState();
    ref('config/evPrize').get().then((s) {
      final v = s.value;
      if (v is Map && mounted) {
        v.forEach((k, x) {
          if (cs[k.toString()] != null && x is num) cs[k.toString()]!.text = x.toInt().toString();
        });
        setState(() {});
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in cs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final up = <String, Object?>{};
      cs.forEach((k, c) {
        final n = int.tryParse(normDigits(c.text.trim())) ?? 40;
        up['config/evPrize/$k'] = n.clamp(0, 100000);
      });
      await db.ref().update(up);
      toast('تم حفظ الجوائز', accent: true);
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل جوائز')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('جائزة الفائز بكل فعالية جماعية (رصيد). الرهانات مثل الكريستال لها جوائزها الثابتة.', style: TextStyle(color: kMu, fontSize: 12.5, height: 1.7)),
        const SizedBox(height: 10),
        for (final i in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextField(controller: cs[i[0]], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: i[1])),
          ),
        const SizedBox(height: 10),
        AppButton(saving ? '...' : 'حفظ', glow: true, onPressed: saving ? null : _save),
      ]),
    );
  }
}

/// أسماء إجابات الفعاليات (إيموجي/ألوان/حيوانات): لا تُعدّ مخالفة أثناء فعالية جارية
const Set<String> _evSafe = {
  'كلب', 'قطه', 'قط', 'هره', 'اسد', 'حصان', 'جمل', 'فراشه', 'قنبله', 'نار', 'قلب', 'تاج', 'نجمه', 'قمر', 'هلال', 'شمس', 'ورده',
  'تفاحه', 'تفاح', 'موزه', 'موز', 'سياره', 'طياره', 'كره', 'هديه', 'مفتاح', 'شجره', 'ساعه', 'منبه', 'جوال', 'هاتف', 'موبايل',
  'بيت', 'منزل', 'بالون', 'بيتزا', 'برق', 'صاعقه', 'ثلج', 'بطيخ', 'احمر', 'ازرق', 'اخضر', 'اصفر', 'بنفسجي', 'برتقالي', 'بني',
  'زهري', 'وردي', 'رمادي', 'فضي', 'حمار', 'ثور', 'خنزير', 'تيس', 'ذئب', 'ثعلب', 'قرد', 'فيل', 'نمر', 'دب',
};

String _evNorm(String s) => s
    .replaceAll(RegExp('[\u064B-\u0652\u0640]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp('[يى]'), 'ي')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .replaceAll(RegExp(r'\s+'), '')
    .toLowerCase();

bool evSafeWord(String t) => _evSafe.contains(_evNorm(t.trim()));

/// إلغاء الفعالية الجارية في القروب (السيرفر يتحقق من الصلاحية والشروط)
Future<void> cancelEvent(String gid) async {
  try {
    await ref('evReq/${ref('evReq').push().key}').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 'g': gid, 'k': 'cancel'}).timeout(const Duration(seconds: 8));
    toast('تم إرسال طلب الإلغاء');
  } catch (_) {
    toast('تعذر إلغاء الفعالية', bad: true);
  }
}

/// «إعادة ضبط»: ينهي أي فعالية عالقة في كل النقابات (للمطورين والإمبراطور)
Future<void> resetEvents(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('إعادة ضبط الفعاليات'),
      content: const Text('هذا الخيار هو خيار لجعل اي فعالية عالقة تختفي وينتهي مسارها هل انت واثق من ايقاف كلشي؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لا')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('نعم')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref('evReq/${ref('evReq').push().key}').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 'g': 'all', 'k': 'resetall'}).timeout(const Duration(seconds: 8));
    toast('تم إنهاء كل الفعاليات العالقة', accent: true);
  } catch (_) {
    toast('تعذر تنفيذ إعادة الضبط', bad: true);
  }
}
