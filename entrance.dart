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
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.emperor ? 4000 : 4500))..forward();

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
              final t = c.value * (widget.emperor ? 4.0 : 4.5);
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
      final o = _s(t, 0.5, 1.3) * (1 - _s(t, 3.4, 3.95));
      final p = (t / 4.0).clamp(0.0, 1.0);
      return Opacity(
        opacity: o,
        child: Transform.scale(
          scale: 0.86 + 0.14 * _s(t, 0.5, 1.6),
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment(-3 + 4 * p, 0),
              end: Alignment(-1 + 4 * p, 0),
              colors: const [Color(0xFFD4AF37), Color(0xFFFFFFFF), Color(0xFFD4AF37)],
            ).createShader(r),
            child: const Text(
              'انضم الإمبراطور إلى الشات معكم !',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 27, height: 1.6, fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
        ),
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

  @override
  void paint(Canvas cv, Size s) {
    cv.drawRect(Offset.zero & s, Paint()..color = Colors.black);
    final c = Offset(s.width / 2, s.height / 2);
    final glow = _s(t, 0.3, 1.5) * (1 - _s(t, 3.4, 4.0));
    if (glow > 0) {
      cv.drawCircle(c, s.width * .55, Paint()..color = Color.fromRGBO(140, 10, 30, .28 * glow)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
    }
    // جمرات ذهبية صاعدة
    for (var i = 0; i < 36; i++) {
      final f = (i * 37 % 100) / 100;
      final life = (t * (0.18 + (i % 5) * .05) + f) % 1.0;
      final x = s.width * f + sin(t * 2 + i) * 10;
      final y = s.height * (1.05 - life * 1.1);
      final a = ((1 - life) * 200 * glow).round().clamp(0, 255);
      cv.drawCircle(Offset(x, y), 1.5 + (i % 3), Paint()..color = Color.lerp(const Color(0xFFFFE066), const Color(0xFFFF5A1F), life)!.withAlpha(a)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }
    // خط ذهبي رفيع يتمدد تحت النص
    final ln = _s(t, 1.0, 2.0) * (1 - _s(t, 3.4, 4.0));
    if (ln > 0) {
      final w = s.width * .5 * ln;
      cv.drawLine(Offset(c.dx - w, c.dy + 46), Offset(c.dx + w, c.dy + 46), Paint()..color = const Color(0xFFD4AF37).withAlpha(200)..strokeWidth = 2..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    }
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
