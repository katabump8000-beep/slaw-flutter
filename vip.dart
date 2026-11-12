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
  VipDef('galaxy', '𝑽𝑰𝑷 المجرة', 'نجوم وشهب متحركة بدون أي تغطية للألوان', 0, Color(0xFF3D7BFF), Color(0xFF9B5CFF)),
  VipDef('emerald', '𝑽𝑰𝑷 زمردة', 'واجهة وردية راقية: غصن متدلٍّ وأرضية وأوراق خريفية خفيفة وورد على الأزرار وصوت هادئ', 0, Color(0xFFFF6FAE), Color(0xFFFFC1DC)),
  VipDef('thunder', '𝑽𝑰𝑷 الصاعقة', 'واجهة وأزرار زرقاء بالكامل مع خلفية متحركة وبرق نادر وأسلاك كهرباء', 0, Color(0xFF2F8CFF), Color(0xFFBFE3FF)),
  VipDef('royal', '𝑽𝑰𝑷 الملكي', 'خمري ملكي دائماً مع خلفية دوامة ثلاثية الأبعاد تنقلك لعالم آخر', 0, Color(0xFFA31E3E), Color(0xFFFFC857)),
  VipDef('royal2', '𝑽𝑰𝑷 الملكي الذهبي', 'خمري ملكي بدوامة ذهبية متوهجة', 0, Color(0xFFA31E3E), Color(0xFFFFD27A)),
  VipDef('royal3', '𝑽𝑰𝑷 الملكي القرمزي', 'خمري داكن بدوامة قرمزية عميقة', 0, Color(0xFF7A1230), Color(0xFFFF6B8A)),
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
  var ok = false;
  final fresh = <String>{};
  for (var i = 0; i < 3 && !ok; i++) {
    try {
      final v = (await ref('vips/$myUid').get().timeout(const Duration(seconds: 12))).value;
      if (v is Map) fresh.addAll(v.keys.map((e) => e.toString()));
      ok = true;
    } catch (_) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
  final ckey = 'vown_$myUid';
  if (ok) {
    vipOwned
      ..clear()
      ..addAll(fresh);
    prefs.setString(ckey, fresh.join(','));
  } else {
    // تعذر الاتصال: لا نُفرغ ممتلكاته، نستخدم آخر نسخة محفوظة على الجهاز
    final c = (prefs.getString(ckey) ?? '').split(',').where((e) => e.isNotEmpty);
    vipOwned.addAll(c);
  }
  final k = prefs.getString('vipk') ?? '';
  _applyVip(vipOwned.contains(k) ? k : '');
}

