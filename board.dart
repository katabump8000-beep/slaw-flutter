import 'servertime.dart';
import 'dart:async';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'home.dart' show groupsCache, groupName;
import 'profile.dart' show viewProfile;
import 'widgets.dart';

/// ملخص المتصدرين: كل مستخدم ينشر أرقامه (ضمن حدود القواعد)
class Board {
  static Future<void> sync() async {
    try {
      if (Session.isEmp || myUid.isEmpty) return;
      final now = nowMs();
      Future<int> n(String p) async {
        final v = (await ref(p).get()).value;
        return v is num ? v.toInt() : 0;
      }
      // تصفير المتصدرين: نسجّل أرقام هذا الجهاز كنقطة بداية جديدة عند صدور أمر تصفير أحدث
      final rs = (await ref('boardReset').get()).value;
      var fresh = false;
      if (rs is Map) {
        final rts = (rs['ts'] as num?)?.toInt() ?? 0;
        if (rts > (prefs.getInt('br_ts') ?? 0)) {
          fresh = true;
          prefs.setInt('br_ts', rts);
          prefs.setInt('br_b', Session.isDev ? 0 : await n('wallets/$myUid/bal'));
          prefs.setInt('br_l', Session.isDev ? 0 : await n('loss/$myUid'));
          if (rs['a'] == true) prefs.setInt('br_a', await n('msgTotal/$myUid'));
        }
      }
      if (!fresh && now - (prefs.getInt('board_ts') ?? 0) < 25000) return;
      prefs.setInt('board_ts', now);
      // المطورون لا يدخلون قوائم الربح والخسارة، فقط التفاعل
      final b = Session.isDev ? 0 : max(0, await n('wallets/$myUid/bal') - (prefs.getInt('br_b') ?? 0));
      final l = Session.isDev ? 0 : max(0, await n('loss/$myUid') - (prefs.getInt('br_l') ?? 0));
      final a = max(0, await n('msgTotal/$myUid') - (prefs.getInt('br_a') ?? 0));
      await ref('board/$myUid').set(<String, Object?>{'b': b, 'l': l, 'a': a});
    } catch (_) {}
  }
}

class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المتصدرون'),
          bottom: const TabBar(isScrollable: true, tabs: [Tab(text: 'الأكثر ربحاً'), Tab(text: 'الأكثر خسارة'), Tab(text: 'الأفضل تفاعلاً'), Tab(text: 'النقابات')]),
        ),
        body: const TabBarView(children: [_BoardList('b', 'رصيد'), _BoardList('l', 'خسارة'), _BoardList('a', 'رسالة'), _GuildBoard()]),
      ),
    );
  }
}

class _BoardList extends StatefulWidget {
  final String f;
  final String unit;
  const _BoardList(this.f, this.unit);

  @override
  State<_BoardList> createState() => _BoardListState();
}

class _BoardListState extends State<_BoardList> {
  List<MapEntry<String, int>>? data;
  StreamSubscription<DatabaseEvent>? sub;
  int _gen = 0;

  String get f => widget.f;
  String get unit => widget.unit;

  @override
  void initState() {
    super.initState();
    // تحديث مباشر: أي تغيير في الأرقام يظهر فوراً دون إعادة فتح الصفحة
    sub = ref('board').orderByChild(f).limitToLast(f == 'a' ? 15 : 60).onValue.listen((e) async {
      final g = ++_gen;
      final l = await _process(e.snapshot.value);
      if (mounted && g == _gen) setState(() => data = l);
    }, onError: (_) {
      if (mounted && data == null) setState(() => data = <MapEntry<String, int>>[]);
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<List<MapEntry<String, int>>> _process(Object? v) async {
    final out = <MapEntry<String, int>>[];
    if (v is Map) {
      v.forEach((k, x) {
        if (x is Map && x[f] is num && (x[f] as num) > 0 && k.toString() != Session.emp) out.add(MapEntry(k.toString(), (x[f] as num).toInt()));
      });
    }
    out.sort((a, b) => b.value.compareTo(a.value));
    if (f != 'a') {
      final keep = <MapEntry<String, int>>[];
      for (final e in out) {
        if (await roleOf(e.key) == null) keep.add(e);
        if (keep.length >= 10) break;
      }
      return keep;
    }
    return out.take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = data;
    if (l == null) return const Center(child: CircularProgressIndicator());
    if (l.isEmpty) return const Center(child: Text('لا توجد بيانات بعد', style: TextStyle(color: kMu)));
        const ring = [Color(0xFFFFD54A), Color(0xFFD7DEE8), Color(0xFFCD7F32)];
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: l.length,
          itemBuilder: (c, i) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => viewProfile(context, l[i].key),
            child: Container(
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
          ),
        );
  }
}

/// ترتيب النقابات (أول 20): القوة = عدد الأعضاء + التفاعل (يحدّثها سيرفر الإشعارات كل دقيقة)
class _GuildBoard extends StatelessWidget {
  const _GuildBoard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('guildBoard').onValue,
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final v = s.data!.snapshot.value;
        final rows = <MapEntry<String, Map<dynamic, dynamic>>>[];
        if (v is Map) {
          v.forEach((k, x) {
            if (x is Map && groupsCache.containsKey(k.toString())) rows.add(MapEntry(k.toString(), x));
          });
        }
        int score(Map<dynamic, dynamic> x) => ((x['n'] as num?)?.toInt() ?? 0) * 100 + ((x['m'] as num?)?.toInt() ?? 0);
        rows.sort((a, b) => score(b.value).compareTo(score(a.value)));
        final top = rows.take(20).toList();
        if (top.isEmpty) return const Center(child: Text('لا توجد بيانات بعد', style: TextStyle(color: kMu)));
        const ring = [Color(0xFFFFD54A), Color(0xFFD7DEE8), Color(0xFFCD7F32)];
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: top.length,
          itemBuilder: (c, i) {
            final x = top[i].value;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(0, 0, 0, .28),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: i < 3 ? ring[i].withAlpha(160) : kLine),
              ),
              child: Row(children: [
                SizedBox(width: 30, child: Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: i < 3 ? 22 : 17, fontWeight: FontWeight.w900, color: i < 3 ? ring[i] : kMu))),
                const SizedBox(width: 8),
                Expanded(child: Text(groupName(top[i].key), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: i < 3 ? 16 : 14.5))),
                Text('👥 ${fmtN((x['n'] as num?) ?? 0)}   💬 ${fmtN((x['m'] as num?) ?? 0)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: context.accent2)),
              ]),
            );
          },
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
