import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

/// ملخص المتصدرين: كل مستخدم ينشر أرقامه (ضمن حدود القواعد)
class Board {
  static Future<void> sync() async {
    try {
      if (Session.isEmp || myUid.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - (prefs.getInt('board_ts') ?? 0) < 300000) return;
      prefs.setInt('board_ts', now);
      Future<int> n(String p) async {
        final v = (await ref(p).get()).value;
        return v is num ? v.toInt() : 0;
      }
      final b = await n('wallets/$myUid/bal');
      final l = await n('loss/$myUid');
      final a = await n('msgTotal/$myUid');
      await ref('board/$myUid').set(<String, Object?>{'b': b, 'l': l, 'a': a});
    } catch (_) {}
  }
}

class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المتصدرون'),
          bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'الأكثر ربحاً'), Tab(text: 'الأكثر خسارة'), Tab(text: 'الأفضل تفاعلاً')]),
        ),
        body: const TabBarView(children: [_BoardList('b', 'رصيد'), _BoardList('l', 'خسارة'), _BoardList('a', 'رسالة')]),
      ),
    );
  }
}

class _BoardList extends StatelessWidget {
  final String f;
  final String unit;
  const _BoardList(this.f, this.unit);

  Future<List<MapEntry<String, int>>> _load() async {
    final s = await ref('board').orderByChild(f).limitToLast(15).get();
    final v = s.value;
    final out = <MapEntry<String, int>>[];
    if (v is Map) {
      v.forEach((k, x) {
        if (x is Map && x[f] is num && (x[f] as num) > 0 && k.toString() != Session.emp) out.add(MapEntry(k.toString(), (x[f] as num).toInt()));
      });
    }
    out.sort((a, b) => b.value.compareTo(a.value));
    return out.take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MapEntry<String, int>>>(
      future: _load(),
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final l = s.data ?? <MapEntry<String, int>>[];
        if (l.isEmpty) return const Center(child: Text('لا توجد بيانات بعد', style: TextStyle(color: kMu)));
        const ring = [Color(0xFFFFD54A), Color(0xFFD7DEE8), Color(0xFFCD7F32)];
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: l.length,
          itemBuilder: (c, i) => Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: EdgeInsets.all(i < 3 ? 14 : 12),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(0, 0, 0, .28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: i < 3 ? ring[i].withAlpha(160) : kLine),
            ),
            child: Row(children: [
              SizedBox(width: 30, child: Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: i < 3 ? 22 : 17, fontWeight: FontWeight.w900, color: i < 3 ? ring[i] : kMu))),
              const SizedBox(width: 6),
              i < 3 ? _GlowRing(color: ring[i], child: UserAvatar(l[i].key, size: 54)) : UserAvatar(l[i].key, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: FutureBuilder<Prof>(
                  future: prof(l[i].key),
                  builder: (c, p) => Text(p.data?.name ?? '...', style: TextStyle(fontWeight: FontWeight.w800, fontSize: i < 3 ? 16 : 14.5)),
                ),
              ),
              Text('${fmtN(l[i].value)} $unit', style: TextStyle(fontWeight: FontWeight.w900, color: context.accent2)),
            ]),
          ),
        );
      },
    );
  }
}

/// إطار يشع حول صورة أصحاب المراكز الثلاثة الأولى (ذهبي / فضي / برونزي)
class _GlowRing extends StatefulWidget {
  final Color color;
  final Widget child;
  const _GlowRing({required this.color, required this.child});

  @override
  State<_GlowRing> createState() => _GlowRingState();
}

class _GlowRingState extends State<_GlowRing> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: c,
        builder: (_, child) => Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: widget.color, width: 2.5),
            boxShadow: [BoxShadow(color: widget.color.withAlpha(150), blurRadius: 8 + 12 * c.value, spreadRadius: 1 + 2 * c.value)],
          ),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
