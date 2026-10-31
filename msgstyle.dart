import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

/// تأثيرات رسائل خاصة بالمطورين والإمبراطور
/// الكود المحفوظ في الرسالة (الحقل ms): c{لون}e{تأثير}s{شهب}  مثل c2e3s1   أو  roy  (الملكي للإمبراطور فقط)

class _Pal {
  final String n;
  final Color a; // لون التمييز
  final Color d; // خلفية داكنة
  const _Pal(this.n, this.a, this.d);
}

const List<_Pal> kMsPalettes = [
  _Pal('ذهبي', Color(0xFFFFC94A), Color(0xFF221A06)),
  _Pal('بنفسجي', Color(0xFFB57BFF), Color(0xFF1B1030)),
  _Pal('أزرق جليدي', Color(0xFF6CC8FF), Color(0xFF08202E)),
  _Pal('زمردي', Color(0xFF3DE0A0), Color(0xFF07251C)),
  _Pal('وردي', Color(0xFFFF6FB5), Color(0xFF2B0C1D)),
];
const List<String> kMsEffects = ['موجة', 'لمعة', 'توهّج', 'حافة دوّارة', 'نبض'];
const List<String> kMsSparks = ['نجوم', 'نقاط', 'ماس', 'قلوب', 'شُهب'];

class MsgStyle {
  final int c, e, s;
  final bool royal;
  const MsgStyle(this.c, this.e, this.s, {this.royal = false});

  static MsgStyle? parse(Object? v) {
    final t = (v ?? '').toString();
    if (t == 'roy') return const MsgStyle(0, 0, 0, royal: true);
    final m = RegExp(r'^c([0-5])e([0-5])s([0-5])$').firstMatch(t);
    if (m == null) return null;
    final x = MsgStyle(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    return (x.c == 0 && x.e == 0 && x.s == 0) ? null : x;
  }

  String get code => royal ? 'roy' : 'c${c}e${e}s$s';
}

/// الكود الذي يُرفق برسائلي (للمطورين/الإمبراطور فقط)
String? myMsgStyleCode() {
  if (!Session.isDev) return null;
  final s = prefs.getString('mst') ?? '';
  final st = MsgStyle.parse(s);
  if (st == null) return null;
  if (st.royal && !Session.isEmp) return null;
  return s;
}

/// فقاعة بتأثير خاص (تُستعمل بدل VipBubble)
class StyledBubble extends StatefulWidget {
  final MsgStyle st;
  final BoxConstraints constraints;
  final EdgeInsets padding;
  final Widget child;
  const StyledBubble({super.key, required this.st, required this.constraints, required this.padding, required this.child});

  @override
  State<StyledBubble> createState() => _StyledBubbleState();
}

class _StyledBubbleState extends State<StyledBubble> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.st.royal ? 15000 : 3600))..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.st;
    final pal = kMsPalettes[(st.c == 0 ? 1 : st.c) - 1];
    final body = Container(constraints: widget.constraints, padding: widget.padding, child: widget.child);
    final painted = RepaintBoundary(
      child: AnimatedBuilder(
        animation: c,
        builder: (_, child) => CustomPaint(
          painter: _BackPainter(st, pal, c.value),
          foregroundPainter: _FrontPainter(st, pal, c.value),
          child: child,
        ),
        child: body,
      ),
    );
    if (!st.royal) return painted;
    // الملكي: كأس خمري ناعم على زاوية الرسالة
    return Stack(clipBehavior: Clip.none, children: [
      painted,
      const PositionedDirectional(
        top: -10,
        end: -4,
        child: Text('🍷', style: TextStyle(fontSize: 15, shadows: [Shadow(color: Color(0x99FF2A4A), blurRadius: 8)])),
      ),
    ]);
  }
}


RRect _rr(Size sz) => RRect.fromRectAndRadius(Offset.zero & sz, const Radius.circular(16));

double _frac(double x) => x - x.floorToDouble();

class _BackPainter extends CustomPainter {
  final MsgStyle st;
  final _Pal pal;
  final double t;
  _BackPainter(this.st, this.pal, this.t);

