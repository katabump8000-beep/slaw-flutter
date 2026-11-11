import 'zain.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'data.dart';
import 'sfx.dart';
import 'widgets.dart';

// ======================================================================
// وضع «بدون إنترنت»: شاشة البداية + لعبة القفز (10 مراحل) + استعادة الاتصال
// ======================================================================

const int kDinoStages = 10;
const int kDinoPerStage = 10; // شوكات كل مرحلة
const int kDinoPrizeStep = 10; // جائزة المرحلة n = 10×n (المرحلة 10 = 100)

void _s(String n) {
  Sfx.start(n).then((p) {
    Future<void>.delayed(const Duration(seconds: 6), () {
      try {
        p.dispose();
      } catch (_) {}
    });
  }).catchError((_) {});
}

/// يراقب عودة الاتصال: تظهر بطاقة ثم يُغلق التطبيق ليدخل العضو طبيعياً في المرة القادمة
StreamSubscription<DatabaseEvent> watchConnectionRestore(BuildContext context) {
  var wasOff = false;
  var shown = false;
  return FirebaseDatabase.instance.ref('.info/connected').onValue.listen((e) {
    if (prefs.getBool('lite_mode') ?? false) return; // وضع التوفير ثابت: لا نخرج المستخدم عند عودة الاتصال
    final on = e.snapshot.value == true;
    if (!on) {
      wasOff = true;
      return;
    }
    if (wasOff && !shown && context.mounted) {
      shown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (d) => const AlertDialog(
          title: Text('📶 تم استعادة الاتصال'),
          content: Text('تم استعادة الاتصال بالانترنت... عاود الدخول للبرنامج مجددا.'),
        ),
      );
      Future<void>.delayed(const Duration(milliseconds: 2200), () => SystemNavigator.pop());
    }
  }, onError: (_) {});
}

/// جائزة اللعبة المسحوبة دون اتصال: تُطلب من السيرفر عند أول دخول بعد عودة الإنترنت
Future<void> claimDino() async {
  final n = prefs.getInt('dino_pending') ?? 0;
  if (n <= 0) return;
  final rid = ref('dinoReq').push().key!;
  final done = Completer<Map<dynamic, dynamic>>();
  final sub = ref('dinoRes/$myUid').onValue.listen((e) {
    final v = e.snapshot.value;
    if (v is Map && v['id'] == rid && !done.isCompleted) done.complete(v);
  }, onError: (_) {});
  try {
    await ref('dinoReq/$rid').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 'n': math.min(100, math.max(1, n))}).timeout(const Duration(seconds: 8));
    final r = await done.future.timeout(const Duration(seconds: 30));
    final err = (r['err'] ?? '').toString();
    prefs.setInt('dino_pending', 0);
    if (err.isEmpty) {
      toast('🎮 تمت إضافة جائزة اللعبة: $n رصيد', accent: true);
    } else if (err == 'daily') {
      toast('الجائزة تُمنح مرة واحدة كل 24 ساعة', bad: true);
    }
  } catch (_) {
    // فشل الاتصال: نُبقي الجائزة لمحاولة لاحقة
  }
  await sub.cancel();
}

// ---------- شاشة البداية بدون اتصال ----------
class OfflineStartScreen extends StatefulWidget {
  final VoidCallback onRetry;
  final VoidCallback onOut;
  const OfflineStartScreen({super.key, required this.onRetry, required this.onOut});

  @override
  State<OfflineStartScreen> createState() => _OfflineStartState();
}

class _OfflineStartState extends State<OfflineStartScreen> {
  StreamSubscription<DatabaseEvent>? sub;

  @override
  void initState() {
    super.initState();
    sub = watchConnectionRestore(context);
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('⚠️', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 10),
                const Text('عذرا..!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('رجاءا قم بالتحقق من الاتصال بالانترنت لديك!', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: kMu, height: 1.7)),
                const SizedBox(height: 26),
                AppButton('العب بدون انترنت', glow: true, onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DinoScreen()))),
                const SizedBox(height: 10),
                AppButton('توفير الإنترنت', kind: 'g', onPressed: () {
                  prefs.setBool('lite_mode', true); // ثابت حتى يضغط «إيقاف التوفير»
                  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const LiteHome()), (r) => false);
                }),
                const SizedBox(height: 10),
                AppButton('إعادة المحاولة', kind: 'g', onPressed: widget.onRetry),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------- لعبة القفز ----------
