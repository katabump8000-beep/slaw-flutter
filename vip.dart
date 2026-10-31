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
              const Text('VIP 👑', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFFFFD54A))),
              const SizedBox(height: 10),
              Text(
                on
                    ? 'وضع VIP مفعّل الآن. هل تريد إيقافه؟'
                    : 'عزيزي هذا يزيد من جمال التطبيق لكن قد يسبب حملاً وثقلاً وضعف حركة ولاقاً إذا كان هاتفك ضعيفاً.',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.8),
              ),
              const SizedBox(height: 14),
              AppButton(on ? 'إيقاف VIP' : 'تأكيد', onPressed: () {
                setVip(!on);
                Navigator.of(sc).pop();
                toast(on ? 'تم إيقاف VIP' : 'تم تفعيل VIP 👑');
              }),
              const SizedBox(height: 8),
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

  @override
  void paint(Canvas cv, Size s) {
    final ms = el.value.inMilliseconds;
    final cycle = ms ~/ 3000;
    final t = (ms % 3000) / 3000;
    if (t > .55) return;
    final k = t / .55;
    final r = math.Random(cycle * 7919 + 13);
    final x0 = s.width * (.25 + r.nextDouble() * .75);
    final y0 = s.height * (.02 + r.nextDouble() * .35);
    final ang = math.pi * (r.nextBool() ? .72 : .28);
    final dir = Offset(math.cos(ang), math.sin(ang));
    final len = s.height * .45;
    final head = Offset(x0, y0) + dir * (len * k);
    final tail = head - dir * 110;
    final a = (1 - (k - .5).abs() * 2).clamp(0.0, 1.0);
    final p = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(colors: [col.withAlpha(0), Colors.white.withAlpha((230 * a).round())]).createShader(Rect.fromPoints(tail, head));
    cv.drawLine(tail, head, p);
    cv.drawCircle(head, 2.6, Paint()..color = Colors.white.withAlpha((240 * a).round())..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  }

  @override
  bool shouldRepaint(covariant _StarsPainter old) => false;
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
