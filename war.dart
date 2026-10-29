import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'core.dart';
import 'data.dart';
import 'home.dart';
import 'sfx.dart';
import 'widgets.dart';

const Color _red = Color(0xFFFF3B3B);
const Color _yellow = Color(0xFFFFD21F);
const Color _blue = Color(0xFF2E8BFF);

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

List<List<String>> _roster(dynamic raw, String key) {
  try {
    final m = raw is String ? jsonDecode(raw) : raw;
    final l = (m as Map)[key];
    if (l is List) return l.map<List<String>>((e) => [(e as List)[0].toString(), e[1].toString()]).toList();
  } catch (_) {}
  return <List<String>>[];
}

/// مراقب الحروب: العروض العامة + الإشعاع + أصوات الترقية
class WarWatcher {
  static final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  static final ValueNotifier<Color?> glow = ValueNotifier<Color?>(null);
  static final Map<String, Map<String, dynamic>> feeds = {};
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static StreamSubscription<DatabaseEvent>? _a, _c, _r;
  static final List<StreamSubscription<DatabaseEvent>> _sfx = [];
  static Timer? _glowT;
  static bool showing = false;
  static String _uid = '';

  static void start() {
    if (myUid.isEmpty || (_uid == myUid && _a != null)) return;
    stop();
    _uid = myUid;
    final q = ref('warFeed').orderByKey().limitToLast(6);
    void put(DatabaseEvent e) {
      final k = e.snapshot.key;
      final v = e.snapshot.value;
      if (k == null || v is! Map) return;
      feeds[k] = Map<String, dynamic>.from(v);
      tick.value++;
      _eval();
    }
    _a = q.onChildAdded.listen(put, onError: (_) {});
    _c = q.onChildChanged.listen(put, onError: (_) {});
    _r = q.onChildRemoved.listen((e) {
      feeds.remove(e.snapshot.key);
      tick.value++;
    }, onError: (_) {});
    _glowT = Timer.periodic(const Duration(seconds: 9), (_) => _pulse());
    for (final g in mainGroups()) {
      _sfx.add(ref('warSfx/$g').onValue.listen((e) {
        final v = e.snapshot.value;
        if (v is! Map) return;
        final ts = (v['ts'] as num?)?.toInt() ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if ((v['by'] ?? '') == myUid || (now - ts).abs() > 9000) return;
        if (prefs.getInt('sfx_$g') == ts) return;
        prefs.setInt('sfx_$g', ts);
        Sfx.playWait(v['t'] == 'atk' ? 'hjom.mp3' : 'defa.mp3');
      }, onError: (_) {}));
    }
  }

  static void stop() {
    _a?.cancel();
    _c?.cancel();
    _r?.cancel();
    _a = _c = _r = null;
    for (final s in _sfx) {
      s.cancel();
    }
    _sfx.clear();
    _glowT?.cancel();
    feeds.clear();
    _uid = '';
  }

  static void _pulse() {
    final now = DateTime.now().millisecondsSinceEpoch;
    Color? c;
    for (final f in feeds.values) {
      if (f['res'] != null) continue;
      final st = (f['st'] as num?)?.toInt() ?? 0;
      if (now >= st + 120000) continue;
      if (memCache[(f['dg'] ?? '').toString()] == true) c = _red;
      if (memCache[(f['ag'] ?? '').toString()] == true) c = _blue;
    }
    if (c == null || Session.isEmp) return;
    glow.value = c;
    Future<void>.delayed(const Duration(milliseconds: 1800), () => glow.value = null);
  }

  static final List<Future<void> Function()> _queue = [];

  static void _eval() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in feeds.entries) {
      final wid = e.key;
      final f = e.value;
      final ts = (f['ts'] as num?)?.toInt() ?? 0;
      if (ts > 0 && now - ts < 90000 && !(prefs.getBool('war_in_$wid') ?? false)) {
        prefs.setBool('war_in_$wid', true);
        _queue.add(() => _show(WarIntroScreen(f: f)));
      }
      final rs = (f['rs'] as num?)?.toInt() ?? 0;
      if (f['res'] != null && rs > 0 && now - rs < 20 * 60000 && !(prefs.getBool('war_ep_$wid') ?? false)) {
        prefs.setBool('war_ep_$wid', true);
        _queue.add(() => _show(WarEpicScreen(f: f)));
      }
    }
    _drain();
  }

  static Future<void> _drain() async {
    if (showing) return;
    showing = true;
    while (_queue.isNotEmpty) {
      final j = _queue.removeAt(0);
      await j();
    }
    showing = false;
  }

  static Future<void> _show(Widget w) async {
    final n = navKey.currentState;
    if (n == null) return;
    await n.push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => w,
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
    ));
  }
}