class _Obs {
  double x;
  bool counted = false;
  _Obs(this.x);
}

class DinoScreen extends StatefulWidget {
  const DinoScreen({super.key});

  @override
  State<DinoScreen> createState() => _DinoState();
}

class _DinoState extends State<DinoScreen> with SingleTickerProviderStateMixin {
  late final Ticker ticker;
  StreamSubscription<DatabaseEvent>? conn;
  final math.Random rnd = math.Random();
  Duration last = Duration.zero;
  int stage = 1;
  int passed = 0;
  int spawned = 0;
  double y = 0;
  double vy = 0;
  double dist = 0;
  double nextGap = 0;
  double w = 360;
  bool running = false;
  bool over = false;
  bool asking = false;
  final List<_Obs> obs = [];

  static const double groundH = 70;
  static const double playerX = 70;
  static const double pw = 26;
  static const double ph = 44;
  static const double ow = 24;
  static const double oh = 28;

  double get speed => 250 + (stage - 1) * 42; // تزداد السرعة كل مرحلة
  int get prize => stage * kDinoPrizeStep;

  @override
  void initState() {
    super.initState();
    ticker = createTicker(_tick);
    conn = watchConnectionRestore(context);
  }

  @override
  void dispose() {
    ticker.dispose();
    conn?.cancel();
    super.dispose();
  }

  void _startStage() {
    obs.clear();
    passed = 0;
    spawned = 0;
    y = 0;
    vy = 0;
    over = false;
    asking = false;
    nextGap = 380;
    last = Duration.zero;
    running = true;
    if (!ticker.isActive) ticker.start();
    setState(() {});
  }

  void _jump() {
    if (!running) return;
    if (y <= 0.5) {
      vy = 790;
      _s('reel_stop.wav');
    }
  }

  void _tick(Duration t) {
    if (!running) return;
    final dt = last == Duration.zero ? 0.016 : math.min(0.05, (t - last).inMicroseconds / 1e6);
    last = t;
    if (y > 0 || vy > 0) {
      vy -= 2000 * dt;
      y += vy * dt;
      if (y <= 0) {
        y = 0;
        vy = 0;
      }
    }
    dist += speed * dt;
    for (final o in obs) {
      o.x -= speed * dt;
    }
    // توليد الشوكات: عشرة في كل مرحلة
    if (spawned < kDinoPerStage) {
      final lastX = obs.isEmpty ? -9999.0 : obs.last.x;
      if (obs.isEmpty || w - lastX >= nextGap) {
        obs.add(_Obs(w + 20));
        spawned++;
        nextGap = (300 + rnd.nextDouble() * 200) * (speed / 280).clamp(1.0, 1.9);
      }
    }
    for (final o in obs) {
      if (!o.counted && o.x + ow < playerX) {
        o.counted = true;
        passed++;
      }
      final overlapX = playerX + pw - 4 > o.x + 3 && playerX + 4 < o.x + ow - 3;
      if (overlapX && y < oh - 6) {
        _die();
        return;
      }
    }
    obs.removeWhere((o) => o.x < -60);
    if (passed >= kDinoPerStage) {
      running = false;
      _s('win.wav');
      _stageDone();
    }
    if (mounted) setState(() {});
  }

  void _die() {
    running = false;
    over = true;
    _s('boom.wav');
    if (mounted) setState(() {});
  }

