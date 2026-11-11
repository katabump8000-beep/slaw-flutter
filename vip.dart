import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_state.dart';
import 'sfx.dart';
import 'data.dart';
import 'widgets.dart';

/// أنواع VIP (تُشترى من المتجر وتُفعَّل من «ممتلكاتي»). لا يوجد VIP مجاني.
class VipDef {
  final String id, name, desc;
  final int price;
  final Color c1, c2;
  const VipDef(this.id, this.name, this.desc, this.price, this.c1, this.c2);
}

const List<VipDef> kVips = [
  VipDef('galaxy', '𝑽𝑰𝑷 المجرة', 'شهب ونجوم وتوهج أزرق يتدرج إلى البنفسجي', 0, Color(0xFF3D7BFF), Color(0xFF9B5CFF)),
  VipDef('emerald', '𝑽𝑰𝑷 زمردة', 'أوراق ورود راقية تتساقط بألوان واجهتك', 0, Color(0xFFFF6FA8), Color(0xFFFFB3D1)),
  VipDef('thunder', '𝑽𝑰𝑷 الصاعقة', 'برق ورعد وأسلاك كهرباء وألوان زرقاء ثابتة', 0, Color(0xFF2F8CFF), Color(0xFFBFE3FF)),
  VipDef('royal', '𝑽𝑰𝑷 الملكي', 'خمري ملكي بحواف ذهبية وأوراق خريف خمرية متساقطة', 0, Color(0xFF8E1B3A), Color(0xFFFFC857)),
];

VipDef? vipDef(String id) {
  for (final v in kVips) {
    if (v.id == id) return v;
  }
  return null;
}

final ValueNotifier<bool> vipOn = ValueNotifier<bool>(false);
final ValueNotifier<String> vipKind = ValueNotifier<String>('');
final ValueNotifier<double> vipPhase = ValueNotifier<double>(0);
final Set<String> vipOwned = <String>{};
Timer? _trialT;
String _beforeTrial = '';

void _applyVip(String k) {
  vipKind.value = k;
  vipOn.value = k.isNotEmpty;
}

/// تحميل ما يملكه المستخدم وتفعيل المحفوظ (إن كان ما زال يملكه)
Future<void> initVip() async {
  try {
    vipOwned.clear();
    final v = (await ref('vips/$myUid').get()).value;
    if (v is Map) vipOwned.addAll(v.keys.map((e) => e.toString()));
  } catch (_) {}
  final k = prefs.getString('vipk') ?? '';
  _applyVip(vipOwned.contains(k) ? k : '');
}

void setVipKind(String k) {
  _trialT?.cancel();
  prefs.setString('vipk', k);
  _applyVip(k);
}

/// تجربة مرة واحدة لكل VIP لمدة 3 دقائق ثم ترجع الحالة السابقة
bool startVipTrial(String id) {
  if (prefs.getBool('vtr_$id') ?? false) return false;
  prefs.setBool('vtr_$id', true);
  _trialT?.cancel();
  _beforeTrial = vipOwned.contains(prefs.getString('vipk') ?? '') ? (prefs.getString('vipk') ?? '') : '';
  _applyVip(id);
  _trialT = Timer(const Duration(minutes: 3), () {
    _applyVip(_beforeTrial);
    toast('انتهت التجربة وعاد كل شيء كما كان');
  });
  return true;
}

/// طبقة الشهب + ساعة الموجة (تعمل فقط عند تفعيل VIP)
class VipLayers extends StatefulWidget {
  const VipLayers({super.key});

  @override
  State<VipLayers> createState() => _VipLayersState();
}

class _VipLayersState extends State<VipLayers> with SingleTickerProviderStateMixin {
  late final Ticker tk;
  int _slot = -1;
  final ValueNotifier<Duration> el = ValueNotifier<Duration>(Duration.zero);

