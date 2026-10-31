import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_state.dart';
import 'widgets.dart';

/// وضع VIP: اختياري. يغيّر شكل الرسائل والبطاقات والأزرار ويضيف شهباً وأصوات نقر مختلفة
final ValueNotifier<bool> vipOn = ValueNotifier<bool>(prefs.getBool('vip') ?? false);
final ValueNotifier<double> vipPhase = ValueNotifier<double>(0);

void setVip(bool v) {
  prefs.setBool('vip', v);
  vipOn.value = v;
}

/// زر VIP الذي يظهر عند كل المستخدمين
class VipChip extends StatelessWidget {
  const VipChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: vipOn,
      builder: (c, on, _) => GestureDetector(
        onTap: () => showAppSheet<void>(context, (sc) => [
              const Text('✨ VIP 👑 ✨', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFFFD54A), shadows: [Shadow(color: Color(0xAAFFB000), blurRadius: 14)])),
              const Text('اجعل تطبيقك يلمع كسماء الليل', textAlign: TextAlign.center, style: TextStyle(color: kMu, fontSize: 12.5)),
              const SizedBox(height: 4),
              for (final f in const [
                ['🌠', 'شهب متعددة تعبر الشاشة'],
                ['⭐', 'نجوم خفيفة تلمع وتخبو'],
                ['🌌', 'توهج شفقي ناعم على الأطراف'],
                ['💬', 'رسائل بإطار متوهج وموجة دوّارة'],
                ['🔔', 'أصوات نقر مميزة'],
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [Text(f[0], style: const TextStyle(fontSize: 18)), const SizedBox(width: 10), Expanded(child: Text(f[1], style: const TextStyle(fontSize: 13.5, height: 1.5)))]),
                ),
              const SizedBox(height: 4),
              Text(
                on ? 'وضع VIP مفعّل الآن. هل تريد إيقافه؟' : 'تنبيه: قد يسبب ثقلاً أو بطءاً إذا كان هاتفك ضعيفاً، ويمكنك إيقافه في أي وقت.',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.8, fontSize: 12.5, color: kMu),
              ),
              AppButton(on ? 'إيقاف VIP' : 'تفعيل VIP 👑', onPressed: () {
                setVip(!on);
                Navigator.of(sc).pop();
                toast(on ? 'تم إيقاف VIP' : 'تم تفعيل VIP 👑');
              }),
              AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(sc).pop()),
            ]),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(colors: [Color(0xFFFFD54A), Color(0xFFFF9A1F)]),
            boxShadow: on ? const [BoxShadow(color: Color(0x99FFB000), blurRadius: 10)] : null,
          ),
          child: Text(on ? 'VIP ✓' : 'VIP', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
      ),
    );
  }
}

/// طبقة الشهب + ساعة الموجة (تعمل فقط عند تفعيل VIP)
class VipLayers extends StatefulWidget {
  const VipLayers({super.key});

  @override
  State<VipLayers> createState() => _VipLayersState();
}

class _VipLayersState extends State<VipLayers> with SingleTickerProviderStateMixin {
  late final Ticker tk;
  final ValueNotifier<Duration> el = ValueNotifier<Duration>(Duration.zero);

  @override
  void initState() {
    super.initState();
    tk = createTicker((d) {
      el.value = d;
      vipPhase.value = (d.inMilliseconds % 4000) / 4000;
    })..start();
  }

