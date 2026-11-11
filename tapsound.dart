import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sfx.dart';
import 'vip.dart';

/// يشغّل صوت نقر خفيفاً عند كل لمسة (نقرة وليس تمريراً)
class TapSound extends StatefulWidget {
  final Widget child;
  const TapSound({super.key, required this.child});
  @override
  State<TapSound> createState() => _TapSoundState();
}

class _TapSoundState extends State<TapSound> {
  Offset? _p;

  void _tap() {
    if (!vipOn.value) {
      Sfx.click();
      return;
    }
    final k = vipKind.value;
    final snd = k == 'thunder' ? 'zap${1 + math.Random().nextInt(3)}.wav' : (k.startsWith('royal') ? 'royal.wav' : (k == 'emerald' ? 'rose${1 + math.Random().nextInt(4)}.wav' : 'vip${1 + math.Random().nextInt(4)}.wav'));
    final vol = k == 'thunder' ? .4 : (k == 'emerald' ? .5 : (k.startsWith('royal') ? .6 : .9));
    Sfx.start(snd, volume: vol).then((p) {
      p.onPlayerComplete.first.timeout(const Duration(seconds: 3), onTimeout: () {}).then((_) => p.dispose());
    });
  }
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
        if ((e.position - p).distance < 14 && DateTime.now().millisecondsSinceEpoch - _t < 350) _tap();
      },
      child: widget.child,
    );
  }
}