/// طبقة الإشعاع على حواف الشاشة (أحمر للمدافعين، أزرق للمهاجمين)
class EdgeGlow extends StatelessWidget {
  const EdgeGlow({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<Color?>(
        valueListenable: WarWatcher.glow,
        builder: (c, col, _) => AnimatedOpacity(
          opacity: col == null ? 0 : 1,
          duration: const Duration(milliseconds: 450),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: (col ?? Colors.transparent).withAlpha(38), width: 2),
              boxShadow: [BoxShadow(color: (col ?? Colors.transparent).withAlpha(26), blurRadius: 16, spreadRadius: -8)],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- إعلان حرب ----------
Future<void> declareWarSheet(BuildContext context) async {
  final att = <String>[];
  for (final g in groupsCache.keys) {
    if (groupKind(g) != 'main') continue;
    if (Session.isDev) {
      att.add(g);
    } else if (memCache[g] == true) {
      try {
        final a = await ref('groupAdmins/$g/$myUid').get();
        if (a.exists) att.add(g);
      } catch (_) {}
    }
  }
  if (att.isEmpty) {
    toast('للمشرفين فقط', bad: true);
    return;
  }
  if (!context.mounted) return;
  void pickTarget(String a) {
    final others = groupsCache.keys.where((g) => groupKind(g) == 'main' && g != a).toList();
    showAppSheet<void>(context, (sc) => [
          const Text('⚔️ اختر النقابة المستهدفة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ...others.map((g) => AppButton(groupName(g), kind: 'g', onPressed: () async {
                Navigator.of(sc).pop();
                await _declare(a, g);
              })),
        ]);
  }
  if (att.length == 1) {
    pickTarget(att.first);
  } else {
    showAppSheet<void>(context, (sc) => [
          const Text('من أي نقابة تعلن الحرب؟', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ...att.map((g) => AppButton(groupName(g), kind: 'g', onPressed: () {
                Navigator.of(sc).pop();
                pickTarget(g);
              })),
        ]);
  }
}

Future<void> _declare(String a, String d) async {
  try {
    if ((await balanceNow()) < 10000) {
      toast('رصيدك لا يكفي (10,000)', bad: true);
      return;
    }
    final wid = ref('wars').push().key!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final st = now + 3600000 + 30000;
    await db.ref().update(<String, Object?>{
      'wars/$wid': <String, Object?>{'a': a, 'd': d, 'by': myUid, 't0': now, 'st': st, 'en': st, 's': 'p'},
      'activeWar/$a': wid,
      'activeWar/$d': wid,
      'wallets/$myUid/bal': ServerValue.increment(-10000),
      'warFeed/$wid': <String, Object?>{
        'ag': a, 'dg': d, 'an': groupName(a), 'dn': groupName(d), 'by': myUid, 'bn': Session.me.name,
        'st': st, 'ts': ServerValue.timestamp,
      },
    });
    await feedNote('news', '⚔️ إعلان حرب: نقابة ${groupName(a)} تعلن الحرب على ${groupName(d)}', k: 'war',
        d: jsonEncode({'t': 'decl', 'a': groupName(a), 'd': groupName(d), 'by': Session.me.name, 'st': st}));
    toast('تم إعلان الحرب، تبدأ بعد ساعة ⚔️');
  } catch (e) {
    err(e);
  }
}

Future<void> cancelWar(String wid) async {
  try {
    final f = WarWatcher.feeds[wid];
    final a = (f?['ag'] ?? '').toString(), d = (f?['dg'] ?? '').toString();
    await db.ref().update(<String, Object?>{
      'wars/$wid': null,
      'activeWar/$a': null,
      'activeWar/$d': null,
      'warFeed/$wid': null,
    });
    toast('تم إلغاء الحرب');
  } catch (e) {
    err(e);
  }
}

/// شريط «إلغاء الحرب» لمن أعلنها (يظهر في الصحيفة)
class WarCancelBar extends StatelessWidget {
  const WarCancelBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: WarWatcher.tick,
      builder: (c, _, __) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final mine = WarWatcher.feeds.entries.where((e) => e.value['by'] == myUid && e.value['res'] == null && ((e.value['st'] as num?)?.toInt() ?? 0) > now).toList();
        if (mine.isEmpty) return const SizedBox();
        return Column(
          children: [
            for (final e in mine)
              Container(
                color: const Color(0xFF4A0A0A),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  Expanded(child: Text('حربك على «${e.value['dn']}» معلنة', style: const TextStyle(fontSize: 13))),
                  SizedBox(width: 120, child: AppButton('إلغاء الحرب', kind: 'r', compact: true, onPressed: () => cancelWar(e.key))),
                ]),
              ),
          ],
        );
      },
    );
  }
}

// ---------- لوحة النقابة: المستويات والترقية ----------
class GuildPanel extends StatefulWidget {
  final String gid;
  const GuildPanel({super.key, required this.gid});

  @override
  State<GuildPanel> createState() => _GuildPanelState();
}

