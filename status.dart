import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// نسبة البطارية وقوة الاتصال: أخضر جيد / أصفر متوسط / أحمر ضعيف
class StatusBadge extends StatefulWidget {
  const StatusBadge({super.key});

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge> {
  int bat = -1;
  int ms = -1;
  Timer? t;

  @override
  void initState() {
    super.initState();
    _tick();
    t = Timer.periodic(const Duration(seconds: 25), (_) => _tick());
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    var b = bat;
    var m = ms;
    try {
      b = await Battery().batteryLevel;
    } catch (_) {}
    try {
      final sw = Stopwatch()..start();
      await http.get(Uri.parse('https://www.gstatic.com/generate_204')).timeout(const Duration(seconds: 4));
      m = sw.elapsedMilliseconds;
    } catch (_) {
      m = -2;
    }
    if (mounted) {
      setState(() {
        bat = b;
        ms = m;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const g = Color(0xFF2EE07A), y = Color(0xFFFFD83B), r = Color(0xFFFF4D4D);
    final bc = bat < 0 ? Colors.white38 : (bat >= 50 ? g : (bat >= 20 ? y : r));
    final nc = ms == -1 ? Colors.white38 : (ms < 0 ? r : (ms < 450 ? g : (ms < 1300 ? y : r)));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(bat >= 0 && bat < 20 ? Icons.battery_alert : Icons.battery_full, size: 15, color: bc),
      const SizedBox(width: 2),
      Text(bat < 0 ? '--' : '$bat%', style: TextStyle(fontSize: 11, color: bc, fontWeight: FontWeight.w800)),
      const SizedBox(width: 8),
      Icon(ms == -2 ? Icons.signal_wifi_off : Icons.network_check, size: 15, color: nc),
    ]);
  }
}
