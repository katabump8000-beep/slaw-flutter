import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'sfx.dart';

/// دخول الإمبراطور/المطور إلى شات نقابة: عرض سينمائي يراه المتواجدون في الشات
Future<void> announceEntrance(String gid, String type) async {
  try {
    await ref('entrance/$gid').set(<String, Object?>{'u': myUid, 't': type, 'n': Session.me.name, 'ts': ServerValue.timestamp});
  } catch (_) {}
}

bool shouldShowEntrance(Object? v, String gid) {
  if (v is! Map) return false;
  final ts = (v['ts'] as num?)?.toInt() ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  if ((now - ts).abs() > 12000) return false;
  if (prefs.getInt('ent_$gid') == ts) return false;
  prefs.setInt('ent_$gid', ts);
  return v['u'] != myUid;
}

double _s(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

class EntranceScreen extends StatefulWidget {
  final bool emperor;
  final String name;
  const EntranceScreen({super.key, required this.emperor, required this.name});

  @override
  State<EntranceScreen> createState() => _EntranceState();
}

class _EntranceState extends State<EntranceScreen> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.emperor ? 6800 : 4500))..forward();

  @override
  void initState() {
    super.initState();
    Sfx.block('show');
    Sfx.playWait(widget.emperor ? 'emp_in.wav' : 'dev_in.wav');
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    c.dispose();
    Sfx.unblock('show');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AbsorbPointer(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: AnimatedBuilder(
            animation: c,
            builder: (_, __) {
              final t = c.value * (widget.emperor ? 6.8 : 4.5);
              return CustomPaint(
                painter: widget.emperor ? _EmpPainter(t) : _DevPainter(t),
                child: Center(child: _text(t)),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _text(double t) {
    if (widget.emperor) {
      final o = _s(t, 5.4, 6.0);
      return Opacity(
        opacity: o,
        child: const Text('دخول الإمبراطور إلى الشات', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), shadows: [Shadow(color: Colors.white, blurRadius: 16)])),
      );
    }
    final full = 'دخول أحد المطورين: ${widget.name}';
    final n = (full.length * _s(t, 1.2, 3.2)).round();
    return Text(full.substring(0, n), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(color: Color(0xFFFF6A00), blurRadius: 22), Shadow(color: Color(0xFFFFD54A), blurRadius: 36)]));
  }
}

class _EmpPainter extends CustomPainter {
  final double t;
  _EmpPainter(this.t);
  final List<double> seeds = List<double>.generate(120, (i) => (i * 97 % 360) + (i % 7) * .13);

  @override
  void paint(Canvas cv, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    cv.drawRect(Offset.zero & s, Paint()..color = Colors.black);
    // نجوم تندفع نحو الأطراف (انطلاق في الفضاء)
    final speed = 0.15 + _s(t, 0, 3.8) * 1.6;
    for (var i = 0; i < seeds.length; i++) {
      final a = seeds[i] * pi / 180;
      final r0 = ((i * 53 % 100) / 100) * 0.5;
      final r = ((r0 + t * speed * 0.35 + i * 0.011) % 1.0) * s.longestSide * .75;
      final p = c + Offset(cos(a), sin(a)) * r;
      final len = 2 + r * .05 * _s(t, 0, 3.8);
      cv.drawLine(p, p + Offset(cos(a), sin(a)) * len, Paint()..color = Colors.white.withAlpha((120 + (i % 5) * 25).clamp(0, 255))..strokeWidth = 1.4);
    }
    // شق فضي قلبه أسود
    final crack = _s(t, 3.0, 3.8);
    if (crack > 0) {
      final h = s.height * .45 * crack;
      for (final dx in [-24.0, 24.0]) {
        final path = Path()..moveTo(c.dx + dx, c.dy - h);
        var y = c.dy - h;
        var k = 0;
        while (y < c.dy + h) {
          y += 38;
          path.lineTo(c.dx + dx + (k.isEven ? 10 : -10), y);
          k++;
        }
        cv.drawPath(path, Paint()..color = const Color(0xFFC9D3DD)..style = PaintingStyle.stroke..strokeWidth = 4);
      }
      cv.drawRect(Rect.fromCenter(center: c, width: 40, height: h * 2), Paint()..color = Colors.black);
      // عينان بحواف حادة داخل الشق
      final eye = _s(t, 3.6, 4.2);
      if (eye > 0) {
        for (final ex in [-1.0, 1.0]) {
          final cx = c.dx + ex * 62, cy = c.dy - 8;
          final w = 44 * eye, hh = 12 * eye;
          final e = Path()
            ..moveTo(cx - w, cy + ex * 6)
            ..lineTo(cx, cy - hh)
            ..lineTo(cx + w, cy - ex * 6)
            ..lineTo(cx, cy + hh)
            ..close();
          cv.drawPath(e, Paint()..color = const Color(0xFFFF2B2B).withAlpha(230)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
          cv.drawPath(e, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
        }
      }
    }
    // نقطة بيضاء تكبر وتتحول إلى نجم يشع ثم يعمي الشاشة
    final dot = _s(t, 4.1, 5.4);
    if (dot > 0) {
      final r = 4 + dot * dot * s.longestSide * 1.2;
      cv.drawCircle(c, r, Paint()..color = Colors.white..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + dot * 30));
      for (var i = 0; i < 12; i++) {
        final a = i * pi / 6 + t;
        cv.drawLine(c, c + Offset(cos(a), sin(a)) * r * 1.6, Paint()..color = Colors.white.withAlpha(120)..strokeWidth = 2);
      }
    }
    // يعود الأبيض إلى الظلام في النهاية
    final fade = _s(t, 6.1, 6.8);
    if (fade > 0 && dot >= 1) cv.drawRect(Offset.zero & s, Paint()..color = Colors.black.withAlpha((fade * 255).round()));
  }

  @override
  bool shouldRepaint(covariant _EmpPainter old) => old.t != t;
}

class _DevPainter extends CustomPainter {
  final double t;
  _DevPainter(this.t);

  @override
  void paint(Canvas cv, Size s) {
    cv.drawRect(Offset.zero & s, Paint()..color = Colors.black);
    final grow = _s(t, 0, 1.2);
    // قساس نار يتصاعد من كل أطراف الشاشة
    for (var i = 0; i < 90; i++) {
      final edge = i % 4;
      final f = (i * 37 % 100) / 100;
      final life = ((t * (0.5 + (i % 5) * .12) + f) % 1.0);
      Offset p;
      switch (edge) {
        case 0:
          p = Offset(f * s.width, s.height - life * s.height * .55 * grow);
          break;
        case 1:
          p = Offset(f * s.width, life * s.height * .55 * grow);
          break;
        case 2:
          p = Offset(life * s.width * .4 * grow, f * s.height);
          break;
        default:
          p = Offset(s.width - life * s.width * .4 * grow, f * s.height);
      }
      final a = ((1 - life) * 220).round().clamp(0, 255);
      cv.drawCircle(p, 2.5 + (i % 4), Paint()..color = Color.lerp(const Color(0xFFFFD54A), const Color(0xFFFF3B00), life)!.withAlpha(a)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
    final out = _s(t, 4.0, 4.5);
    if (out > 0) cv.drawRect(Offset.zero & s, Paint()..color = Colors.black.withAlpha((out * 255).round()));
  }

  @override
  bool shouldRepaint(covariant _DevPainter old) => old.t != t;
}
