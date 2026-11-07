import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'aljesi.dart';
import 'app_state.dart';
import 'core.dart';
import 'data.dart';
import 'servertime.dart';
import 'widgets.dart';

const List<String> _names = [
  'ناروتو', 'ناروتو أوزوماكي', 'ساسكي', 'ساكورا', 'كاكاشي', 'ايتاتشي', 'مادارا', 'هيناتا', 'جيرايا',
  'لوفي', 'زورو', 'سانجي', 'اس', 'غوكو', 'فيجيتا', 'جوهان', 'ايرين', 'ميكاسا', 'ليفاي',
  'ناتسو', 'غراي', 'ايتشيغو', 'روكيا', 'غون', 'كيلوا', 'تانجيرو', 'نيزوكو', 'ساتورو غوجو', 'يوجي', 'ميغومي',
  'لايت', 'ريوك', 'ديكو', 'باكوغو', 'اينوسكي', 'ساسكي اوتشيها',
];

const List<List<Object>> _evColors = [
  ['أحمر', '#FF3B3B', '🔴'],
  ['أزرق', '#3B7BFF', '🔵'],
  ['أخضر', '#2EE07A', '🟢'],
  ['أصفر', '#FFD83B', '🟡'],
  ['بنفسجي', '#A64BFF', '🟣'],
  ['برتقالي', '#FF8A1F', '🟠'],
];

/// بطاقة فعالية سوداء (تُعرض لرسائل ALJESI التي فيها d={"ev":1,"col":"#RRGGBB"})
class EvCard extends StatefulWidget {
  final String text;
  final String col;
  final Map<String, dynamic>? o; // بطاقة الجيل الجديد (v:2) يرسلها السيرفر
  final int at;
  final bool canCancel;
  final bool cancelLocked;
  final VoidCallback? onCancel;
  const EvCard({super.key, required this.text, this.col = '', this.o, this.at = 0, this.canCancel = false, this.cancelLocked = false, this.onCancel});

  @override
  State<EvCard> createState() => _EvCardState();
}

