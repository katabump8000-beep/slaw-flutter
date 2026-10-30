import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'aljesi.dart';
import 'app_state.dart';
import 'core.dart';
import 'data.dart';

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
  const EvCard({super.key, required this.text, this.col = ''});

  @override
  State<EvCard> createState() => _EvCardState();
}

class _EvCardState extends State<EvCard> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        'd': jsonEncode(<String, Object?>{'ev': 1, if (col.isNotEmpty) 'col': col}),
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
          await botSay(gid, '🎊 فاز $n بـ $title! 🏆\n💰 40 رصيد أُضيفت إلى رصيده', d: jsonEncode(<String, Object?>{'win': winner, 'amt': 40}));
          break;
        }
      } else {
        idle++;
        try {
          await ref('messages/$gid/$key/text').set('$show\n⌛ انتهى الوقت');
        } catch (_) {}
        if (idle >= 2) {
          await botSay(gid, '🛑 تم إلغاء الفعالية لعدم التفاعل.');
          break;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (stopped) await botSay(gid, '🛑 تم إلغاء الفعالية.');
    await _sub?.cancel();
    _active.remove(gid);
  }
}