  Future<void> _stageDone() async {
    if (!mounted) return;
    if (stage >= kDinoStages) {
      _withdraw(all: true);
      return;
    }
    setState(() => asking = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        title: Text('🎉 أنهيت الجولة $stage'),
        content: Text('جائزتك الآن: $prize رصيد\nهل تريد المتابعة الى الجولة ${stage + 1}؟ او تريد سحب رصيدك وانهاء اللعبة؟'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(d);
              _withdraw();
            },
            child: const Text('سحب'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(d);
              stage++;
              _startStage();
            },
            child: const Text('اكمال'),
          ),
        ],
      ),
    );
  }

  Future<void> _withdraw({bool all = false}) async {
    final cur = prefs.getInt('dino_pending') ?? 0;
    prefs.setInt('dino_pending', math.min(100, math.max(cur, prize)));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(all ? '🏆 أنهيت كل المراحل!' : 'تم سحب رصيدك'),
        content: const Text('عندما تستعيد الاتصال بالانترنت سوف تحصل على جائزتك.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('حسناً'))],
      ),
    );
    if (!mounted) return;
    setState(() {
      stage = 1;
      running = false;
      over = false;
      asking = false;
      obs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    w = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(title: const Text('العب بدون انترنت 🎮')),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _jump(),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            color: const Color(0x22000000),
            child: Text('المرحلة $stage / $kDinoStages   •   الشوكات: $passed / $kDinoPerStage   •   الجائزة: $prize', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
          ),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _DinoPainter(y: y, obs: obs.map((o) => o.x).toList(), dist: dist, running: running))),
              if (!running && !over && !asking)
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('اضغط للقفز فوق الشوكات', style: TextStyle(fontSize: 16, color: kMu)),
                    const SizedBox(height: 12),
                    SizedBox(width: 200, child: AppButton(stage == 1 ? 'ابدأ اللعبة' : 'ابدأ', glow: true, onPressed: _startStage)),
                  ]),
                ),
              if (over)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: const Color(0xEE000000), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFFF6B6B))),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('💥 خسرت!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      const Text('يجب أن تعيد من البداية', style: TextStyle(color: kMu)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 180,
                        child: AppButton('إعادة', glow: true, onPressed: () {
                          stage = 1;
                          _startStage();
                        }),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DinoPainter extends CustomPainter {
  final double y;
  final List<double> obs;
  final double dist;
  final bool running;
  _DinoPainter({required this.y, required this.obs, required this.dist, required this.running});

  @override
  void paint(Canvas canvas, Size s) {
    final gy = s.height - _DinoState.groundH;
    // سماء
    canvas.drawRect(Offset.zero & s, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF14213D), Color(0xFF3A5A8C)]).createShader(Offset.zero & s));
    // أرض
    canvas.drawRect(Rect.fromLTWH(0, gy, s.width, _DinoState.groundH), Paint()..color = const Color(0xFF2E7D32));
    canvas.drawRect(Rect.fromLTWH(0, gy, s.width, 5), Paint()..color = const Color(0xFF66BB6A));
    final line = Paint()..color = const Color(0x55FFFFFF)..strokeWidth = 2;
    final off = dist % 40;
    for (var x = -off; x < s.width; x += 40) {
      canvas.drawLine(Offset(x, gy + 22), Offset(x + 16, gy + 22), line);
    }
    // الشوكات
    final thorn = Paint()..color = const Color(0xFFE0E0E0);
    final thorn2 = Paint()..color = const Color(0xFF9E9E9E);
    for (final x in obs) {
      final p1 = Path()
        ..moveTo(x, gy)
        ..lineTo(x + _DinoState.ow / 2, gy - _DinoState.oh)
        ..lineTo(x + _DinoState.ow, gy)
        ..close();
      canvas.drawPath(p1, thorn);
      canvas.drawPath(p1, Paint()..style = PaintingStyle.stroke..color = thorn2.color..strokeWidth = 1.5);
    }
    // اللاعب: فتى صغير
    final px = _DinoState.playerX;
    final base = gy - y;
    final leg = running && y <= 0.5 ? math.sin(dist / 14) * 6 : 0.0;
    final skin = Paint()..color = const Color(0xFFFFCC99);
    final legA = math.min(0.0, leg);
    final legB = math.max(0.0, leg);
    canvas.drawRect(Rect.fromLTWH(px + 6, base - 14, 5, 14 + legA), Paint()..color = const Color(0xFF333366));
    canvas.drawRect(Rect.fromLTWH(px + 15, base - 14, 5, 14 - legB), Paint()..color = const Color(0xFF333366));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px + 3, base - 32, 20, 20), const Radius.circular(4)), Paint()..color = const Color(0xFFE53935));
    canvas.drawCircle(Offset(px + 13, base - 38), 9, skin);
    canvas.drawRect(Rect.fromLTWH(px + 4, base - 47, 18, 6), Paint()..color = const Color(0xFF3E2723));
    canvas.drawCircle(Offset(px + 16, base - 39), 1.6, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant _DinoPainter old) => true;
}