  @override
  void paint(Canvas cv, Size sz) {
    final rr = _rr(sz);
    final rect = Offset.zero & sz;
    if (st.royal) {
      cv.drawRRect(rr, Paint()..shader = const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF45101F), Color(0xFF1E0610)]).createShader(rect));
      return;
    }
    cv.drawRRect(rr, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(pal.d, Colors.black, .35)!, pal.d]).createShader(rect));
    if (st.s > 0) {
      cv.save();
      cv.clipRRect(rr);
      _sparks(cv, sz);
      cv.restore();
    }
  }

  // شهب خفيفة على الخلفية
  void _sparks(Canvas cv, Size sz) {
    const n = 9;
    for (var i = 0; i < n; i++) {
      final seed = math.sin(i * 12.9898) * 43758.5453;
      final x0 = _frac(seed.abs());
      final sp = .55 + _frac(seed.abs() * 1.7) * .6;
      final ph = _frac(t * sp + i / n);
      final a = (math.sin(ph * math.pi)).clamp(0.0, 1.0);
      final size = 2.2 + _frac(seed.abs() * 3.1) * 2.6;
      final col = pal.a.withAlpha((a * 190).toInt());
      final p = Paint()..color = col;
      if (st.s == 5) {
        // شهاب: خط قطري ينزلق من أعلى اليمين لأسفل اليسار
        final hx = sz.width * (1.15 - ph * 1.4) * (.6 + x0 * .5);
        final hy = sz.height * (ph * 1.3 - .1);
        final tail = 16 + size * 3;
        final from = Offset(hx, hy), to = Offset(hx + tail * .8, hy - tail * .6);
        cv.drawLine(
          from,
          to,
          Paint()
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round
            ..shader = LinearGradient(colors: [col, col.withAlpha(0)]).createShader(Rect.fromPoints(from, to)),
        );
        continue;
      }
      final cx = sz.width * x0 + math.sin((ph + i) * 6) * 5;
      final cy = sz.height * (1.05 - ph * 1.1);
      final c = Offset(cx, cy);
      switch (st.s) {
        case 1:
          final s = size * 1.3;
          final q = s * .28;
          cv.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - s)
              ..lineTo(c.dx + q, c.dy - q)
              ..lineTo(c.dx + s, c.dy)
              ..lineTo(c.dx + q, c.dy + q)
              ..lineTo(c.dx, c.dy + s)
              ..lineTo(c.dx - q, c.dy + q)
              ..lineTo(c.dx - s, c.dy)
              ..lineTo(c.dx - q, c.dy - q)
              ..close(),
            p,
          );
          break;
        case 2:
          cv.drawCircle(c, size * .55, p);
          break;
        case 3:
          final s = size;
          cv.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - s)
              ..lineTo(c.dx + s * .7, c.dy)
              ..lineTo(c.dx, c.dy + s)
              ..lineTo(c.dx - s * .7, c.dy)
              ..close(),
            p,
          );
          break;
        default:
          final s = size * .8;
          cv.drawPath(
            Path()
              ..moveTo(c.dx, c.dy + s * .9)
              ..cubicTo(c.dx - s * 1.6, c.dy - s * .2, c.dx - s * .6, c.dy - s * 1.3, c.dx, c.dy - s * .45)
              ..cubicTo(c.dx + s * .6, c.dy - s * 1.3, c.dx + s * 1.6, c.dy - s * .2, c.dx, c.dy + s * .9),
            p,
          );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BackPainter o) => o.t != t || o.st.code != st.code;
}

class _FrontPainter extends CustomPainter {
  final MsgStyle st;
  final _Pal pal;
  final double t;
  _FrontPainter(this.st, this.pal, this.t);