  @override
  void initState() {
    super.initState();
    tk = createTicker((d) {
      el.value = d;
      vipPhase.value = (d.inMilliseconds % 4000) / 4000;
      // الصاعقة: مع كل برق صوت صعقة حاد ثم رعد بعده بلحظة (يتزامن مع رسم البرق)
      final slot = d.inMilliseconds ~/ 5000;
      if (slot != _slot) {
        _slot = slot;
        if (vipKind.value == 'thunder') {
          Sfx.start('zap${1 + math.Random().nextInt(3)}.wav', volume: .55);
          Future<void>.delayed(const Duration(milliseconds: 380), () {
            if (mounted && vipKind.value == 'thunder') Sfx.start('thunder.wav', volume: .6);
          });
        }
      }
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
        child: ValueListenableBuilder<String>(
          valueListenable: vipKind,
          builder: (c, k, _) {
            final d = vipDef(k);
            switch (k) {
              case 'emerald':
                return CustomPaint(size: Size.infinite, painter: _FallPainter(el, context.accent2, petals: true));
              case 'thunder':
                return CustomPaint(size: Size.infinite, painter: _ThunderPainter(el));
              case 'royal':
                return CustomPaint(size: Size.infinite, painter: _RoyalPainter(el));
              default:
                return CustomPaint(size: Size.infinite, painter: _StarsPainter(el, d?.c1 ?? context.accent2));
            }
          },
        ),
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


// ---------- ورود/أوراق متساقطة (زمردة + الملكي) ----------
class _FallPainter extends CustomPainter {
  final ValueNotifier<Duration> el;
  final Color col;
  final bool petals;
  _FallPainter(this.el, this.col, {this.petals = true}) : super(repaint: el);
  static final List<List<double>> _p = () {
    final r = math.Random(77);
    return List.generate(28, (i) => [r.nextDouble(), r.nextDouble(), .05 + r.nextDouble() * .09, 6 + r.nextDouble() * 9, r.nextDouble() * 6.28, 7 + r.nextDouble() * 9]);
  }();

  @override
  void paint(Canvas cv, Size s) {
    final t = el.value.inMilliseconds / 1000.0;
    final hsl = HSLColor.fromColor(col);
    for (var i = 0; i < _p.length; i++) {
      final q = _p[i];
      final y = ((q[1] + t * q[2]) % 1.12 - .06) * s.height;
      final x = (q[0] + math.sin(t * .6 + q[4]) * .05) * s.width;
      final c = hsl.withHue((hsl.hue + i * 9) % 360).withLightness((hsl.lightness + .12).clamp(.4, .8)).toColor();
      cv.save();
      cv.translate(x, y);
      cv.rotate(t * .8 + q[4]);
      final r = q[5];
      final path = Path()
        ..moveTo(0, -r)
        ..quadraticBezierTo(r * .9, -r * .2, 0, r)
        ..quadraticBezierTo(-r * .9, -r * .2, 0, -r);
      cv.drawPath(path, Paint()..color = c.withAlpha(150));
      cv.drawPath(path, Paint()..color = Colors.white.withAlpha(40)..style = PaintingStyle.stroke..strokeWidth = .8);
      cv.restore();
    }
    // ورود في أسفل الشاشة
    for (var i = 0; i < 7; i++) {
      final cx = s.width * (i + .5) / 7;
      final cy = s.height - 8 + math.sin(t + i) * 2;
      final c = hsl.withHue((hsl.hue + i * 14) % 360).toColor();
      for (var k = 0; k < 5; k++) {
        cv.drawCircle(Offset(cx + math.cos(k * 1.256) * 7, cy + math.sin(k * 1.256) * 7), 6, Paint()..color = c.withAlpha(130));
      }
      cv.drawCircle(Offset(cx, cy), 4, Paint()..color = const Color(0xFFFFE08A).withAlpha(170));
    }
  }

  @override
  bool shouldRepaint(covariant _FallPainter o) => false;
}

// ---------- الصاعقة: برق وأسلاك كهرباء ----------
class _ThunderPainter extends CustomPainter {
  final ValueNotifier<Duration> el;
  _ThunderPainter(this.el) : super(repaint: el);

  Path _bolt(Offset a, Offset b, math.Random r, double jag) {
    final p = Path()..moveTo(a.dx, a.dy);
    const n = 9;
    for (var i = 1; i < n; i++) {
      final k = i / n;
      p.lineTo(a.dx + (b.dx - a.dx) * k + (r.nextDouble() - .5) * jag, a.dy + (b.dy - a.dy) * k);
    }
    p.lineTo(b.dx, b.dy);
    return p;
  }

  @override
  void paint(Canvas cv, Size s) {
    final t = el.value.inMilliseconds / 1000.0;
    final slot = (t / 5.0).floor();
    final ph = t - slot * 5.0;
    final r = math.Random(slot * 31 + 5);
    if (ph < .35) {
      final a = (1 - ph / .35);
      cv.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF9CCBFF).withAlpha((a * 55).toInt()));
      final x = s.width * (.15 + r.nextDouble() * .7);
      final path = _bolt(Offset(x, 0), Offset(x + (r.nextDouble() - .5) * 120, s.height * (.35 + r.nextDouble() * .3)), r, 70);
      cv.drawPath(path, Paint()..color = const Color(0xFF58A6FF).withAlpha((a * 160).toInt())..style = PaintingStyle.stroke..strokeWidth = 9..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      cv.drawPath(path, Paint()..color = Colors.white.withAlpha((a * 255).toInt())..style = PaintingStyle.stroke..strokeWidth = 2.4);
    }
    // أسلاك كهرباء في الزاوية
    for (var k = 0; k < 3; k++) {
      final rr = math.Random(((t * 9).floor()) * 7 + k);
      final path = _bolt(Offset(s.width, s.height * .12), Offset(s.width - 70 - k * 14, s.height * .12 + 40 + k * 26), rr, 16);
      cv.drawPath(path, Paint()..color = const Color(0xFF7CC4FF).withAlpha(200)..style = PaintingStyle.stroke..strokeWidth = 1.4);
    }
    cv.drawRect(Offset.zero & s, Paint()..shader = RadialGradient(colors: [Colors.transparent, const Color(0xFF0A3A8C).withAlpha(60)], radius: 1.0).createShader(Offset.zero & s));
  }

  @override
  bool shouldRepaint(covariant _ThunderPainter o) => false;
}

// ---------- الملكي: خمري + حواف ذهبية + أوراق خريف ----------
class _RoyalPainter extends CustomPainter {
  final ValueNotifier<Duration> el;
  _RoyalPainter(this.el) : super(repaint: el);

  @override
  void paint(Canvas cv, Size s) {
    final t = el.value.inMilliseconds / 1000.0;
    cv.drawRect(Offset.zero & s, Paint()..shader = RadialGradient(colors: [Colors.transparent, const Color(0xFF5A0A1F).withAlpha(95)], radius: 1.05).createShader(Offset.zero & s));
    final k = (math.sin(t * 1.4) + 1) / 2;
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Color.lerp(const Color(0xFFB8860B), const Color(0xFFFFE08A), k)!.withAlpha(210);
    cv.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(2, 2, s.width - 4, s.height - 4), const Radius.circular(14)), gold);
    cv.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(7, 7, s.width - 14, s.height - 14), const Radius.circular(10)), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0xFFFFE08A).withAlpha(90));
    final cols = [const Color(0xFF7A1230), const Color(0xFF9C1F3F), const Color(0xFF5E0E26), const Color(0xFFB0453C)];
    for (var i = 0; i < _FallPainter._p.length; i++) {
      final q = _FallPainter._p[i];
      final y = ((q[1] + t * q[2] * .9) % 1.12 - .06) * s.height;
      final x = (q[0] + math.sin(t * .5 + q[4]) * .06) * s.width;
      cv.save();
      cv.translate(x, y);
      cv.rotate(t * .9 + q[4]);
      final r = q[5];
      final leaf = Path()
        ..moveTo(0, -r)
        ..quadraticBezierTo(r, -r * .3, 0, r)
        ..quadraticBezierTo(-r, -r * .3, 0, -r);
      cv.drawPath(leaf, Paint()..color = cols[i % cols.length].withAlpha(190));
      cv.drawLine(Offset(0, -r), Offset(0, r), Paint()..color = const Color(0xFFFFC857).withAlpha(110)..strokeWidth = .8);
      cv.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RoyalPainter o) => false;
}

