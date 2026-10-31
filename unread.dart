import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'home.dart';

Future<int> groupTotal(String gid) async {
  var t = 0;
  try {
    final v = (await ref('stats/$gid').get()).value;
    if (v is Map) {
      for (final x in v.values) {
        if (x is num) t += x.toInt();
      }
    }
  } catch (_) {}
  return t;
}

/// يحفظ أن العضو قرأ كل رسائل القروب حتى الآن
Future<void> markGroupRead(String gid) async {
  try {
    prefs.setInt('tot_$gid', await groupTotal(gid));
  } catch (_) {}
}

/// عدد الرسائل غير المقروءة بجانب اسم النقابة
class UnreadBadge extends StatefulWidget {
  final String gid;
  const UnreadBadge({super.key, required this.gid});

  @override
  State<UnreadBadge> createState() => _UnreadState();
}

class _UnreadState extends State<UnreadBadge> {
  int n = 0;
  Timer? t;

  @override
  void initState() {
    super.initState();
    _tick();
    t = Timer.periodic(const Duration(seconds: 12), (_) => _tick());
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (groupKind(widget.gid) != 'main') return;
    final total = await groupTotal(widget.gid);
    final last = prefs.getInt('tot_${widget.gid}');
    var c = 0;
    if (last == null) {
      prefs.setInt('tot_${widget.gid}', total);
    } else {
      c = total > last ? total - last : 0;
    }
    if (mounted && c != n) setState(() => n = c);
  }

  @override
  Widget build(BuildContext context) {
    if (n <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsetsDirectional.only(start: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: context.accent, borderRadius: BorderRadius.circular(10)),
      child: Text(n > 99 ? '99+' : '$n', style: const TextStyle(color: kDarkText, fontWeight: FontWeight.w900, fontSize: 11.5)),
    );
  }
}
