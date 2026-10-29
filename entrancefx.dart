import 'dart:math' as m;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'sfx.dart';

const List<String> kFxNames = ['', '⚡ الرعد', '🔥 نار العنقاء', '🌑 ظلال الليل', '🌸 بتلات الورد', '✨ نجوم ساحرة'];

/// يُعرض عند زيارة ملف مطور/إمبراطور اختار مؤثر دخول
Future<void> playEntrance(BuildContext context, String uid) async {
  if (uid == myUid) return;
  try {
    final v = (await ref('pdata/$uid/fx').get()).value;
    final k = v is num ? v.toInt() : 0;
    if (k <= 0) return;
    final p = await prof(uid);
    if (!context.mounted) return;
    await Navigator.of(context).push(PageRouteBuilder<void>(opaque: true, pageBuilder: (_, __, ___) => FxScreen(kind: k, name: p.name)));
  } catch (_) {}
}

class FxScreen extends StatefulWidget {
  final int kind;
  final String name;
  const FxScreen({super.key, required this.kind, required this.name});
  @override
  State<FxScreen> createState() => _FxState();
}

class _FxState extends State<FxScreen> with SingleTickerProviderStateMixin {
  static AudioPlayer? _keep;
  AudioPlayer? _own;
  late final double secs = widget.kind == 9 ? 12 : 6;
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: (secs * 1000).toInt()));

  @override
  void initState() {
    super.initState();
    Sfx.block('show');
    _audio();
    c.forward().whenComplete(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _audio() async {
    var f = 'fx${widget.kind}.wav';
    if (widget.kind == 9) {
      try {
        await rootBundle.load('assets/audio/kool.mp3');
        f = 'kool.mp3';
      } catch (_) {
        f = 'kool.wav';
      }
    }
    final p = await Sfx.start(f);
    if (widget.kind == 9) {
      try {
        await _keep?.stop();
      } catch (_) {}
      _keep = p;
    } else {
      _own = p;
    }
  }

  @override
  void dispose() {
    Sfx.unblock('show');
    try {
      _own?.stop();
      _own?.dispose();
    } catch (_) {}
    c.dispose();
    super.dispose();
  }

  Color get _tc => const [Colors.white, Color(0xFF8FC1FF), Color(0xFFFFB347), Color(0xFFC49BFF), Color(0xFFFFB6D2), Color(0xFFFFE7A0)][widget.kind == 9 ? 0 : widget.kind];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AbsorbPointer(
          child: Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: _FxPainter(widget.kind, c, secs)),
            AnimatedBuilder(
              animation: c,
              builder: (_, __) {
                final s = c.value * secs;
                final k9 = widget.kind == 9;
                final a0 = k9 ? .6 : .5, a1 = k9 ? 1.4 : 1.2, b0 = k9 ? 2.6 : 4.4, b1 = k9 ? 3.4 : 5.2;
                final o = (((s - a0) / (a1 - a0)).clamp(0.0, 1.0)) * (1 - ((s - b0) / (b1 - b0)).clamp(0.0, 1.0));
                return Center(
                  child: Opacity(
                    opacity: o,
                    child: Transform.scale(
                      scale: .8 + .2 * o,
                      child: Text(widget.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: k9 ? const Color(0xFFFF3030) : _tc, shadows: [Shadow(color: k9 ? const Color(0xFFFF0000) : _tc, blurRadius: 28)])),
                    ),
                  ),
                );
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _FxPainter extends CustomPainter {
  final int kind;
  final Animation<double> a;
  final double secs;
  _FxPainter(this.kind, this.a, this.secs) : super(repaint: a);

  @override
  void paint(Canvas cv, Size sz) {
    final s = a.value * secs;
    cv.drawRect(Offset.zero & sz, Paint()..color = Colors.black);
    switch (kind) {
      case 9:
        _kool(cv, sz, s);
        break;
      case 1:
        _bolt(cv, sz, s);
        break;
      case 2:
        _fire(cv, sz, s);
        break;
      case 3:
        _smoke(cv, sz, s);
        break;
      case 4:
        _petals(cv, sz, s);
        break;
      default:
        _stars(cv, sz, s);
    }
    final fo = ((s - (secs - .7)) / .7).clamp(0.0, 1.0);
    if (fo > 0) cv.drawRect(Offset.zero & sz, Paint()..color = Color.fromRGBO(0, 0, 0, fo));
  }

  Paint _glow(Color c, double w, double blur) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..color = c
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

  void _kool(Canvas cv, Size sz, double s) {
    final w = sz.width, h = sz.height, cx = w / 2, cy = h * .45;
    if (s > 3.6 && s < 7.6) {
      final open = s < 4.6 ? Curves.easeOut.transform(s - 3.6) : (s > 7.0 ? (1 - (s - 7.0) / .6).clamp(0.0, 1.0) : 1.0);
      final gl = .6 + .4 * m.sin(s * 6);
      for (final side in [-1.0, 1.0]) {
        cv.save();
        cv.translate(cx + side * w * .2, cy);
        cv.rotate(-side * .32);
        final aw = w * .18, bh = h * .075 * open;
        final p = Path()
          ..moveTo(-aw, 0)
          ..quadraticBezierTo(0, -bh * 2, aw, 0)
          ..quadraticBezierTo(0, bh * 1.2, -aw, 0)
          ..close();
        cv.drawPath(p, Paint()..color = Color.fromRGBO(255, 20, 20, .55 * gl)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
        cv.drawPath(p, Paint()..shader = const RadialGradient(colors: [Color(0xFFFF3A2A), Color(0xFF8A0000)]).createShader(Rect.fromCircle(center: Offset.zero, radius: aw)));
        cv.drawOval(Rect.fromCenter(center: Offset.zero, width: aw * .12, height: bh * 1.5), Paint()..color = Colors.black);
        cv.restore();
      }
    }
    const lines = [
      [.05, .1, .95, .8, 7.4],
      [.95, .15, .1, .7, 8.2],
      [.2, .95, .85, .05, 9.0],
    ];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final st = l[4];
      if (s < st) continue;
      final p = ((s - st) / .22).clamp(0.0, 1.0);
      final a0 = Offset(l[0] * w, l[1] * h), a1 = Offset(l[2] * w, l[3] * h);
      final e = Offset.lerp(a0, a1, p)!;
      final fade = (1 - ((s - st - .4) / 2.0)).clamp(.25, 1.0);
      final col = i == 2 ? const Color(0xFFFF2A2A) : const Color(0xFFDDE6FF);
      cv.drawLine(a0, e, _glow(Color.fromRGBO(col.red, col.green, col.blue, .8 * fade), i == 2 ? 20 : 12, 14));
      cv.drawLine(a0, e, Paint()..color = Colors.white..strokeWidth = i == 2 ? 5 : 3..strokeCap = StrokeCap.round);
      final fl = 1 - (s - st) / .3;
      if (fl > 0) cv.drawRect(Offset.zero & sz, Paint()..color = Color.fromRGBO(255, 255, 255, .45 * fl));
      if (i == 2 && s > st + .2) {
        cv.drawCircle(Offset(cx, cy), (s - st - .2).clamp(0.0, 1.5) * w * .18, Paint()..color = Colors.black);
        cv.drawCircle(Offset(cx, cy), (s - st - .2).clamp(0.0, 1.5) * w * .18, _glow(const Color(0xCCFF1A1A), 6, 10));
      }
    }
  }

  void _bolt(Canvas cv, Size sz, double s) {
    final w = sz.width, h = sz.height;
    cv.drawRect(Offset.zero & sz, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF020818), Color(0xFF0B1E4A)]).createShader(Offset.zero & sz));
    final b = (s * 5).floor(), fr = s * 5 - b;
    final r = m.Random(b * 7919 + 3);
    if (fr < .55 && s > .3) {
      cv.drawRect(Offset.zero & sz, Paint()..color = Color.fromRGBO(170, 200, 255, .22 * (1 - fr / .55)));
      for (var k = 0; k < 2; k++) {
        var x = w * (.15 + .7 * r.nextDouble());
        var y = 0.0;
        final p = Path()..moveTo(x, y);
        while (y < h) {
          y += h / 10;
          x += (r.nextDouble() - .5) * w * .18;
          p.lineTo(x, y);
        }
        cv.drawPath(p, _glow(const Color(0x884D8DFF), 9, 12));
        cv.drawPath(p, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white);
      }
    }
  }

  void _fire(Canvas cv, Size sz, double s) {
    final w = sz.width, h = sz.height;
    cv.drawRect(Offset.zero & sz, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Color(0xFF3A0500)]).createShader(Offset.zero & sz));
    for (var i = 0; i < 45; i++) {
      final r = m.Random(i * 31 + 7);
      final sp = .25 + .5 * r.nextDouble();
      final pr = (s * sp + r.nextDouble()) % 1.0;
      final x = w * r.nextDouble() + m.sin(s * 3 + i) * 14;
      final y = h * (1.05 - pr);
      final rad = (18 + 46 * r.nextDouble()) * (1 - pr * .7);
      final col = Color.lerp(const Color(0xFFFFE066), const Color(0xFFFF3B00), pr)!;
      cv.drawCircle(Offset(x, y), rad, Paint()..color = col.withAlpha(((1 - pr) * 150).toInt())..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
  }

  void _smoke(Canvas cv, Size sz, double s) {
    final w = sz.width, h = sz.height;
    cv.drawRect(Offset.zero & sz, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF05010A), Color(0xFF1A0A2E)]).createShader(Offset.zero & sz));
    for (var i = 0; i < 24; i++) {
      final r = m.Random(i * 17 + 5);
      final pr = (s * .15 + r.nextDouble()) % 1.0;
      cv.drawCircle(Offset(w * (r.nextDouble() + .08 * m.sin(s + i)), h * (1.1 - pr * 1.2)), 60 + 70 * r.nextDouble(), Paint()..color = const Color(0x40A06BFF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34));
    }
  }

  void _petals(Canvas cv, Size sz, double s) {
    final w = sz.width, h = sz.height;
    cv.drawRect(Offset.zero & sz, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B0610), Color(0xFF3A0F24)]).createShader(Offset.zero & sz));
    for (var i = 0; i < 36; i++) {
      final r = m.Random(i * 13 + 11);
      final pr = (s * .22 * (.5 + r.nextDouble()) + r.nextDouble()) % 1.0;
      cv.save();
      cv.translate(w * r.nextDouble() + 30 * m.sin(s * 2 + i), h * 1.05 * pr - 20);
      cv.rotate(s * 2 + i);
      cv.drawOval(Rect.fromCenter(center: Offset.zero, width: 14 + 10 * r.nextDouble(), height: 24 + 10 * r.nextDouble()), Paint()..color = Color.lerp(const Color(0xFFFF8FB8), const Color(0xFFFFD0E2), r.nextDouble())!.withAlpha(215));
      cv.restore();
    }
  }

  void _stars(Canvas cv, Size sz, double s) {
    final w = sz.width, h = sz.height;
    cv.drawRect(Offset.zero & sz, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF040414), Color(0xFF14123A)]).createShader(Offset.zero & sz));
    for (var i = 0; i < 55; i++) {
      final r = m.Random(i * 23 + 9);
      final tw = .5 + .5 * m.sin(s * 4 + i);
      final c = Offset(w * r.nextDouble(), h * r.nextDouble());
      final rad = 3 + 11 * r.nextDouble() * tw;
      final p = Path()
        ..moveTo(c.dx, c.dy - rad)
        ..lineTo(c.dx + rad * .25, c.dy - rad * .25)
        ..lineTo(c.dx + rad, c.dy)
        ..lineTo(c.dx + rad * .25, c.dy + rad * .25)
        ..lineTo(c.dx, c.dy + rad)
        ..lineTo(c.dx - rad * .25, c.dy + rad * .25)
        ..lineTo(c.dx - rad, c.dy)
        ..lineTo(c.dx - rad * .25, c.dy - rad * .25)
        ..close();
      cv.drawPath(p, Paint()..color = Color.lerp(const Color(0xFFFFE7A0), Colors.white, tw)!.withAlpha(230)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }
    final sp = (s * .5) % 1.0;
    final a0 = Offset(w * (1.1 - sp * 1.3), h * (.05 + sp * .5));
    cv.drawLine(a0, a0 + const Offset(70, -40), _glow(const Color(0xCCFFFFFF), 3, 3));
  }

  @override
  bool shouldRepaint(covariant _FxPainter o) => true;
}