  @override
  void paint(Canvas cv, Size sz) {
    if (sz.isEmpty) return;
    final rr = _rr(sz);
    if (st.royal) {
      _royal(cv, sz, rr);
      return;
    }
    final a = pal.a;
    final rect = Offset.zero & sz;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = a.withAlpha(st.e == 0 ? 130 : 170);
    final pulse = (math.sin(t * 2 * math.pi) + 1) / 2;
    switch (st.e) {
      case 1: // موجة
        cv.save();
        cv.clipRRect(rr);
        for (var k = 0; k < 2; k++) {
          final path = Path()..moveTo(0, sz.height);
          final base = sz.height * (.72 - k * .12);
          for (double x = 0; x <= sz.width; x += 4) {
            path.lineTo(x, base + math.sin((x / sz.width) * 2 * math.pi * (1.4 + k * .5) + t * 2 * math.pi * (k == 0 ? 1 : -1)) * 4.5);
          }
          path
            ..lineTo(sz.width, sz.height)
            ..close();
          cv.drawPath(path, Paint()..color = a.withAlpha(k == 0 ? 38 : 24));
        }
        cv.restore();
        cv.drawRRect(rr, border);
        break;
      case 2: // لمعة
        cv.save();
        cv.clipRRect(rr);
        final x = -sz.width * .4 + (sz.width * 1.8) * t;
        cv.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Colors.transparent, a.withAlpha(70), Colors.white.withAlpha(55), a.withAlpha(70), Colors.transparent],
              stops: const [0, .35, .5, .65, 1],
              transform: GradientRotation(.5),
            ).createShader(Rect.fromLTWH(x - sz.width * .3, -sz.height, sz.width * .6, sz.height * 3)),
        );
        cv.restore();
        cv.drawRRect(rr, border);
        break;
      case 3: // توهّج
        cv.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = a.withAlpha((80 + 110 * pulse).toInt())
            ..maskFilter = MaskFilter.blur(BlurStyle.outer, 5 + 5 * pulse),
        );
        cv.drawRRect(rr, border..strokeWidth = 1.8);
        break;
      case 4: // حافة دوّارة
        cv.drawRRect(rr, border..color = a.withAlpha(60));
        cv.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..shader = SweepGradient(colors: [a.withAlpha(0), a, a.withAlpha(0)], stops: const [0, .12, .3], transform: GradientRotation(t * 2 * math.pi)).createShader(rect),
        );
        break;
      case 5: // نبض
        cv.drawRRect(rr, Paint()..color = a.withAlpha((10 + 22 * pulse).toInt()));
        cv.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3 + 1.4 * pulse
            ..color = a.withAlpha((90 + 140 * pulse).toInt()),
        );
        break;
      default:
        cv.drawRRect(rr, border);
    }
  }

  // ===== الملكي: حواف حمراء + 3 موجات بينها فاصل 3 ثوانٍ (دورة 15 ثانية) =====
  void _royal(Canvas cv, Size sz, RRect rr) {
    final s = t * 15.0;
    final rect = Offset.zero & sz;
    // حافة حمراء ثابتة
    cv.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = const Color(0xFFB3122B),
    );
    // الموجة 1 (0–2ث): نقاط متتابعة تظهر حول الحافة
    if (s < 2) {
      final u = s / 2;
      final path = Path()..addRRect(rr);
      final m = path.computeMetrics().first;
      const n = 18;
      final fade = 1 - ((u - .85) / .15).clamp(0.0, 1.0);
      for (var k = 0; k < n; k++) {
        final at = k / n * .8;
        final al = ((u - at) / .2).clamp(0.0, 1.0) * fade;
        if (al <= 0) continue;
        final tg = m.getTangentForOffset(m.length * k / n);
        if (tg == null) continue;
        cv.drawCircle(tg.position, 2.3, Paint()..color = const Color(0xFFFF4D6A).withAlpha((al * 255).toInt()));
      }
    }
    // الموجة 2 (5–7ث): لمعة خمرية تدور على الحافة
    if (s >= 5 && s < 7) {
      final u = (s - 5) / 2;
      final env = math.sin(u * math.pi);
      cv.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..shader = SweepGradient(
            colors: [const Color(0x00FF3B5C), const Color(0xFFFF5A7A).withAlpha((env * 255).toInt()), const Color(0x00FF3B5C)],
            stops: const [0, .14, .3],
            transform: GradientRotation(u * 2 * math.pi),
          ).createShader(rect),
      );
    }
    // الموجة 3 (10–12ث): تتحول للذهبي لمدة ثانية ثم تخفت
    if (s >= 10 && s < 12) {
      final u = s - 10; // 0..2
      final env = u < .5 ? u / .5 : (u < 1.5 ? 1.0 : (2 - u) / .5);
      final g = const Color(0xFFFFD36B);
      cv.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = g.withAlpha((env * 90).toInt())
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6),
      );
      cv.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = g.withAlpha((env * 255).toInt()),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FrontPainter o) => o.t != t || o.st.code != st.code;
}