/// يُستدعى بعد شراء ناجح لتثبيت الملكية على الجهاز أيضاً
void rememberVip(String id) {
  vipOwned.add(id);
  prefs.setString('vown_$myUid', vipOwned.join(','));
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
      final slot = d.inMilliseconds ~/ 13000;
      if (slot != _slot) {
        _slot = slot;
        if (vipKind.value == 'thunder') {
          Sfx.start('zap${1 + math.Random().nextInt(3)}.wav', volume: .28);
          Future<void>.delayed(const Duration(milliseconds: 380), () {
            if (mounted && vipKind.value == 'thunder') Sfx.start('thunder.wav', volume: .3);
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
                return CustomPaint(size: Size.infinite, painter: _GardenPainter(el));
              case 'thunder':
                return CustomPaint(size: Size.infinite, painter: _ThunderPainter(el));
              case 'royal':
                return CustomPaint(size: Size.infinite, painter: _VortexPainter(el, 0));
              case 'royal2':
                return CustomPaint(size: Size.infinite, painter: _VortexPainter(el, 1));
              case 'royal3':
                return CustomPaint(size: Size.infinite, painter: _VortexPainter(el, 2));
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


// ---------- زمردة: حديقة وردية خفيفة (أرضية + غصن متدلٍّ + أوراق قليلة) بلا أي تغطية للشاشة ----------
class _GardenPainter extends CustomPainter {
  final ValueNotifier<Duration> el;
  _GardenPainter(this.el) : super(repaint: el);
  static const List<Color> _cols = [Color(0xFFFF8FB8), Color(0xFFFFB380), Color(0xFFFFC4D8), Color(0xFFFF9A6B), Color(0xFFF7A8C8)];
  static final List<List<double>> _p = () {
    final r = math.Random(11);
    return List.generate(7, (i) => [r.nextDouble(), r.nextDouble(), .03 + r.nextDouble() * .035, 6 + r.nextDouble() * 4, r.nextDouble() * 6.28]);
  }();

  void _leaf(Canvas cv, Offset o, double r, double ang, Color c, int a) {
    cv.save();
    cv.translate(o.dx, o.dy);
    cv.rotate(ang);
    final path = Path()
      ..moveTo(0, -r)
      ..quadraticBezierTo(r * .8, -r * .2, 0, r)
      ..quadraticBezierTo(-r * .8, -r * .2, 0, -r);
    cv.drawPath(path, Paint()..color = c.withAlpha(a));
    cv.drawLine(Offset(0, -r), Offset(0, r), Paint()..color = Colors.white.withAlpha(60)..strokeWidth = .7);
    cv.restore();
  }

  void _blossom(Canvas cv, Offset o, double r, Color c) {
    for (var k = 0; k < 5; k++) {
      cv.drawCircle(o + Offset(math.cos(k * 1.2566) * r * .7, math.sin(k * 1.2566) * r * .7), r * .55, Paint()..color = c.withAlpha(210));
    }
    cv.drawCircle(o, r * .35, Paint()..color = const Color(0xFFFFE08A));
  }

  @override
  void paint(Canvas cv, Size s) {
    final t = el.value.inMilliseconds / 1000.0;
    // الأرضية: شريط عشب ناعم مع أزهار صغيرة
    const fh = 24.0;
    final fr = Rect.fromLTWH(0, s.height - fh, s.width, fh);
    cv.drawRect(fr, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00FF9EC4), Color(0x55FF9EC4)]).createShader(fr));
    for (var i = 0; i < 26; i++) {
      final x = (i + .5) / 26 * s.width;
      final sway = math.sin(t * 1.1 + i) * 2.2;
      final hh = 9.0 + (i % 3) * 3;
      cv.drawLine(Offset(x, s.height), Offset(x + sway, s.height - hh), Paint()..color = const Color(0xFF9BD6A0).withAlpha(110)..strokeWidth = 1.4..strokeCap = StrokeCap.round);
      if (i % 4 == 1) _blossom(cv, Offset(x + sway, s.height - hh - 2), 3.6, _cols[i % _cols.length]);
    }
    // غصن متدلٍّ من الزاوية العليا اليمنى
    final sw = math.sin(t * .6) * 5;
    final br = Path()
      ..moveTo(s.width + 6, -4)
      ..cubicTo(s.width * .86, s.height * .02 + sw * .3, s.width * .68, s.height * .05 + sw * .6, s.width * .46 + sw, s.height * .1 + sw * .4);
    cv.drawPath(br, Paint()..color = const Color(0xFF8A5A44).withAlpha(210)..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round);
    final m = br.computeMetrics().first;
    for (var k = 1; k <= 9; k++) {
      final tg = m.getTangentForOffset(m.length * k / 9);
      if (tg == null) continue;
      final o = tg.position;
      final flap = math.sin(t * 1.3 + k) * .35;
      _leaf(cv, o + const Offset(0, 8), 7, 1.0 + flap, _cols[k % _cols.length], 190);
      _leaf(cv, o + const Offset(0, -6), 6, -1.0 + flap, _cols[(k + 2) % _cols.length], 170);
      if (k % 3 == 0) _blossom(cv, o + Offset(math.sin(t + k) * 1.5, 14), 5, const Color(0xFFFF7FB0));
    }
    // أوراق خريفية قليلة جداً (زهري/برتقالي)
    for (var i = 0; i < _p.length; i++) {
      final q = _p[i];
      final y = ((q[1] + t * q[2]) % 1.1 - .05) * s.height;
      final x = (q[0] + math.sin(t * .5 + q[4]) * .05) * s.width;
      _leaf(cv, Offset(x, y), q[3], t * .7 + q[4], _cols[i % _cols.length], 150);
    }
  }

  @override
  bool shouldRepaint(covariant _GardenPainter o) => false;
}

// ---------- الصاعقة: خلفية زرقاء متحركة خفيفة + برق نادر + أسلاك كهرباء (بدون تغطية الشاشة) ----------
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
    // خطوط طاقة مائلة بطيئة
    for (var i = 0; i < 9; i++) {
      final x = ((i * .137) + t * .018 * (1 + i % 4)) % 1.2 * s.width;
      final y = ((i * .211) + t * .045) % 1.2 * s.height - 40;
      cv.drawLine(Offset(x, y), Offset(x - 36, y + 64), Paint()..color = const Color(0xFF58A6FF).withAlpha(34)..strokeWidth = 1.2..strokeCap = StrokeCap.round);
    }
    // شرارات تطفو للأعلى
    for (var i = 0; i < 16; i++) {
      final x = ((i * .0713) + math.sin(t * .4 + i) * .02) % 1 * s.width;
      final y = s.height - (((i * .173) + t * .03) % 1) * s.height;
      final a = (math.sin(t * 1.6 + i * 2) + 1) / 2;
      cv.drawCircle(Offset(x, y), 1.3 + a, Paint()..color = const Color(0xFF9CCBFF).withAlpha((a * 130).toInt()));
    }
    // برق نادر (كل 13 ثانية تقريباً) رفيع بلا وميض للشاشة
    final slot = (t / 13.0).floor();
    final ph = t - slot * 13.0;
    if (ph < .45) {
      final r = math.Random(slot * 31 + 5);
      final a = 1 - ph / .45;
      final x = s.width * (.15 + r.nextDouble() * .7);
      final path = _bolt(Offset(x, 0), Offset(x + (r.nextDouble() - .5) * 110, s.height * (.3 + r.nextDouble() * .25)), r, 60);
      cv.drawPath(path, Paint()..color = const Color(0xFF58A6FF).withAlpha((a * 110).toInt())..style = PaintingStyle.stroke..strokeWidth = 6..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      cv.drawPath(path, Paint()..color = Colors.white.withAlpha((a * 235).toInt())..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    // أسلاك كهرباء في الزاوية العليا اليمنى
    for (var k = 0; k < 3; k++) {
      final rr = math.Random(((t * 7).floor()) * 7 + k);
      final path = _bolt(Offset(s.width, s.height * .1), Offset(s.width - 70 - k * 14, s.height * .1 + 40 + k * 26), rr, 14);
      cv.drawPath(path, Paint()..color = const Color(0xFF7CC4FF).withAlpha(190)..style = PaintingStyle.stroke..strokeWidth = 1.3);
    }
  }

  @override
  bool shouldRepaint(covariant _ThunderPainter o) => false;
}

// ---------- الملكي: دوامة ثلاثية الأبعاد (نفق يدور) كخلفية رفيعة بلا تغطية ----------
class _VortexPainter extends CustomPainter {
  final ValueNotifier<Duration> el;
  final int v;
  _VortexPainter(this.el, this.v) : super(repaint: el);

  @override
  void paint(Canvas cv, Size s) {
    final t = el.value.inMilliseconds / 1000.0;
    final c = Offset(s.width / 2, s.height * .46);
    final maxR = math.sqrt(s.width * s.width + s.height * s.height) / 2;
    final cols = v == 1 ? const [Color(0xFFFFC857), Color(0xFFFF9F43)] : v == 2 ? const [Color(0xFFD81B60), Color(0xFF7A1230)] : const [Color(0xFFB3203F), Color(0xFFFFC857)];
    const arms = 5;
    for (var a = 0; a < arms; a++) {
      final path = Path();
      for (var k = 0; k <= 40; k++) {
        final z = k / 40;
        final r = math.pow(z, 1.8).toDouble() * maxR;
        final ang = a * 2 * math.pi / arms + z * 3.4 - t * (v == 2 ? .32 : .45);
        final pt = c + Offset(math.cos(ang) * r, math.sin(ang) * r * .92);
        if (k == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      cv.drawPath(path, Paint()..color = cols[a % 2].withAlpha(48)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
    for (var i = 0; i < 12; i++) {
      final z = ((i / 12) + t * .06) % 1;
      final r = math.pow(z, 2.1).toDouble() * maxR;
      final al = (math.sin(z * math.pi) * 52).toInt();
      cv.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 1.84), Paint()..color = cols[0].withAlpha(al)..style = PaintingStyle.stroke..strokeWidth = 1 + z * 2);
    }
    for (var i = 0; i < 14; i++) {
      final z = ((i / 14) + t * .09) % 1;
      final r = math.pow(z, 1.8).toDouble() * maxR;
      final ang = (i % arms) * 2 * math.pi / arms + z * 3.4 - t * (v == 2 ? .32 : .45);
      final pt = c + Offset(math.cos(ang) * r, math.sin(ang) * r * .92);
      cv.drawCircle(pt, 1 + z * 2.2, Paint()..color = cols[1].withAlpha((math.sin(z * math.pi) * 200).toInt()));
    }
  }

  @override
  bool shouldRepaint(covariant _VortexPainter o) => false;
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
          ? Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('لا تملك أي تأثير بعد. يمكنك شراء VIP من المتجر.\nإذا اشتريت ولم يظهر اضغط تحديث.', textAlign: TextAlign.center, style: TextStyle(color: kMu, height: 1.8)), const SizedBox(height: 10), AppButton('تحديث', compact: true, onPressed: () async { await initVip(); if (mounted) setState(() {}); })])))
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