class _GuildPanelState extends State<GuildPanel> {
  Map<String, dynamic>? gs;
  int cards = 0;
  int mine = 0;
  int cool = 0;
  Timer? _t;
  String warLine = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await ref('guildStats/${widget.gid}').get();
      gs = s.value is Map ? Map<String, dynamic>.from(s.value as Map) : null;
      final c = await ref('inv/$myUid/upg').get();
      cards = c.value is num ? (c.value as num).toInt() : 0;
      final con = gs?['contrib'];
      mine = con is Map && con[myUid] is num ? (con[myUid] as num).toInt() : 0;
      final aw = await ref('activeWar/${widget.gid}').get();
      if (aw.exists) {
        final f = WarWatcher.feeds[aw.value.toString()];
        if (f != null) {
          final at = f['ag'] == widget.gid;
          warLine = at ? '⚔️ تشنون حرباً على «${f['dn']}»' : '🚨 تتعرضون لهجوم من «${f['an']}»';
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _up(String k) async {
    if (cool > 0) return;
    if (cards <= 0) {
      toast('لا تملك بطاقة ترقية، اشترِ من المتجر', bad: true);
      return;
    }
    setState(() => cool = 5);
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => cool = max(0, cool - 1));
      if (cool == 0) t.cancel();
    });
    try {
      await db.ref().update(<String, Object?>{
        'guildStats/${widget.gid}/$k': ServerValue.increment(1),
        'inv/$myUid/upg': ServerValue.increment(-1),
        'guildStats/${widget.gid}/contrib/$myUid': ServerValue.increment(1),
      });
      ref('warSfx/${widget.gid}').set(<String, Object?>{'t': k, 'by': myUid, 'ts': ServerValue.timestamp});
      Sfx.chain([k == 'atk' ? 'hjom.mp3' : 'defa.mp3', 'tarkya.mp3']);
      await feedNote('shop', '🎫 ${Session.me.name} رقّى ${k == 'atk' ? 'هجوم' : 'دفاع'} نقابة ${groupName(widget.gid)}', k: 'buy');
      await _load();
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = gs;
    if (g == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          const Text('لم تُفعَّل المستويات لهذه النقابة بعد.', style: TextStyle(color: kMu)),
          if (Session.isDev)
            AppButton('تفعيل المستويات', kind: 'g', onPressed: () async {
              await ref('guildStats/${widget.gid}').set(<String, Object?>{'atk': 1, 'def': 1});
              _load();
            }),
        ]),
      );
    }
    final lock = cool > 0;
    Widget btn(String k, String label) => Expanded(
          child: AppButton(lock ? '⏱ $cool' : label, onPressed: lock ? null : () => _up(k)),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: accentA(context, .5)), color: accentA(context, .07)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('⚔️ المستويات والحرب', style: TextStyle(fontWeight: FontWeight.w800, color: context.accent2)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _lv('⚔️ الهجوم', '${g['atk']}')),
          const SizedBox(width: 10),
          Expanded(child: _lv('🛡 الدفاع', '${g['def']}')),
        ]),
        const SizedBox(height: 8),
        Text('🎫 بطاقاتك: $cards  •  مساهماتك: $mine', style: const TextStyle(color: kMu)),
        const SizedBox(height: 8),
        Row(children: [btn('atk', '⬆️ ترقية الهجوم'), const SizedBox(width: 10), btn('def', '⬆️ ترقية الدفاع')]),
        if (lock)
          const Padding(padding: EdgeInsets.only(top: 6), child: Center(child: Icon(Icons.access_time, size: 18, color: kMu))),
        if (warLine.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(warLine, style: const TextStyle(color: _red, fontWeight: FontWeight.w800))),
      ]),
    );
  }

  Widget _lv(String t, String v) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .3), borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine)),
        child: Column(children: [Text(t), Text(v, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: context.accent2))]),
      );
}

// ---------- بطاقة إعلان الحرب في الصحيفة (مع عدّاد) ----------
class WarCard extends StatefulWidget {
  final Map<String, dynamic> o;
  const WarCard({super.key, required this.o});

  @override
  State<WarCard> createState() => _WarCardState();
}

class _WarCardState extends State<WarCard> {
  Timer? t;