  @override
  void dispose() {
    tk.dispose();
    el.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(size: Size.infinite, painter: _StarsPainter(el, context.accent2)),
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  final ValueNotifier<Duration> el;
  final Color col;
  _StarsPainter(this.el, this.col) : super(repaint: el);

  static const int _nStars = 52;
  static const int _nMeteors = 5;
  static final List<List<double>> _stars = _mkStars();

  // x, y (نسبة), طور، سرعة، حجم، نوع اللون
  static List<List<double>> _mkStars() {
    final r = math.Random(2026);
    return List.generate(_nStars, (i) => [r.nextDouble(), r.nextDouble(), r.nextDouble(), .25 + r.nextDouble() * .6, .8 + r.nextDouble() * 1.7, r.nextInt(3).toDouble()]);
  }

  @override
  void paint(Canvas cv, Size s) {
    final sec = el.value.inMilliseconds / 1000.0;
    _glow(cv, s, sec);
    _twinkle(cv, s, sec);
    for (var i = 0; i < _nMeteors; i++) {
      _meteor(cv, s, sec, i);
    }
  }

  // توهج ناعم على الأطراف (شفق) يتحرك ببطء
  void _glow(Canvas cv, Size s, double sec) {
    final k1 = (math.sin(sec * .55) + 1) / 2;
    final k2 = (math.sin(sec * .43 + 2) + 1) / 2;
    final top = Offset(s.width * (.2 + .6 * k1), -s.height * .02);
    final bot = Offset(s.width * (.8 - .6 * k2), s.height * 1.02);
    cv.drawRect(
      Offset.zero & s,
      Paint()..shader = RadialGradient(colors: [col.withAlpha(46), col.withAlpha(0)]).createShader(Rect.fromCircle(center: top, radius: s.width * .85)),
    );
    cv.drawRect(
      Offset.zero & s,
      Paint()..shader = RadialGradient(colors: [const Color(0xFFB57BFF).withAlpha(38), const Color(0xFFB57BFF).withAlpha(0)]).createShader(Rect.fromCircle(center: bot, radius: s.width * .9)),
    );
  }

  // نجوم صغيرة تلمع وتخبو، والأكبر منها بشكل شرارة رباعية
  void _twinkle(Canvas cv, Size s, double sec) {
    final p = Paint();
    for (var i = 0; i < _nStars; i++) {
      final st = _stars[i];
      final ph = (sec * st[3] * .35 + st[2]) % 1.0;
      final a = math.pow((math.sin(ph * 2 * math.pi) + 1) / 2, 2.2).toDouble();
      if (a < .04) continue;
      final c = st[5] == 0 ? Colors.white : (st[5] == 1 ? col : const Color(0xFFFFE9A8));
      final x = st[0] * s.width;
      final y = st[1] * s.height;
      final r = st[4];
      p.color = c.withAlpha((a * 215).round());
      cv.drawCircle(Offset(x, y), r * (.7 + .5 * a), p);
      if (r > 1.9) {
        final L = r * 3.6 * a;
        final q = Paint()
          ..strokeWidth = .9
          ..strokeCap = StrokeCap.round
          ..color = c.withAlpha((a * 170).round());
        cv.drawLine(Offset(x - L, y), Offset(x + L, y), q);
        cv.drawLine(Offset(x, y - L), Offset(x, y + L), q);
      }
    }
  }

  // عدة شهب تعبر الشاشة بتوقيتات مختلفة
  void _meteor(Canvas cv, Size s, double sec, int i) {
    final period = 2.3 + i * .55;
    final off = i * 1.17;
    final cycle = ((sec + off) / period).floor();
    final t = ((sec + off) % period) / period;
    const life = .42;
    if (t > life) return;
    final k = t / life;
    final r = math.Random(cycle * 7919 + i * 131 + 13);
    final fromRight = r.nextBool();
    final x0 = s.width * (fromRight ? .35 + r.nextDouble() * .65 : r.nextDouble() * .65);
    final y0 = s.height * (-.02 + r.nextDouble() * .5);
    final ang = math.pi * (fromRight ? .74 + r.nextDouble() * .06 : .20 + r.nextDouble() * .06);
    final dir = Offset(math.cos(ang), math.sin(ang));
    final len = s.height * (.32 + r.nextDouble() * .25);
    final head = Offset(x0, y0) + dir * (len * k);
    final tail = head - dir * (90 + r.nextDouble() * 70);
    final a = math.sin(k * math.pi).clamp(0.0, 1.0);
    final warm = i.isEven ? Colors.white : const Color(0xFFFFE9A8);
    cv.drawLine(
      tail,
      head,
      Paint()
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [col.withAlpha(0), warm.withAlpha((235 * a).round())]).createShader(Rect.fromPoints(tail, head)),
    );
    cv.drawCircle(head, 5.5, Paint()..color = col.withAlpha((70 * a).round()));
    cv.drawCircle(head, 2.4, Paint()..color = Colors.white.withAlpha((245 * a).round()));
  }

  @override
  bool shouldRepaint(covariant _StarsPainter old) => old.col != col;
}

/// فقاعة رسالة: عادية، أو داكنة بحافة فاقعة وموجة تدور كل 4 ثوانٍ في وضع VIP
class VipBubble extends StatelessWidget {
  final Color color;
  final Color dark;
  final BoxConstraints constraints;
  final EdgeInsets padding;
  final Widget child;
  const VipBubble({super.key, required this.color, required this.dark, required this.constraints, required this.padding, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: vipOn,
      builder: (c, on, _) {
        final r = BorderRadius.circular(16);
        if (!on) {
          return Container(
            constraints: constraints,
            padding: padding,
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, dark]), borderRadius: r),
            child: child,
          );
        }
        return CustomPaint(
          foregroundPainter: _WavePainter(color, r),
          child: Container(
            constraints: constraints,
            padding: padding,
            decoration: BoxDecoration(
              color: Color.lerp(dark, Colors.black, .78),
              borderRadius: r,
              border: Border.all(color: color, width: 1.6),
              boxShadow: [BoxShadow(color: color.withAlpha(90), blurRadius: 8)],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color col;
  final BorderRadius r;
  _WavePainter(this.col, this.r) : super(repaint: vipPhase);

  @override
  void paint(Canvas cv, Size s) {
    final rect = Offset.zero & s;
    final shader = SweepGradient(
      colors: [col.withAlpha(0), col, Colors.white, col, col.withAlpha(0)],
      stops: const [0.0, .12, .2, .28, .45],
      transform: GradientRotation(vipPhase.value * 2 * math.pi),
    ).createShader(rect);
    cv.drawRRect(
      r.toRRect(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.col != col;
}
