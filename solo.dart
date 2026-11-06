import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
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
      toast('تعذر تنفيذ الطلب، حاول مجدداً', bad: true);
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
  final Map<int, String> shown = {}; // الخلية -> نص ظاهر (إيموجي + قيمة)
  final Set<int> bombs = {};
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
      setState(() {
        active = false;
        over = true;
        busy = false;
        msg = '💥 قنبلة! خسرت جولتك';
      });
      return;
    }
    shown[i] = '${r['e']}\n+${r['v']}';
    sum = (r['sum'] as num?)?.toInt() ?? (r['win'] as num?)?.toInt() ?? sum;
    if (r['done'] == true) {
      setState(() {
        active = false;
        over = true;
        busy = false;
        msg = '🎉 ربحت $sum رصيد!';
      });
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: txt != null ? kCard : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: txt != null ? kLine : Colors.transparent),
        ),
        alignment: Alignment.center,
        child: txt != null
            ? Text(txt, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.2))
            : const Text('🎈', style: TextStyle(fontSize: 46)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎈 البالونات')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Center(child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800))),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [for (var i = 0; i < cells; i++) _cell(i)],
        ),
        const SizedBox(height: 16),
        if (!active) AppButton(busy ? '...' : (over ? 'جولة جديدة' : 'ابدأ'), glow: true, onPressed: busy ? null : _start),
        const SizedBox(height: 10),
        const Center(child: Text('☘️ +10    ⭐ +20    💎 +50', style: TextStyle(color: kMu, fontSize: 12))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// بطاقة الحظ الصفراء
// ---------------------------------------------------------------------
class LuckyCardScreen extends StatefulWidget {
  const LuckyCardScreen({super.key});

  @override
  State<LuckyCardScreen> createState() => _LuckyState();
}

class _LuckyState extends State<LuckyCardScreen> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  bool busy = false;
  String emoji = '';
  int value = 0;
  int left = -1;

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (busy) return;
    setState(() {
      busy = true;
      emoji = '';
    });
    final r = await gameCall('lucky', 'play');
    if (!mounted) return;
    if (soloErr(r)) {
      setState(() => busy = false);
      return;
    }
    c.reset();
    await c.forward();
    if (!mounted) return;
    setState(() {
      emoji = (r['e'] ?? '').toString();
      value = (r['v'] as num?)?.toInt() ?? 0;
      left = (r['left'] as num?)?.toInt() ?? 0;
      busy = false;
    });
    toast('🎉 ربحت $value رصيد');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('❓ بطاقة الحظ')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: c,
            builder: (_, __) {
              final flip = c.value;
              final showFront = flip > .5 && emoji.isNotEmpty;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY((flip < .5 ? flip : flip - 1) * math.pi),
                child: Container(
                  width: 190,
                  height: 250,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE680), Color(0xFFFFB000)]),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Color(0x88FFB000), blurRadius: 24)],
                  ),
                  child: showFront
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(emoji, style: const TextStyle(fontSize: 70)),
                          Text('+$value', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF3A2400))),
                        ])
                      : const Text('؟', style: TextStyle(fontSize: 120, fontWeight: FontWeight.w900, color: Color(0xFF3A2400))),
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          const Text('💎 20   ⭐ 10   🏆 30', style: TextStyle(color: kMu)),
          const SizedBox(height: 14),
          SizedBox(width: 220, child: AppButton(busy ? '...' : 'اكشف البطاقة', glow: true, onPressed: busy ? null : _play)),
          if (left >= 0) Padding(padding: const EdgeInsets.only(top: 10), child: Text('متبقي لك $left من 3', style: const TextStyle(color: kMu, fontSize: 12))),
        ]),
      ),
    );
  }
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
  List<String> syms = ['❔', '❔', '❔', '❔'];
  String hit = '';
  String msg = 'ضع رهانك (10 - 500) ثم لِف';
  Timer? spinT;

  @override
  void dispose() {
    spinT?.cancel();
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
    });
    // دوران بصري فقط أثناء انتظار رد السيرفر
    const pool = ['⭐', '🍒', '💣', '💎', '💠'];
    final rr = math.Random();
    spinT = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (mounted) setState(() => syms = List<String>.generate(4, (_) => pool[rr.nextInt(pool.length)]));
    });
    final r = await gameCall('crystal', 'play', {'bet': b});
    spinT?.cancel();
    if (!mounted) return;
    if (soloErr(r)) {
      setState(() {
        busy = false;
        syms = ['❔', '❔', '❔', '❔'];
        msg = 'ضع رهانك (10 - 500) ثم لِف';
      });
      return;
    }
    final s = ((r['s'] as List?) ?? const []).map((e) => e.toString()).toList();
    final out = (r['out'] ?? '').toString();
    final net = (r['net'] as num?)?.toInt() ?? 0;
    setState(() {
      if (s.length == 4) syms = s;
      hit = out == 'win' ? (r['hit'] ?? '').toString() : '';
      busy = false;
      msg = out == 'win'
          ? '🎉 ربحت ${fmtN(net)} رصيد (×${r['mult']})'
          : out == 'refund'
              ? 'لم تربح شيء، تم استرجاع رصيدك'
              : '💥 خسرت ${fmtN(-net)} رصيد';
    });
  }

  void _info() {
    showAppSheet<void>(context, (sc) => [
          const Text('💎 جدول الكريستال', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Text('⭐ ظهور 25٪ — ×2\n🍒 ظهور 25٪ — ×1.5\n💣 ظهور 40٪ — خسارة الرهان\n💎 ظهور 8٪ — ×3.5\n💠 ظهور 2٪ — ×6', style: TextStyle(height: 1.9, fontSize: 14)),
          const Text(
            'يُحسب أكثر إيموجي تكراراً (مرتان فأكثر) ويتوهج.\n'
            '• قنبلتان أو أكثر = خسارة الرهان.\n'
            '• قنبلة واحدة بلا 💎 أو 💠 = استرجاع الرهان.\n'
            '• 💎 أو 💠 تُبطل أثر القنبلة الواحدة.\n'
            '• بلا تكرار = استرجاع الرهان.',
            style: TextStyle(color: kMu, height: 1.7, fontSize: 12.5),
          ),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final cnt = <String, int>{};
    for (final s in syms) {
      cnt[s] = (cnt[s] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('💎 الكريستال'), actions: [IconButton(onPressed: _info, icon: const Icon(Icons.info_outline_rounded))]),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Center(child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800, fontSize: 15))),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: glow,
          builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final s in syms)
              Container(
                width: 70,
                height: 84,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: hit.isNotEmpty && s == hit ? const Color(0xFFFFD54A) : kLine, width: hit.isNotEmpty && s == hit ? 2 : 1),
                  boxShadow: hit.isNotEmpty && s == hit ? [BoxShadow(color: const Color(0xFFFFB000).withAlpha(120 + (90 * glow.value).toInt()), blurRadius: 10 + 14 * glow.value)] : null,
                ),
                child: Text(s, style: const TextStyle(fontSize: 38)),
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