  @override
  void initState() {
    super.initState();
    if (widget.o['t'] == 'decl') t = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  String _mmss(int ms) {
    final s = max(0, ms ~/ 1000);
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    return '${h > 0 ? '$h:' : ''}${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    final decl = o['t'] == 'decl';
    final left = ((o['st'] as num?)?.toInt() ?? 0) - DateTime.now().millisecondsSinceEpoch;
    if (decl && left < -120000) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
        child: Text('⚔️ انتهت حرب «${o['a']}» و«${o['d']}»', textAlign: TextAlign.center, style: const TextStyle(color: kMu, fontSize: 12.5)),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _red),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A0A0A), Color(0xFF120404)]),
      ),
      child: Column(children: [
        const Text('🗡️⚔️🗡️', style: TextStyle(fontSize: 26)),
        Text(decl ? 'إعلان حرب' : 'انتهت الحرب', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 4),
        if (decl) ...[
          Text('نقابة «${o['a']}»  ⚔️  نقابة «${o['d']}»', textAlign: TextAlign.center, style: const TextStyle(height: 1.7)),
          Text('بقيادة ${o['by']}', style: const TextStyle(color: kMu, fontSize: 12)),
          const SizedBox(height: 6),
          Text(left > 0 ? '⏱ تبدأ المعركة بعد ${_mmss(left)}' : '🔥 بدأت المعركة', style: const TextStyle(color: _yellow, fontWeight: FontWeight.w800)),
        ] else ...[
          Text('انتصرت نقابة «${o['win']}» 👑', style: const TextStyle(height: 1.7)),
          if ((o['lose'] ?? '').toString().isNotEmpty) Text('تم الغزو: «${o['lose']}»', style: const TextStyle(color: _red)),
          if ((o['lead'] ?? '').toString().isNotEmpty) Text('القائد: ${o['lead']}', style: const TextStyle(color: kMu, fontSize: 12)),
        ],
      ]),
    );
  }
}

// ---------- عرض إعلان الحرب (7 ثوانٍ) ----------
class WarIntroScreen extends StatefulWidget {
  final Map<String, dynamic> f;
  const WarIntroScreen({super.key, required this.f});

  @override
  State<WarIntroScreen> createState() => _WarIntroState();
}

