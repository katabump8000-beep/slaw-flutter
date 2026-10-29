import 'package:flutter/material.dart';

import 'sfx.dart';

/// يشغّل صوت نقر خفيفاً عند كل لمسة (نقرة وليس تمريراً)
class TapSound extends StatefulWidget {
  final Widget child;
  const TapSound({super.key, required this.child});
  @override
  State<TapSound> createState() => _TapSoundState();
}

class _TapSoundState extends State<TapSound> {
  Offset? _p;
  int _t = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _p = e.position;
        _t = DateTime.now().millisecondsSinceEpoch;
      },
      onPointerUp: (e) {
        final p = _p;
        if (p == null) return;
        _p = null;
        if ((e.position - p).distance < 14 && DateTime.now().millisecondsSinceEpoch - _t < 350) Sfx.click();
      },
      child: widget.child,
    );
  }
}