class _EvCardState extends State<EvCard> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  Timer? _tk;

  @override
  void initState() {
    super.initState();
    final o = widget.o;
    if (o != null && o['cd'] is num) {
      _tk = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tk?.cancel();
    c.dispose();
    super.dispose();
  }

  static String _ago(int at) {
    if (at <= 0) return 'الآن';
    final s = ((nowMs() - at) / 1000).floor();
    if (s < 60) return 'منذ لحظات';
    if (s < 3600) return 'منذ ${s ~/ 60} دقيقة';
    if (s < 86400) return 'منذ ${s ~/ 3600} ساعة';
    return 'منذ ${s ~/ 86400} يوم';
  }

  Widget _ball(Color col, double size) => AnimatedBuilder(
        animation: c,
        builder: (_, __) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: col,
            boxShadow: [BoxShadow(color: col.withAlpha(200), blurRadius: 18 + 36 * c.value, spreadRadius: 4 + 14 * c.value)],
          ),
        ),
      );

  Widget _decor(String s, Color col) => Text(s, textAlign: TextAlign.center, style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 15, height: 1.3));

  Widget _row(String k, String v, Color col, {double size = 17}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$k  ', style: TextStyle(color: col, fontWeight: FontWeight.w900)),
            TextSpan(text: v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: size),
        ),
      );

  Widget _cancel(Map<String, dynamic> o) {
    if (!widget.canCancel) return const SizedBox.shrink();
    if (widget.cancelLocked) {
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0x33888888), borderRadius: BorderRadius.circular(12)),
        child: const Text('لم يعد بإمكانك الغاء الفعالية لأنها اصبحت مثيرة لدى الاعضاء!', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 12.5, fontWeight: FontWeight.w700)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        child: GestureDetector(
          onTap: widget.onCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(color: const Color(0x33FF3B3B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFF3B3B))),
            child: const Text('الغاء الفعالية', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w900, fontSize: 13.5)),
          ),
        ),
      ),
    );
  }

  Widget _v2(BuildContext context, Map<String, dynamic> o) {
    final k = (o['k'] ?? '').toString();
    final base = hexOk(o['col']?.toString()) ? hexColor(o['col'].toString()) : const Color(0xFF39FF88);
    final accent = context.accent;
    final edge = (k == 'result' || k == 'ann') ? accent : base;
    final left = o['cd'] is num ? max(0, (((o['cd'] as num).toInt() - nowMs()) / 1000).ceil()) : 0;
    final kids = <Widget>[];
    if (k == 'intro') {
      kids.add(_decor('❆━━━━━═⏣⊰🎮⊱⏣═━━━━━❆', base));
      kids.add(const SizedBox(height: 8));
      kids.add(ShaderMask(
        shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFF3B3B), Color(0xFFFFD83B), Color(0xFF2EE07A), Color(0xFF3B7BFF), Color(0xFFA64BFF), Color(0xFFFF6FB5)]).createShader(r),
        child: Text((o['title'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: Colors.white)),
      ));
      kids.add(const SizedBox(height: 10));
      kids.add(Text('الشرح: ${o['how'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.7, fontWeight: FontWeight.w700, color: Colors.white)));
      final ex = o['ex'];
      if (ex is Map) {
        kids.add(const SizedBox(height: 10));
        kids.add(Text('مثال عن الفعالية:', textAlign: TextAlign.center, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: base)));
        kids.add(Text((ex['a'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.white70)));
        if (hexOk(ex['ball']?.toString())) kids.add(Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Center(child: _ball(hexColor(ex['ball'].toString()), 52))));
        if ((ex['big'] ?? '').toString().isNotEmpty) kids.add(Text(ex['big'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 54)));
        kids.add(Text((ex['b'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.white70)));
      }
      kids.add(const SizedBox(height: 12));
      kids.add(Text('ستبدأ الفعالية بعد:  $left', textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF39FF14))));
      kids.add(const SizedBox(height: 6));
      kids.add(_decor('❆━━━━━═⏣⊰🎮⊱⏣═━━━━━❆', base));
    } else if (k == 'round') {
      kids.add(_decor('╗══════════════════╔', base));
      kids.add(const SizedBox(height: 8));
      kids.add(Text((o['q'] ?? '').toString(), textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: base)));
      kids.add(const SizedBox(height: 10));
      final big = (o['big'] ?? '').toString();
      if (big == 'ball') {
        kids.add(Padding(padding: const EdgeInsets.symmetric(vertical: 22), child: Center(child: _ball(base, 118))));
      } else if (big == 'emoji') {
        kids.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text((o['e'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 112))));
      } else {
        kids.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text((o['w'] ?? '').toString(), textAlign: TextAlign.center, style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, height: 1.4, color: accent, shadows: [Shadow(color: accent.withAlpha(180), blurRadius: 16)])),
        ));
      }
      kids.add(Text('المدة:  $left', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: left <= 5 ? const Color(0xFFFF6B6B) : base)));
      final first = (o['first'] ?? '').toString();
      if (first.isNotEmpty) {
        kids.add(const SizedBox(height: 8));
        kids.add(Text('أول من أجاب:  $first', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF4CE07A))));
      }
      kids.add(const SizedBox(height: 8));
      kids.add(_decor('╝══════════════════╚', base));
    } else if (k == 'result' || k == 'ann') {
      kids.add(_decor('╗══════════════════╔', accent));
      if (k == 'ann') kids.add(Text('إنتهت!', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: accent)));
      kids.add(const SizedBox(height: 8));
      final w = (o['winner'] ?? '').toString();
      if (w.isNotEmpty) {
        kids.add(Center(
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent, width: 3), boxShadow: [BoxShadow(color: accent.withAlpha(150), blurRadius: 18)]),
            child: UserAvatar(w, size: 84),
          ),
        ));
        kids.add(const SizedBox(height: 8));
      }
      kids.add(_row('الفائز:', (o['wn'] ?? '').toString(), accent, size: 20));
      kids.add(_row('الجائزة:', '${o['prize'] ?? ''} رصيد', accent));
      if (k == 'ann') {
        kids.add(_row('كمية الفوز:', '${o['wins'] ?? 0}', accent));
        kids.add(_row('كمية الخسارة:', '${o['loss'] ?? 0}', accent));
        kids.add(_row('النقابة:', (o['g'] ?? '').toString(), accent));
      }
      kids.add(_row('الفعالية:', (o['kn'] ?? '').toString(), accent));
      kids.add(_row(k == 'ann' ? 'التوقيت:' : 'الوقت:', _ago(widget.at > 0 ? widget.at : ((o['at'] as num?)?.toInt() ?? 0)), accent));
      if (k == 'result') kids.add(_row('منشأ الفعالية:', (o['bn'] ?? '').toString(), accent));
      kids.add(const SizedBox(height: 6));
      kids.add(_decor('╝══════════════════╚', accent));
    } else {
      kids.add(Text(widget.text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: base)));
    }
    if (k == 'intro' || k == 'round') kids.add(_cancel(o));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: edge.withAlpha(200), width: 1.6),
        boxShadow: [BoxShadow(color: edge.withAlpha(95), blurRadius: 22, spreadRadius: 1)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    if (o != null && o['v'] == 2) return _v2(context, o);
    final has = hexOk(widget.col);

    final col = has ? hexColor(widget.col) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: has ? col.withAlpha(150) : const Color(0x55FFFFFF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (has)
          Center(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: c,
                builder: (_, __) => Container(
                  width: 74,
                  height: 74,
                  margin: const EdgeInsets.only(bottom: 12, top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: col,
                    boxShadow: [BoxShadow(color: col.withAlpha(170), blurRadius: 12 + 28 * c.value, spreadRadius: 2 + 10 * c.value)],
                  ),
                ),
              ),
            ),
          ),
        for (final l in widget.text.split('\n'))
          Text(
            l,
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.7,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: l.startsWith('✅') ? const Color(0xFF4CE07A) : col,
            ),
          ),
      ]),
    );
  }
}