class _WarIntroState extends State<WarIntroScreen> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 7));
  List<String> adA = [];
  List<String> adD = [];

  @override
  void initState() {
    super.initState();
    Sfx.block('show');
    Sfx.playWait('fire.mp3');
    c.forward();
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) Navigator.of(context).pop();
    });
    _admins();
  }

  Future<void> _admins() async {
    Future<List<String>> a(String g) async {
      try {
        final s = await ref('groupAdmins/$g').get();
        return s.value is Map ? (s.value as Map).keys.map((e) => e.toString()).take(3).toList() : <String>[];
      } catch (_) {
        return <String>[];
      }
    }
    final x = await a((widget.f['ag'] ?? '').toString());
    final y = await a((widget.f['dg'] ?? '').toString());
    if (mounted) setState(() {
      adA = x;
      adD = y;
    });
  }

  @override
  void dispose() {
    c.dispose();
    Sfx.unblock('show');
    super.dispose();
  }

  Widget _card(double p, bool atk, String g, String name, List<String> admins, String leader) {
    final shake = sin(p * 40) * 8 * (1 - p);
    return Opacity(
      opacity: p.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset((atk ? -1 : 1) * (1 - p) * 260 + shake, 0),
        child: Transform.scale(
          scale: 1 + (1 - p) * .8,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: atk ? _yellow : _red, width: 4), boxShadow: [BoxShadow(color: (atk ? _yellow : _red).withAlpha(160), blurRadius: 22)]),
              child: GroupPhoto(g, size: 110),
            ),
            const SizedBox(height: 8),
            Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900), maxLines: 2),
            Text(atk ? 'المهاجم' : 'المدافع', style: TextStyle(color: atk ? _yellow : _red, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              if (atk) UserAvatar(widget.f['by']?.toString() ?? '', size: 38),
              ...admins.where((u) => u != widget.f['by']).map((u) => UserAvatar(u, size: 38)),
            ]),
            if (atk) Text(leader, style: const TextStyle(fontSize: 12, color: kMu)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    return PopScope(
      canPop: false,
      child: AbsorbPointer(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: AnimatedBuilder(
            animation: c,
            builder: (_, __) {
              final t = c.value * 7;
              final fire = 1 - _seg(t, 0, 1.2);
              final out = _seg(t, 6.2, 7);
              return Opacity(
                opacity: 1 - out * .9,
                child: Stack(fit: StackFit.expand, children: [
                  Container(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment.center, radius: 1.1, colors: [Color.lerp(const Color(0xFF3A0500), const Color(0xFFFF6A00), fire)!, Colors.black]))),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Center(
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        Flexible(child: _card(_seg(t, 1.0, 2.2), true, (f['ag'] ?? '').toString(), (f['an'] ?? '').toString(), adA, (f['bn'] ?? '').toString())),
                        Transform.scale(scale: 0.6 + _seg(t, 2.6, 3.2) * .8, child: Opacity(opacity: _seg(t, 2.6, 3.2), child: const Text('VS', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white)))),
                        Flexible(child: _card(_seg(t, 2.2, 3.4), false, (f['dg'] ?? '').toString(), (f['dn'] ?? '').toString(), adD, '')),
                      ]),
                    ),
                  ),
                  Positioned(
                    bottom: 60,
                    left: 0,
                    right: 0,
                    child: Opacity(
                      opacity: _seg(t, 3.6, 4.2),
                      child: const Text('🔥 أُعلنت الحرب! 🔥', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFFFD54A))),
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------- العرض الأسطوري عند بدء الحرب (atta.mp3) ----------
class WarEpicScreen extends StatefulWidget {
  final Map<String, dynamic> f;
  const WarEpicScreen({super.key, required this.f});

  @override
  State<WarEpicScreen> createState() => _WarEpicState();
}

class _WarEpicState extends State<WarEpicScreen> with SingleTickerProviderStateMixin {
  AudioPlayer? ap;
  late final AnimationController ac = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  final Stopwatch sw = Stopwatch()..start();
  double endT = 53;
  bool audioDone = false;
  int phase = 0; // 0 عرض، 1 نتيجة
  int resStep = 0;
  final ScrollController scA = ScrollController();
  final ScrollController scD = ScrollController();
  late final List<List<String>> admA, memA, admD, memD, roy;
  bool royalShown = false;
  double passPx = 0;

  Map<String, dynamic> get f => widget.f;
  bool get attackWon => f['res'] == 'a';

  @override
  void initState() {
    super.initState();
    Sfx.block('show');
    admA = _roster(f['rA'], 'adm');
    memA = _roster(f['rA'], 'mem');
    admD = _roster(f['rD'], 'adm');
    memD = _roster(f['rD'], 'mem');
    roy = _roster(f['rA'], 'roy');
    _audio();
    ac.addListener(_frame);
  }

  Future<void> _audio() async {
    try {
      final p = await Sfx.start('atta.mp3');
      ap = p;
      p.onDurationChanged.listen((d) {
        final s = d.inMilliseconds / 1000;
        if (s > 8) endT = min(53, s);
      });
      p.onPlayerComplete.listen((_) => audioDone = true);
    } catch (_) {
      audioDone = false;
    }
  }

  double get t => sw.elapsedMilliseconds / 1000;

  void _frame() {
    if (!mounted || phase != 0) return;
    final tt = t;
    // نزول الأسماء: يبدأ بعد عرض النقابتين
    if (tt > 6) {
      for (final s in [scA, scD]) {
        if (s.hasClients) s.jumpTo(s.offset + 1.1);
      }
      passPx += 1.1;
      if (!royalShown && passPx > 54.0 * (max(memA.length + admA.length, memD.length + admD.length) + 3)) {
        royalShown = true;
      }
    }
    // خفض تدريجي للموسيقى في آخر 3 ثوانٍ
    if (tt > endT - 3) {
      final v = ((endT - tt) / 3).clamp(0.0, 1.0);
      ap?.setVolume(v);
    }
    if (tt >= endT || (audioDone && tt > 8)) {
      phase = 1;
      ap?.stop();
      _result();
    }
    setState(() {});
  }

  Future<void> _result() async {
    ac.stop();
    for (var i = 1; i <= 3; i++) {
      await Future<void>.delayed(Duration(milliseconds: i == 1 ? 600 : (i == 2 ? 3200 : 6200)));
      if (!mounted) return;
      setState(() => resStep = i);
    }
    await Future<void>.delayed(const Duration(seconds: 5));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    ac.dispose();
    ap?.dispose();
    scA.dispose();
    scD.dispose();
    Sfx.unblock('show');
    super.dispose();
  }

  Widget _rect(List<String> e, bool admin) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: admin ? const Color(0xFF3A0808) : const Color(0xFF0B1B3A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: admin ? _red : const Color(0xFF4DA3FF), width: 1.6),
          boxShadow: admin ? [BoxShadow(color: _red.withAlpha(150), blurRadius: 12)] : null,
        ),
        child: Row(children: [
          UserAvatar(e[0], size: 34),
          const SizedBox(width: 8),
          Expanded(child: Text(e[1], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _head(String t, Color c) => Padding(padding: const EdgeInsets.fromLTRB(8, 10, 8, 4), child: Text(t, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: c)));

  // نزول بقوة: تكبير ضخم ثم اصطدام بالشاشة
  Widget _slam(double tt, double t0, Widget child, {double dur = .38}) {
    if (tt < t0) return Opacity(opacity: 0, child: child);
    final p = _seg(tt, t0, t0 + dur);
    final scale = 2.6 - 1.6 * Curves.easeIn.transform(p);
    return Opacity(opacity: min(1.0, p * 4), child: Transform.scale(scale: scale, child: child));
  }

  // ارتجاج الشاشة عند كل اصطدام
  Offset _quake(double tt) {
    var dx = 0.0, dy = 0.0;
    for (final h in const [3.38, 3.88, 4.88, 5.38]) {
      final q = tt - h;
      if (q >= 0 && q < .45) {
        final k = 1 - q / .45;
        dx += sin(q * 70) * 7 * k;
        dy += cos(q * 55) * 5 * k;
      }
    }
    return Offset(dx, dy);
  }

  Widget _head2(bool atk, double tt) {
    final g = (f[atk ? 'ag' : 'dg'] ?? '').toString();
    final name = (f[atk ? 'an' : 'dn'] ?? '').toString();
    final t0 = atk ? 3.0 : 4.5;
    final col = atk ? _yellow : _red;
    return Column(children: [
      _slam(tt, t0, Container(
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: col, width: 4), boxShadow: [BoxShadow(color: col.withAlpha(120), blurRadius: 14)]),
        child: GroupPhoto(g, size: 120),
      )),
      const SizedBox(height: 6),
      _slam(tt, t0 + .5, Column(children: [
        Text(name, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        Text(atk ? 'المهاجم' : 'المدافع', style: TextStyle(color: col, fontWeight: FontWeight.w800)),
      ])),
    ]);
  }

  // قائمة واحدة: كل صف فيه مشرف/عضو من كل نقابة متقابلين، والفراغ يبقى فراغاً
  Widget _pairedList() {
    Widget cell(List<List<String>> l, int i, bool admin) => i < l.length ? _rect(l[i], admin) : const SizedBox(height: 54);
    Widget row(Widget a, Widget b) => Row(children: [Expanded(child: a), const SizedBox(width: 36), Expanded(child: b)]);
    final items = <Widget>[];
    final na = max(admA.length, admD.length);
    if (na > 0) {
      items.add(row(_head('👑 المشرفون:', _red), _head('👑 المشرفون:', _red)));
      for (var i = 0; i < na; i++) {
        items.add(row(cell(admA, i, true), cell(admD, i, true)));
      }
    }
    final nm = max(memA.length, memD.length);
    if (nm > 0) {
      items.add(row(_head('👤 الأعضاء:', const Color(0xFF4DA3FF)), _head('👤 الأعضاء:', const Color(0xFF4DA3FF))));
      for (var i = 0; i < nm; i++) {
        items.add(row(cell(memA, i, false), cell(memD, i, false)));
      }
    }
    if (items.isEmpty) return const SizedBox();
    items.add(const SizedBox(height: 60));
    return ListView.builder(controller: scA, itemBuilder: (c, i) => items[i % items.length]);
  }

  Widget _royal() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xF2050505), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x33FFFFFF))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🍷 الإمبراطور:', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFD4AF37))),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFF4A0F1F), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB03060), width: 2)),
            child: const Text('آلَجَيـــــــًّسًــــــــي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          if (roy.isNotEmpty) const Text('🖋 الرتب الملكية:', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF5DE08A))),
          if (roy.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: roy.take(8).map((e) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFF0B3A1F), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF3DDC84)), boxShadow: const [BoxShadow(color: Color(0x663DDC84), blurRadius: 10)]),
                  child: Text(e[1], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                )).toList()),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final tt = t;
    final win = (f['win'] ?? '').toString();
    final lose = (f['lose'] ?? '').toString();
    final winG = attackWon ? (f['ag'] ?? '').toString() : (f['dg'] ?? '').toString();
    final loseG = attackWon ? (f['dg'] ?? '').toString() : (f['ag'] ?? '').toString();
    final atkName = (f['an'] ?? '').toString();
    final defName = (f['dn'] ?? '').toString();
    Widget body;
    if (phase == 0) {
      final bg = _seg(tt, 6, 7.5);
      body = Stack(fit: StackFit.expand, children: [
        Container(color: Color.lerp(Colors.black, const Color(0xFF0A0F24), bg)),
        if (tt < 3.2)
          Center(
            child: Opacity(
              opacity: (_seg(tt, 0, .8) * (1 - _seg(tt, 2.0, 3.0))),
              child: const Text('دقيقة من وقتك!', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(color: Color(0xFFFF6A00), blurRadius: 24), Shadow(color: Color(0xFFFFD54A), blurRadius: 40)])),
            ),
          ),
        if (tt >= 3)
          Directionality(
            textDirection: TextDirection.ltr,
            child: Transform.translate(
              offset: _quake(tt),
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _head2(true, tt)),
                    SizedBox(width: 36, child: Padding(padding: const EdgeInsets.only(top: 50), child: Opacity(opacity: _seg(tt, 4.5, 5.0), child: const FittedBox(child: Text('VS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))))),
                    Expanded(child: _head2(false, tt)),
                  ]),
                  Expanded(child: Opacity(opacity: _seg(tt, 6.0, 6.8) * (1 - _seg(tt, endT - 4, endT - .3)), child: _pairedList())),
                ]),
              ),
            ),
          ),
        if (royalShown) Positioned(left: 14, right: 14, bottom: 30, child: Opacity(opacity: 1 - _seg(tt, endT - 4, endT - .3), child: _royal())),
        Positioned(top: 8, left: 0, right: 0, child: Opacity(opacity: tt > 3 ? .0 : 0, child: Text('$atkName ⚔️ $defName'))),
      ]);
    } else {
      body = Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedOpacity(opacity: resStep >= 1 ? 1 : 0, duration: const Duration(milliseconds: 900), child: const Text('النقابة التي انتصرت:', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(color: Color(0xFFFFD54A), blurRadius: 26)]))),
          const SizedBox(height: 18),
          AnimatedOpacity(opacity: resStep >= 2 ? 1 : 0, duration: const Duration(milliseconds: 900), child: Column(children: [
            Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFFD54A), width: 5), boxShadow: const [BoxShadow(color: Color(0xAAFFD54A), blurRadius: 30)]), child: GroupPhoto(winG, size: 150)),
            const SizedBox(height: 10),
            Text('👑 $win', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ])),
          const SizedBox(height: 26),
          AnimatedOpacity(opacity: resStep >= 3 ? 1 : 0, duration: const Duration(milliseconds: 900), child: Column(children: [
            GroupPhoto(loseG, size: 80),
            const SizedBox(height: 6),
            Text(lose, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('تم الغزو من قبل نقابة $win', textAlign: TextAlign.center, style: const TextStyle(color: _red, fontWeight: FontWeight.w900, fontSize: 16)),
          ])),
        ]),
      );
    }
    return PopScope(canPop: false, child: AbsorbPointer(child: Scaffold(backgroundColor: Colors.black, body: body)));
  }
}

