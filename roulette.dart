import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'core.dart';
import 'data.dart';
import 'sfx.dart';
import 'widgets.dart';

const List<int> _prizes = [50, 100, 150, 200, 250, 300, 400, 500, 750, 1000];
const List<int> _weights = [22, 20, 16, 12, 10, 8, 5, 4, 2, 1];
const List<Color> _segCols = [
  Color(0xFFFF4D4D), Color(0xFFFF9A1F), Color(0xFFFFD83B), Color(0xFF2EE07A), Color(0xFF2EC8FF),
  Color(0xFF5B7BFF), Color(0xFFA64BFF), Color(0xFFFF4FA0), Color(0xFF19C7B0), Color(0xFFFFFFFF),
];

/// عجلة روليت صغيرة ملونة في الواجهة الرئيسية
class RouletteFab extends StatelessWidget {
  const RouletteFab({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RouletteScreen())),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black, border: Border.all(color: const Color(0xFFFFD54A), width: 2), boxShadow: const [BoxShadow(color: Color(0x88FFB000), blurRadius: 14)]),
        child: const Padding(padding: EdgeInsets.all(5), child: CustomPaint(painter: _WheelPainter(0, small: true))),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double rot;
  final bool small;
  const _WheelPainter(this.rot, {this.small = false});

  @override
  void paint(Canvas cv, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = math.min(s.width, s.height) / 2;
    final seg = 2 * math.pi / _prizes.length;
    for (var i = 0; i < _prizes.length; i++) {
      final a0 = -math.pi / 2 + rot + i * seg;
      cv.drawArc(Rect.fromCircle(center: c, radius: r), a0, seg, true, Paint()..color = _segCols[i]);
      cv.drawArc(Rect.fromCircle(center: c, radius: r), a0, seg, true, Paint()..style = PaintingStyle.stroke..strokeWidth = small ? 1 : 2..color = Colors.black54);
      if (!small) {
        final tp = TextPainter(
          text: TextSpan(text: '${_prizes[i]}', style: TextStyle(color: i == 9 || i == 2 ? Colors.black : Colors.white, fontSize: r * .13, fontWeight: FontWeight.w900)),
          textDirection: TextDirection.ltr,
        )..layout();
        final am = a0 + seg / 2;
        cv.save();
        cv.translate(c.dx + math.cos(am) * r * .68, c.dy + math.sin(am) * r * .68);
        cv.rotate(am + math.pi / 2);
        tp.paint(cv, Offset(-tp.width / 2, -tp.height / 2));
        cv.restore();
      }
    }
    cv.drawCircle(c, r * .12, Paint()..color = Colors.black);
    cv.drawCircle(c, r * .12, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFFFFD54A));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.rot != rot;
}

class RouletteScreen extends StatefulWidget {
  const RouletteScreen({super.key});

  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

class _RouletteScreenState extends State<RouletteScreen> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4600));
  double from = 0, to = 0;
  bool busy = false;
  String info = 'لفّة واحدة كل 12 ساعة';
  int left = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final v = (await ref('spin/$myUid').get()).value;
      if (v is num) {
        final l = 43200000 - (DateTime.now().millisecondsSinceEpoch - v.toInt());
        if (l > 0 && mounted) {
          setState(() {
            left = l;
            info = 'اللفة القادمة بعد ${_fmt(l)}';
          });
        }
      }
    } catch (_) {}
  }

  String _fmt(int ms) {
    final m = (ms / 60000).ceil();
    return m >= 60 ? '${m ~/ 60} ساعة و${m % 60} دقيقة' : '$m دقيقة';
  }

  int _pick() {
    final t = _weights.fold<int>(0, (a, b) => a + b);
    var r = math.Random().nextInt(t);
    for (var i = 0; i < _weights.length; i++) {
      r -= _weights[i];
      if (r < 0) return i;
    }
    return 0;
  }

  Future<void> _spin() async {
    if (busy || left > 0) {
      toast(left > 0 ? 'اللفة القادمة بعد ${_fmt(left)}' : 'انتظر...', bad: true);
      return;
    }
    setState(() => busy = true);
    try {
      await ref('spin/$myUid').set(ServerValue.timestamp);
    } catch (_) {
      toast('لا يمكنك اللف الآن، حاول لاحقاً', bad: true);
      await _check();
      if (mounted) setState(() => busy = false);
      return;
    }
    final k = _pick();
    final seg = 2 * math.pi / _prizes.length;
    // يجب أن يقف منتصف القطاع k تحت المؤشر في الأعلى
    to = 2 * math.pi * (5 + math.Random().nextInt(2)) - (k + .5) * seg;
    from = 0;
    Sfx.start('wheel.wav');
    c.reset();
    await c.forward();
    final prize = _prizes[k];
    try {
      await addBalRetry(prize);
      if (mounted) setState(() => info = '🎉 ربحت $prize رصيد!');
      toast('🎉 ربحت $prize رصيد');
    } catch (_) {
      toast('تعذر إضافة الجائزة، تواصل مع مطور', bad: true);
    }
    left = 43200000;
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎡 عجلة الحظ')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.arrow_drop_down_rounded, size: 54, color: Color(0xFFFFD54A)),
          SizedBox(
            width: 300,
            height: 300,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: c,
                builder: (_, __) {
                  final e = Curves.easeOutCubic.transform(c.value);
                  return DecoratedBox(
                    decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x66FFB000), blurRadius: 24)]),
                    child: CustomPaint(painter: _WheelPainter(from + (to - from) * e)),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(info, style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 14),
          SizedBox(width: 220, child: AppButton(busy ? '...' : 'لف 🎡', glow: true, onPressed: busy || left > 0 ? null : _spin)),
        ]),
      ),
    );
  }
}