/// فعاليات الكتابة / التفكيك / الألوان: يديرها جهاز من بدأها، وتعمل داخل الشات
class EventsHost {
  static final Map<String, EventsHost> _active = {};
  final String gid;
  final String kind;
  final String starter;
  final String eid = newEventId();
  bool stopped = false;
  Completer<String>? _cur;
  String _want = '';
  StreamSubscription<DatabaseEvent>? _sub;
  EventsHost(this.gid, this.kind, this.starter);

  static bool isActive(String gid) => _active.containsKey(gid);

  static void cancel(String gid) {
    final h = _active[gid];
    if (h == null) return;
    h.stopped = true;
    final c = h._cur;
    if (c != null && !c.isCompleted) c.complete('');
  }

  static Future<void> start(String gid, String kind) async {
    if (_active.containsKey(gid)) {
      toast('هناك فعالية قيد التشغيل في هذا القروب', bad: true);
      return;
    }
    final h = EventsHost(gid, kind, myUid);
    _active[gid] = h;
    h._run();
  }

  Future<String> _card(String text, {String col = ''}) async {
    final key = ref('messages/$gid').push().key!;
    try {
      await ref('messages/$gid/$key').set(<String, Object?>{
        'from': myUid,
        'type': 'sys',
        'k': 'bot',
        'f': Session.me.name,
        'text': text,
        'd': jsonEncode(<String, Object?>{'ev': 1, 'eid': eid, if (col.isNotEmpty) 'col': col}),
        'ts': ServerValue.timestamp,
      });
    } catch (_) {}
    return key;
  }

  Future<bool> _canCancel(String uid) async {
    if (uid == starter) return true;
    try {
      final r = await roleOf(uid);
      if (r == 'emp' || r == 'dev') return true;
      return (await ref('groupAdmins/$gid/$uid').get()).exists;
    } catch (_) {
      return false;
    }
  }