// ---------- حسم الحروب (تنفّذه أجهزة المطورين/الإمبراطور) ----------
Future<void> settleWars() async {
  final now = DateTime.now().millisecondsSinceEpoch;
  Map<dynamic, dynamic> ws = {};
  try {
    final s = await ref('wars').get();
    if (s.value is Map) ws = s.value as Map;
  } catch (_) {
    return;
  }
  for (final e in ws.entries) {
    final w = e.value;
    if (w is! Map) continue;
    final wid = e.key.toString();
    if (w['s'] == 'p' && ((w['st'] as num?)?.toInt() ?? 0) <= now) await _settle(wid, Map<String, dynamic>.from(w));
    if (w['s'] == 'd' && w['res'] == 'a') await _applyMoves(wid, Map<String, dynamic>.from(w));
  }
}

Future<List<List<String>>> _rosterOf(String g, Set<String> high) async {
  // يرجع [[uid,name,isAdmin]]
  final out = <List<String>>[];
  try {
    final m = (await ref('members/$g').get()).value;
    final ad = (await ref('groupAdmins/$g').get()).value;
    if (m is Map) {
      for (final k in m.keys) {
        final u = k.toString();
        if (m[k] != true || high.contains(u)) continue;
        final p = await prof(u);
        out.add([u, p.name, (ad is Map && ad[u] == true) ? '1' : '0']);
      }
    }
  } catch (_) {}
  return out;
}

