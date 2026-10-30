import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';

/// الصورة الشخصية الدائرية (أو أول حرف من الاسم)
class UserAvatar extends StatefulWidget {
  final String uid;
  final double size;
  final VoidCallback? onTap;
  final bool ring;
  final Color? ringColor;

  const UserAvatar(
    this.uid, {
    super.key,
    this.size = 42,
    this.onTap,
    this.ring = false,
    this.ringColor,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  String letter = '';
  MemoryImage? image;

  @override
  void initState() {
    super.initState();
    avatarTick.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant UserAvatar old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _load();
  }

  @override
  void dispose() {
    avatarTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await prof(widget.uid);
    final a = await avOf(widget.uid);
    if (!mounted) return;
    setState(() {
      letter = firstChar(p.name);
      image = avImage(widget.uid, a);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final rc = widget.ringColor ?? context.accent;
    final img = image;
    final box = Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF3A1A0D),
        image: img == null ? null : DecorationImage(image: img, fit: BoxFit.cover),
        border: widget.ring ? Border.all(color: rc, width: 3) : null,
        boxShadow: widget.ring ? [BoxShadow(color: rc, blurRadius: 18)] : null,
      ),
      child: img == null
          ? Text(letter, style: TextStyle(fontSize: s * .39, fontWeight: FontWeight.w800))
          : null,
    );
    if (widget.onTap == null) return box;
    return GestureDetector(onTap: widget.onTap, child: box);
  }
}

/// وسم صغير (رتبة، عمر العضو، جنس...)
class Tag extends StatelessWidget {
  final String text;
  final bool king;
  final Color? fg;
  final Color? bg;
  final IconData? icon;

  const Tag(this.text, {super.key, this.king = false, this.fg, this.bg, this.icon});

  @override
  Widget build(BuildContext context) {
    final color = king ? kDarkText : (fg ?? context.accent2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: king ? null : (bg ?? accentA(context, .18)),
        gradient: king
            ? LinearGradient(colors: [context.accent2, context.accent])
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: king ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// وسم الرتبة (الإمبراطور / رتبة عليا)
Widget? rankTag(String? r) {
  if (r == 'emp') return const Tag('الإمبراطور', king: true, icon: Icons.workspace_premium);
  if (r == 'dev') return const Tag('رتبة عليا');
  return null;
}

/// وسم عمر العضو: عضو (أقل من 3 أيام) / مخضرم (3) / نخبة (10) / أسطورة (50). الرتب العليا أسطورة دائماً
Widget ageTag(Prof p, {String? role}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final ts = p.ts == 0 ? now : p.ts;
  final d = (now - ts) / 86400000;
  String t;
  String c;
  if (role == 'dev' || role == 'emp' || d >= 50) {
    t = 'أسطورة';
    c = '#b46bff';
  } else if (d >= 10) {
    t = 'نخبة';
    c = '#ffb04a';
  } else if (d >= 3) {
    t = 'مخضرم';
    c = '#6ee787';
  } else {
    t = 'عضو';
    c = '#8fa3bf';
  }
  final rgb = rgbOf(c);
  return Tag(
    t,
    fg: hexColor(c),
    bg: Color.fromRGBO(rgb[0], rgb[1], rgb[2], .15),
  );
}

/// زر التطبيق: main (لون الواجهة) / g (رمادي) / r (أحمر)
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final String kind;
  final IconData? icon;
  final bool glow;
  final bool compact;

  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = 'main',
    this.icon,
    this.glow = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    BoxDecoration deco;
    Color fg;
    FontWeight w;
    if (kind == 'g') {
      deco = BoxDecoration(color: const Color.fromRGBO(255, 255, 255, .07), borderRadius: radius);
      fg = kTx;
      w = FontWeight.w600;
    } else if (kind == 'r') {
      deco = BoxDecoration(color: const Color.fromRGBO(255, 90, 77, .18), borderRadius: radius);
      fg = kRed;
      w = FontWeight.w700;
    } else {
      deco = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [context.accent2, context.accent],
        ),
        borderRadius: radius,
        boxShadow: glow ? [BoxShadow(color: accentA(context, .6), blurRadius: 14)] : null,
      );
      fg = kDarkText;
      w = FontWeight.w800;
    }
    return Opacity(
      opacity: onPressed == null ? .5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: deco,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: compact ? 7 : 13, horizontal: compact ? 12 : 8),
              child: Row(
                mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: fg, fontWeight: w, fontSize: compact ? 13 : 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// قسم في الإعدادات: عنوان صغير بلون الواجهة ثم المحتوى
class Sec extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final CrossAxisAlignment align;

  const Sec({super.key, this.title, required this.children, this.align = CrossAxisAlignment.start});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color.fromRGBO(255, 190, 140, .1))),
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                title!,
                style: TextStyle(color: context.accent2, fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

List<Widget> _spaced(List<Widget> c, double g) {
  final out = <Widget>[];
  for (var i = 0; i < c.length; i++) {
    if (i > 0) out.add(SizedBox(height: g));
    out.add(c[i]);
  }
  return out;
}

/// نافذة تنزلق من الأسفل. الدالة تأخذ context النافذة نفسها لإغلاقها
Future<T?> showAppSheet<T>(BuildContext context, List<Widget> Function(BuildContext sheetCtx) build) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _spaced(build(ctx), 10),
          ),
        ),
      ),
    ),
  );
}