/// نافذة اختيار التأثير: ثلاثة أقسام (لون / تأثير / شهب) وفي كل قسم 5 خيارات. وللإمبراطور خيار ملكي إضافي
Future<void> showMsgStyleSheet(BuildContext context) async {
  if (!Session.isDev) return;
  await showAppSheet<void>(context, (sc) => [_StylePicker(close: () => Navigator.of(sc).pop())]);
}

class _StylePicker extends StatefulWidget {
  final VoidCallback close;
  const _StylePicker({required this.close});

  @override
  State<_StylePicker> createState() => _StylePickerState();
}

class _StylePickerState extends State<_StylePicker> {
  int c = 0, e = 0, s = 0;
  bool royal = false;

  @override
  void initState() {
    super.initState();
    final st = MsgStyle.parse(prefs.getString('mst'));
    if (st != null) {
      royal = st.royal && Session.isEmp;
      c = st.c;
      e = st.e;
      s = st.s;
    }
  }

  MsgStyle? get cur => royal ? const MsgStyle(0, 0, 0, royal: true) : ((c == 0 && e == 0 && s == 0) ? null : MsgStyle(c, e, s));

  Widget _sec(String title, List<Widget> chips) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
        Wrap(spacing: 8, runSpacing: 6, children: chips),
      ]);

  Widget _chip(String t, bool sel, VoidCallback on, {Color? dot}) => ChoiceChip(
        selected: sel,
        onSelected: (_) => on(),
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 5)],
          Text(t, style: const TextStyle(fontSize: 12.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final st = cur;
    final preview = Text('هذه معاينة لرسالتك ✨', style: const TextStyle(fontSize: 15, height: 1.5));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Center(child: Text('✨ تأثير رسائلي', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
      const SizedBox(height: 4),
      const Center(child: Text('يظهر على رسائلك أنت فقط (المطورين والإمبراطور)', style: TextStyle(color: kMu, fontSize: 12))),
      const SizedBox(height: 12),
      Center(
        child: st == null
            ? Container(
                padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
                decoration: BoxDecoration(color: const Color(0xFF2A2A3A), borderRadius: BorderRadius.circular(16)),
                child: preview,
              )
            : StyledBubble(st: st, constraints: const BoxConstraints(minWidth: 180), padding: const EdgeInsets.fromLTRB(11, 8, 11, 8), child: preview),
      ),
      if (Session.isEmp)
        _sec('👑 خاص بالإمبراطور', [
          _chip('الملكي 🍷 حواف حمراء وخلفية خمرية', royal, () => setState(() => royal = !royal)),
        ]),
      if (!royal) ...[
        _sec('١) اللون', [for (var i = 0; i < 5; i++) _chip(kMsPalettes[i].n, c == i + 1, () => setState(() => c = c == i + 1 ? 0 : i + 1), dot: kMsPalettes[i].a)]),
        _sec('٢) التأثير', [for (var i = 0; i < 5; i++) _chip(kMsEffects[i], e == i + 1, () => setState(() => e = e == i + 1 ? 0 : i + 1))]),
        _sec('٣) الشهب على الخلفية', [for (var i = 0; i < 5; i++) _chip(kMsSparks[i], s == i + 1, () => setState(() => s = s == i + 1 ? 0 : i + 1))]),
      ],
      const SizedBox(height: 14),
      AppButton('حفظ', onPressed: () {
        final x = cur;
        if (x == null) {
          prefs.setString('mst', '');
          toast('بدون تأثير');
        } else {
          // اللون وحده أو الشهب وحدها كافية؛ نضمن لوناً افتراضياً عند اختيار تأثير بلا لون
          final y = x.royal ? x : MsgStyle(x.c == 0 ? 1 : x.c, x.e, x.s);
          prefs.setString('mst', y.code);
          toast('تم حفظ التأثير ✅');
        }
        widget.close();
      }),
      AppButton('بدون تأثير', kind: 'g', onPressed: () {
        prefs.setString('mst', '');
        toast('تم إلغاء التأثير');
        widget.close();
      }),
    ]);
  }
}