Future<void> _settle(String wid, Map<String, dynamic> w) async {
  final a = (w['a'] ?? '').toString(), d = (w['d'] ?? '').toString();
  try {
    final sa = (await ref('guildStats/$a').get()).value;
    final sd = (await ref('guildStats/$d').get()).value;
    final A = sa is Map ? Map<String, dynamic>.from(sa) : <String, dynamic>{'atk': 1, 'def': 1};
    final D = sd is Map ? Map<String, dynamic>.from(sd) : <String, dynamic>{'atk': 1, 'def': 1};
    final atk = (A['atk'] as num?)?.toInt() ?? 1, def = (D['def'] as num?)?.toInt() ?? 1;
    final win = atk > def ? 'a' : 'd';
    final lead = (await prof((w['by'] ?? '').toString())).name;
    // الرتب العليا لا تظهر في القوائم
    final high = <String>{};
    final dv = (await ref('devs').get()).value;
    if (dv is Map) high.addAll(dv.keys.map((e) => e.toString()));
    final emp = (await ref('config/emperorUid').get()).value?.toString() ?? '';
    if (emp.isNotEmpty) high.add(emp);
    final ra = await _rosterOf(a, high);
    final rd = await _rosterOf(d, high);
    final roy = <List<String>>[];
    for (final u in high) {
      if (u == emp) continue;
      roy.add([u, (await prof(u)).name]);
    }
    String js(List<List<String>> r, {bool withRoy = false}) => jsonEncode(<String, Object?>{
          'adm': r.where((e) => e[2] == '1').map((e) => [e[0], e[1]]).toList(),
          'mem': r.where((e) => e[2] == '0').map((e) => [e[0], e[1]]).toList(),
          if (withRoy) 'roy': roy,
        });
    final up = <String, Object?>{
      'wars/$wid/s': 'd',
      'wars/$wid/res': win,
      'activeWar/$a': null,
      'activeWar/$d': null,
    };
    final nameA = groupName(a), nameD = groupName(d);
    if (win == 'a') {
      final md = (await ref('members/$d').get()).value;
      final cand = <String, String>{};
      if (md is Map) {
        for (final k in md.keys) {
          if (md[k] != true) continue;
          final u = k.toString();
          up['wallets/$u/bal'] = 0;
          cand[u] = (await prof(u)).name;
        }
      }
      final con = A['contrib'];
      final ma = (await ref('members/$a').get()).value;
      final rec = <String, int>{};
      if (con is Map && con.isNotEmpty) {
        con.forEach((k, v) => rec[k.toString()] = (v as num).toInt());
      } else if (ma is Map) {
        for (final k in ma.keys) {
          if (ma[k] == true) rec[k.toString()] = 1;
        }
      }
      final tot = rec.values.fold<int>(0, (s, x) => s + x);
      if (tot > 0) {
        rec.forEach((u, c) {
          final sh = (10000 * c / tot).floor();
          if (sh > 0) up['wallets/$u/bal'] = ServerValue.increment(sh);
        });
      }
      up['warCand/$wid'] = cand;
      up['leadWar/${w['by']}'] = wid;
    } else {
      up['guildStats/$a/atk'] = 1;
      up['guildStats/$d/atk'] = ((D['atk'] as num?)?.toInt() ?? 1) + max(0, atk - 1);
    }
    final winName = win == 'a' ? nameA : nameD, loseName = win == 'a' ? nameD : nameA;
    up['warFeed/$wid/res'] = win;
    up['warFeed/$wid/win'] = winName;
    up['warFeed/$wid/lose'] = loseName;
    up['warFeed/$wid/lead'] = lead;
    up['warFeed/$wid/rA'] = js(ra, withRoy: true);
    up['warFeed/$wid/rD'] = js(rd);
    up['warFeed/$wid/rs'] = ServerValue.timestamp;
    // إشعار لكل أعضاء الطرفين بنتيجة الحرب
    for (final r in [...ra, ...rd]) {
      final k = ref('notifs/${r[0]}').push().key!;
      up['notifs/${r[0]}/$k'] = <String, Object?>{
        't': 'warend', 'from': myUid, 'ts': ServerValue.timestamp, 'tx': '🏆 انتهت الحرب: انتصرت نقابة $winName',
      };
    }
    await db.ref().update(up);
    await feedNote('news', '🏆 انتهت الحرب بانتصار نقابة $winName', k: 'war', d: jsonEncode({'t': 'res', 'win': winName, 'lose': loseName, 'lead': lead}));
  } catch (_) {}
}

