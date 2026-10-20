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

/// وسم عمر العضو في التطبيق
Widget ageTag(Prof p) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final ts = p.ts == 0 ? now : p.ts;
  final d = (now - ts) / 86400000;
  String t;
  String c;
  if (d < 3) {
    t = 'جديد';
    c = '#5de0e6';
  } else if (d < 30) {
    t = 'عضو';
    c = '#6ee787';
  } else if (d < 90) {
    t = 'قديم';
    c = '#ffb04a';
  } else {
    t = 'أسطورة';
    c = '#ff7eb6';
  }
  final rgb = rgbOf(c);
  return Tag(
    t,
    fg: hexColor(c),
    bg: Color.fromRGBO(rgb[0], rgb[1], rgb[2], .13),
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
