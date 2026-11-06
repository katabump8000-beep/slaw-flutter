import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'servertime.dart';

/// عملة نقدية مرسومة (مدورة ومزخرفة) بدل إيموجي 💰
class CoinIcon extends StatelessWidget {
  final double size;
  const CoinIcon({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _CoinPainter());
}

class _CoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2;
    final body = Paint()
      ..shader = const RadialGradient(colors: [Color(0xFFFFEB99), Color(0xFFF5B700), Color(0xFFB87800)], stops: [0, .6, 1]).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, body);
    canvas.drawCircle(c, r - r * .06, Paint()..style = PaintingStyle.stroke..strokeWidth = r * .12..color = const Color(0xFF8A5A00));
    final ir = r * .68;
    canvas.drawCircle(c, ir, Paint()..style = PaintingStyle.stroke..strokeWidth = r * .07..color = const Color(0xFFFFF2B0));
    final dot = Paint()..color = const Color(0xFF8A5A00);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * (r * .82), r * .05, dot);
    }
    final tp = TextPainter(
      text: TextSpan(text: '★', style: TextStyle(fontSize: r * 1.05, color: const Color(0xFF8A5A00), fontWeight: FontWeight.w900, height: 1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// درع مرسوم لحماية النقابة الجديدة
class ShieldIcon extends StatelessWidget {
  final double size;
  final Color color;
  const ShieldIcon({super.key, this.size = 12, this.color = const Color(0xFF4FC3F7)});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size * 1.15), painter: _ShieldPainter(color));
}

class _ShieldPainter extends CustomPainter {
  final Color color;
  _ShieldPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final p = Path()
      ..moveTo(w / 2, 0)
      ..cubicTo(w * .75, h * .12, w * .92, h * .14, w, h * .16)
      ..cubicTo(w, h * .62, w * .78, h * .86, w / 2, h)
      ..cubicTo(w * .22, h * .86, 0, h * .62, 0, h * .16)
      ..cubicTo(w * .08, h * .14, w * .25, h * .12, w / 2, 0)
      ..close();
    canvas.drawPath(p, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, color, color.withAlpha(200)]).createShader(Rect.fromLTWH(0, 0, w, h)));
    canvas.drawPath(p, Paint()..style = PaintingStyle.stroke..strokeWidth = w * .09..color = Colors.white70);
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter old) => old.color != color;
}

/// درع صغير + عداد الأيام بجانب اسم النقابة (يختفي عند انتهاء الحماية)
class ShieldBadge extends StatelessWidget {
  final int until;
  const ShieldBadge({super.key, required this.until});

  @override
  Widget build(BuildContext context) {
    final left = until - nowMs();
    if (until <= 0 || left <= 0) return const SizedBox.shrink();
    final days = (left / 86400000).ceil();
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const ShieldIcon(size: 11),
        const SizedBox(width: 2),
        Text('$days', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF4FC3F7))),
      ]),
    );
  }
}

/// أيقونة يد الألعاب المرسومة
class GamepadIcon extends StatelessWidget {
  final double size;
  final Color color;
  const GamepadIcon({super.key, this.size = 26, this.color = const Color(0xFF39FF88)});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size * 1.3, size), painter: _PadPainter(color));
}

class _PadPainter extends CustomPainter {
  final Color color;
  _PadPainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, h * .18, w, h * .64), Radius.circular(h * .32));
    canvas.drawRRect(body, Paint()..color = color.withAlpha(60));
    canvas.drawRRect(body, Paint()..style = PaintingStyle.stroke..strokeWidth = h * .09..color = color);
    final k = Paint()..color = color;
    final cx = w * .27, cy = h * .5, a = h * .16;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: a * 2.4, height: a * .8), const Radius.circular(2)), k);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: a * .8, height: a * 2.4), const Radius.circular(2)), k);
    canvas.drawCircle(Offset(w * .72, h * .42), h * .08, k);
    canvas.drawCircle(Offset(w * .82, h * .58), h * .08, k);
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) => old.color != color;
}

/// زر الفعاليات في شريط الشات: كبير ويتوهج بالأخضر مع اسم صغير تحته
class GamesActionButton extends StatefulWidget {
  final VoidCallback onTap;
  const GamesActionButton({super.key, required this.onTap});

  @override
  State<GamesActionButton> createState() => _GamesActionState();
}

class _GamesActionState extends State<GamesActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: c,
            builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: const Color(0xFF39FF88).withAlpha((70 + 110 * c.value).round()), blurRadius: 8 + 10 * c.value, spreadRadius: 1)],
                ),
                child: const GamepadIcon(size: 24),
              ),
              const SizedBox(height: 1),
              const Text('الفعاليات', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF39FF88))),
            ]),
          ),
        ),
      ),
    );
  }
}