  void _onMsg(Map<dynamic, dynamic> v) {
    if (v['type'] != 'text') return;
    final text = (v['text'] ?? '').toString();
    final from = (v['from'] ?? '').toString();
    if (normAr(text) == '.الغاء') {
      _canCancel(from).then((ok) {
        if (ok && !stopped) {
          stopped = true;
          final c = _cur;
          if (c != null && !c.isCompleted) c.complete('');
        }
      });
      return;
    }
    final c = _cur;
    if (c != null && !c.isCompleted && _want.isNotEmpty && normAr(text) == _want) c.complete(from);
  }

  Future<void> _run() async {
    final title = kind == 'type' ? '⌨️ فعالية الكتابة' : (kind == 'scramble' ? '🧩 فعالية التفكيك' : '🎨 فعالية الألوان');
    final how = kind == 'type'
        ? 'النظام يرسل كلمة وأنت تكتبها نفسها.\nمثال: ناروتو = ناروتو'
        : (kind == 'scramble'
            ? 'النظام يرسل كلمة مفككة وأنت تكتبها مجمّعة.\nمثال: ن ا ر و ت و = ناروتو'
            : 'النظام يعرض دائرة مشعة بلون، واكتب اسم اللون.\nمثال: 🔵 = أزرق');
    final first = await _card('╮─❖『 $title 』❖─╭\n$how\nأول من يصل إلى 10 إجابات صحيحة يفوز بـ 40 رصيد 🏆\nلإلغاء الفعالية اكتب: .الغاء\n╰─❖『 بالتوفيق 🍀 』❖─╯');
    _sub = ref('messages/$gid').orderByKey().startAfter(first).onChildAdded.listen((e) {
      final v = e.snapshot.value;
      if (v is Map) _onMsg(v);
    });
    final scores = <String, int>{};
    final rnd = Random();
    final pool = List<String>.of(_names)..shuffle();
    var idx = 0;
    var idle = 0;
    await Future<void>.delayed(const Duration(seconds: 4));
    while (!stopped) {
      String show;
      String col = '';
      if (kind == 'colors') {
        final c = _evColors[rnd.nextInt(_evColors.length)];
        _want = normAr(c[0] as String);
        col = c[1] as String;
        show = 'ما هو هذا اللون: ${c[2]}';
      } else {
        final nm = pool[idx % pool.length];
        idx++;
        _want = normAr(nm);
        if (kind == 'type') {
          show = 'الكلمة: $nm';
        } else {
          final words = nm.split(' ').map((w) => w.split('').join(' ')).toList();
          show = 'الكلمة: ${words.join('   ')}';
        }
      }
      final done = Completer<String>();
      _cur = done;
      final key = await _card(show, col: col);
      String winner = '';
      try {
        winner = await done.future.timeout(const Duration(seconds: 40));
      } catch (_) {
        winner = '';
      }
      _want = '';
      if (stopped) break;
      if (winner.isNotEmpty) {
        idle = 0;
        scores[winner] = (scores[winner] ?? 0) + 1;
        final n = (await prof(winner)).name;
        final sc = scores[winner]!;
        try {
          await ref('messages/$gid/$key/text').set('$show\n✅ $n هو من أجاب — $sc/10');
        } catch (_) {}
        if (sc >= 10) {
          await botSay(gid, '🎊 فاز $n بـ $title! 🏆\n💰 40 رصيد أُضيفت إلى رصيده', d: jsonEncode(<String, Object?>{'win': winner, 'amt': 40, 'eid': eid}));
          break;
        }
      } else {
        idle++;
        try {
          await ref('messages/$gid/$key/text').set('$show\n⌛ انتهى الوقت');
        } catch (_) {}
        if (idle >= 2) {
          await botSay(gid, '🛑 تم إلغاء الفعالية لعدم التفاعل.', d: jsonEncode(<String, Object?>{'eid': eid}));
          break;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (stopped) await botSay(gid, '🛑 تم إلغاء الفعالية.', d: jsonEncode(<String, Object?>{'eid': eid}));
    await markEventEnd(gid, eid);
    await _sub?.cancel();
    _active.remove(gid);
  }
}