/// «ممتلكاتي»: كل VIP اشتراه العضو مع تفعيل وإيقاف
class MyVipsScreen extends StatefulWidget {
  const MyVipsScreen({super.key});
  @override
  State<MyVipsScreen> createState() => _MyVipsState();
}

class _MyVipsState extends State<MyVipsScreen> {
  @override
  void initState() {
    super.initState();
    initVip().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final mine = kVips.where((v) => vipOwned.contains(v.id)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('ممتلكاتي')),
      body: mine.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('لا تملك أي تأثير بعد. يمكنك شراء VIP من المتجر.', textAlign: TextAlign.center, style: TextStyle(color: kMu, height: 1.8))))
          : ListView(children: [
              for (final v in mine)
                ValueListenableBuilder<String>(
                  valueListenable: vipKind,
                  builder: (c, k, _) {
                    final on = k == v.id;
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: v.c1.withAlpha(60), child: Text('👑', style: TextStyle(fontSize: 18, shadows: [Shadow(color: v.c1, blurRadius: 10)]))),
                      title: Align(alignment: AlignmentDirectional.centerStart, child: VipName(v.id)),
                      subtitle: Text(v.desc, style: const TextStyle(color: kMu, fontSize: 12)),
                      trailing: SizedBox(width: 92, child: AppButton(on ? 'إيقاف' : 'تفعيل', compact: true, kind: on ? 'r' : 'main', onPressed: () {
                        setVipKind(on ? '' : v.id);
                        toast(on ? 'تم إيقاف التأثير' : 'تم تفعيل ${v.name}');
                      })),
                    );
                  },
                ),
            ]),
    );
  }
}


/// اسم VIP بتدرج لوني (المجرة: أزرق→بنفسجي، زمردة: زهري، الصاعقة: أزرق ساطع، الملكي: خمري→ذهبي)
class VipName extends StatelessWidget {
  final String id;
  final double size;
  const VipName(this.id, {super.key, this.size = 16});
  @override
  Widget build(BuildContext context) {
    final d = vipDef(id);
    if (d == null) return const SizedBox.shrink();
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(colors: [d.c1, d.c2]).createShader(r),
      child: Text(d.name, style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, shadows: [Shadow(color: d.c1.withAlpha(150), blurRadius: 8)])),
    );
  }
}