/// شارة «مطور» ثابتة: تدرج أزرق كهربائي إلى بنفسجي مع توهج خفيف، بدون أي حركة
class DevBadge extends StatelessWidget {
  const DevBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => const LinearGradient(
          colors: [Color(0xFF2EA8FF), Color(0xFF8A3DFF)],
        ).createShader(r),
        child: const Text(
          'مطور',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ),
    );
  }
}

/// علامة اللانهاية للإمبراطور: رسم برمجي (ليست إيموجي) تتدرج فيه كل الألوان
class InfinityMark extends StatefulWidget {
  final double size;
  const InfinityMark({super.key, this.size = 18});

  @override
  State<InfinityMark> createState() => _InfinityMarkState();
}

class _InfinityMarkState extends State<InfinityMark> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size * 1.9,
        height: widget.size,
        child: CustomPaint(painter: _InfPainter(c)),
      ),
    );
  }
}

class _InfPainter extends CustomPainter {
  final Animation<double> a;
  _InfPainter(this.a) : super(repaint: a);

  static const List<Color> _cols = [
    Color(0xFFFF3B3B),
    Color(0xFFFF9A1F),
    Color(0xFFFFE04A),
    Color(0xFF4CE07A),
    Color(0xFF2EC8FF),
    Color(0xFF6A5BFF),
    Color(0xFFD65BFF),
    Color(0xFFFF3B3B),
  ];

  @override
  void paint(Canvas cv, Size s) {
    final sw = s.height * .17;
    final kx = s.width / 2 - sw;
    final ky = (s.height / 2 - sw) / .35355;
    final path = Path();
    const n = 96;
    for (var i = 0; i <= n; i++) {
      final t = i / n * 2 * math.pi;
      final d = 1 + math.sin(t) * math.sin(t);
      final x = s.width / 2 + kx * math.cos(t) / d;
      final y = s.height / 2 + ky * math.sin(t) * math.cos(t) / d;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final shader = SweepGradient(colors: _cols, transform: GradientRotation(a.value * 2 * math.pi)).createShader(Offset.zero & s);
    cv.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw * 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5)
        ..shader = shader
        ..color = const Color(0x55FFFFFF),
    );
    cv.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _InfPainter old) => false;
}

/// بطاقة قسم بعنوان (للشاشة الرئيسية)
class SecCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SecCard({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentA(context, .55)),
        color: const Color.fromRGBO(0, 0, 0, .25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: accentA(context, .12),
            child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.accent2)),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// لون بشفافية معينة من نص hex
Color tint(String hex, double a) {
  final c = rgbOf(hex);
  return Color.fromRGBO(c[0], c[1], c[2], a);
}
