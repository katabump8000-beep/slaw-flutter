import 'servertime.dart';
import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'bets.dart';
import 'core.dart';
import 'data.dart';
import 'widgets.dart';

const int _cool = 82800000; // 23 ساعة

int giftPrize(int n) => n >= 30 ? 1500 : n * 30;

/// صندوق الهدية المشع في الواجهة الرئيسية
class GiftBox extends StatefulWidget {
  const GiftBox({super.key});

  @override
  State<GiftBox> createState() => _GiftBoxState();
}

class _GiftBoxState extends State<GiftBox> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  bool ready = false;

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
      final v = (await ref('gift/$myUid').get()).value;
      var r = true;
      if (v is Map && v['ts'] is num) r = nowMs() - (v['ts'] as num).toInt() >= _cool;
      if (mounted) setState(() => ready = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GiftScreen()));
        _check();
      },
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: c,
          builder: (_, __) => Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(colors: [Color(0xFFFFE680), Color(0xFFFF9A1F)]),
                boxShadow: [BoxShadow(color: const Color(0xFFFFB000).withAlpha(ready ? 170 : 70), blurRadius: 10 + 16 * c.value, spreadRadius: 1 + 4 * c.value)],
              ),
              child: const Text('🎁', style: TextStyle(fontSize: 32)),
            ),
            if (ready) Positioned(top: 2, right: 2, child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: Color(0xFFFF3B3B), shape: BoxShape.circle))),
          ]),
        ),
      ),
    );
  }
}

class GiftScreen extends StatefulWidget {
  const GiftScreen({super.key});

  @override
  State<GiftScreen> createState() => _GiftScreenState();
}

class _GiftScreenState extends State<GiftScreen> {
  int n = 0;
  int ts = 0;
  bool busy = false;
  bool loaded = false;
  Timer? t;

  @override
  void initState() {
    super.initState();
    _load();
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = (await ref('gift/$myUid').get()).value;
      if (v is Map) {
        n = (v['n'] as num?)?.toInt() ?? 0;
        ts = (v['ts'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    if (mounted) setState(() => loaded = true);
  }

  int get left => ts == 0 ? 0 : (ts + _cool) - nowMs();

  String _fmt(int ms) {
    final s = (ms / 1000).ceil();
    String p(int x) => x.toString().padLeft(2, '0');
    return '${p(s ~/ 3600)}:${p((s % 3600) ~/ 60)}:${p(s % 60)}';
  }

  /// الاستلام يتم على السيرفر بالكامل (الوقت + الجائزة + الرصيد): التطبيق يرسل طلباً ثم يعرض النتيجة
  Future<void> _claim() async {
    if (busy || left > 0) return;
    setState(() => busy = true);
    final rid = ref('giftReq').push().key!;
    final done = Completer<Map<dynamic, dynamic>>();
    final sub = ref('giftRes/$myUid').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is Map && v['id'] == rid && !done.isCompleted) done.complete(v);
    }, onError: (_) {});
    Map<dynamic, dynamic>? res;
    String why = '';
    try {
      await ref('giftReq/$rid').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp}).timeout(const Duration(seconds: 8));
    } catch (e) {
      why = e.toString().toLowerCase().contains('permission') ? 'rules' : 'net';
    }
    if (why.isEmpty) {
      try {
        res = await done.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        res = null;
      }
    }
    await sub.cancel();
    if (res == null) {
      toast(why == 'rules' ? 'قواعد قاعدة البيانات لم تُحدَّث بعد (giftReq) — انشر ملف القواعد في Firebase' : why == 'net' ? 'لا يوجد اتصال بالإنترنت' : 'سيرفر المنصة لا يستجيب الآن (قد يكون نائماً)، حاول بعد دقيقة. إن وصل طلبك ستُضاف جائزتك تلقائياً', bad: true);
    } else if (res['err'] != null) {
      toast(res['err'] == 'off' ? 'عذراً قام أحد المطورين بإيقاف هذه!' : 'لا يمكنك استلام الهدية الآن', bad: true);
    } else if (res['elite'] == true) {
      toast('🏅 حصلت على لقب نخبة و 1500 رصيد!');
    } else {
      toast('🎁 حصلت على ${(res['prize'] as num?)?.toInt() ?? 0} رصيد');
    }
    await _load();
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final next = n >= 30 ? 1 : n + 1;
    final can = loaded && left <= 0;
    return Scaffold(
      appBar: AppBar(title: const Text('🎁 هدية يومية')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎁', style: TextStyle(fontSize: 90)),
            const SizedBox(height: 10),
            Text('اليوم $next من 30', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('جائزة اليوم: ${fmtN(giftPrize(next))} رصيد${next == 30 ? ' + لقب نخبة 🏅' : ''}', style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('كل يوم تزيد الجائزة 30 حتى اليوم 30 وجائزته 1500', textAlign: TextAlign.center, style: TextStyle(color: kMu, fontSize: 12.5)),
            const SizedBox(height: 22),
            if (loaded && left > 0)
              Column(children: [
                const Text('الهدية القادمة بعد', style: TextStyle(color: kMu)),
                const SizedBox(height: 4),
                Text(_fmt(left), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 2)),
              ])
            else
              SizedBox(width: 220, child: AppButton(busy ? '...' : 'استلم هديتك 🎁', glow: true, onPressed: can && !busy ? _claim : null)),
            const SizedBox(height: 20),
            Text('استلمت $n من 30', style: const TextStyle(color: kMu)),
          ]),
        ),
      ),
    );
  }
}