Future<void> _applyMoves(String wid, Map<String, dynamic> w) async {
  try {
    final mv = (await ref('warMv/$wid').get()).value;
    if (mv == null) return;
    final list = (mv is List ? mv : (mv as Map).values.toList()).map((e) => e.toString()).take(5).toList();
    final up = <String, Object?>{'warMv/$wid': null, 'warCand/$wid': null, 'leadWar/${w['by']}': null};
    for (final u in list) {
      up['members/${w['d']}/$u'] = null;
      up['members/${w['a']}/$u'] = true;
    }
    await db.ref().update(up);
  } catch (_) {}
}

/// القائد المنتصر يختار حتى 5 أعضاء من النقابة المهزومة
Widget leaderPick(BuildContext context) {
  return FutureBuilder<List<dynamic>>(
    future: () async {
      final wid = (await ref('leadWar/$myUid').get()).value?.toString() ?? '';
      if (wid.isEmpty) return <dynamic>[];
      if ((await ref('warMv/$wid').get()).exists) return <dynamic>[];
      final cand = (await ref('warCand/$wid').get()).value;
      return <dynamic>[wid, cand];
    }(),
    builder: (c, s) {
      final d = s.data;
      if (d == null || d.isEmpty || d[1] is! Map) return const SizedBox();
      final wid = d[0] as String;
      final cand = Map<String, dynamic>.from(d[1] as Map);
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: accentA(context, .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
        child: Column(children: [
          const Text('🏆 انتصرت نقابتك! يحق لك نقل 5 أعضاء من النقابة المهزومة.', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          AppButton('اختيار الأعضاء', onPressed: () {
            final chosen = <String>{};
            showAppSheet<void>(context, (sc) => [
                  StatefulBuilder(builder: (cc, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('اختر حتى 5 (${chosen.length}/5)', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        ...cand.entries.map((e) => CheckboxListTile(
                              value: chosen.contains(e.key),
                              title: Text(e.value.toString()),
                              onChanged: (v) => set(() {
                                if (v == true && chosen.length < 5) {
                                  chosen.add(e.key);
                                } else {
                                  chosen.remove(e.key);
                                }
                              }),
                            )),
                        AppButton('تأكيد النقل', onPressed: () async {
                          if (chosen.isEmpty) return;
                          Navigator.of(sc).pop();
                          try {
                            await ref('warMv/$wid').set(chosen.toList());
                            toast('تم إرسال الطلب ✅');
                          } catch (e) {
                            err(e);
                          }
                        }),
                      ])),
                ]);
          }),
        ]),
      );
    },
  );
}
