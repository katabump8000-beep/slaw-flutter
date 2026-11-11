import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'servertime.dart';
import 'data.dart';
import 'solo.dart' show evCall, evToastPublic;
import 'widgets.dart';

// شاشة الشطرنج الحية: اللوحة تُرسم من حالة السيرفر (chess/{cid}) والسيرفر يتحقق من كل حركة.
class ChessScreen extends StatefulWidget {
  final String gid, cid;
  const ChessScreen({super.key, required this.gid, required this.cid});
  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen> {
  Map<dynamic, dynamic> g = {};
  StreamSubscription<DatabaseEvent>? _s, _cs;
  Timer? _tick;
  final List<Map<dynamic, dynamic>> _chat = [];
  final TextEditingController _c = TextEditingController();
  int sel = -1;
  bool busy = false;

  bool get isPlayer => g['white'] == myUid || g['black'] == myUid;
  bool get iAmBlack => g['black'] == myUid;

  @override
  void initState() {
    super.initState();
    _s = ref('chess/${widget.cid}').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is Map && mounted) {
        setState(() {
          g = v;
          if (v['turn'] != null) busy = false;
        });
        _chatOnce();
      }
    }, onError: (_) {});
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    evCall(widget.gid, 'chwatch', {'cid': widget.cid, 'i': 1});
  }

  bool _chatOn = false;
  void _chatOnce() {
    if (_chatOn || !isPlayer) return;
    _chatOn = true;
    _cs = ref('chessC/${widget.cid}').orderByKey().limitToLast(30).onChildAdded.listen((e) {
      final v = e.snapshot.value;
      if (v is Map && mounted) setState(() => _chat.add(v));
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _s?.cancel();
    _cs?.cancel();
    _tick?.cancel();
    _c.dispose();
    evCall(widget.gid, 'chwatch', {'cid': widget.cid, 'i': 0});
    super.dispose();
  }

  List<String> get _board {
    final fen = (g['fen'] ?? '').toString();
    final out = <String>[];
    if (fen.isEmpty) return List.filled(64, '.');
    for (final row in fen.split(' ').first.split('/')) {
      for (final ch in row.split('')) {
        final n = int.tryParse(ch);
        if (n != null) {
          out.addAll(List.filled(n, '.'));
        } else {
          out.add(ch);
        }
      }
    }
    return out.length == 64 ? out : List.filled(64, '.');
  }

  List<String> get _legal => (g['legal'] is List) ? (g['legal'] as List).map((e) => e.toString()).toList() : <String>[];
  String _nm(int i) => 'abcdefgh'[i & 7] + (8 - (i >> 3)).toString();
  bool get _myTurn => g['st'] == 'play' && ((g['turn'] == 'w' && g['white'] == myUid) || (g['turn'] == 'b' && g['black'] == myUid));

  Future<void> _tap(int i) async {
    if (!_myTurn || busy) return;
    final b = _board;
    final p = b[i];
    final mineColor = iAmBlack ? 'b' : 'w';
    final isMine = p != '.' && ((p.toUpperCase() == p) == (mineColor == 'w'));
    if (isMine) {
      setState(() => sel = i == sel ? -1 : i);
      return;
    }
    if (sel < 0) return;
    final base = _nm(sel) + _nm(i);
    final lg = _legal;
    String? mv;
    if (lg.contains(base)) {
      mv = base;
    } else if (lg.contains('${base}q')) {
      final pc = await showDialog<String>(
        context: context,
        builder: (d) => SimpleDialog(title: const Text('اختر القطعة'), children: [
          for (final e in const [['q', '♛ وزير'], ['r', '♜ قلعة'], ['b', '♝ فيل'], ['n', '♞ حصان']])
            SimpleDialogOption(onPressed: () => Navigator.pop(d, e[0]), child: Text(e[1], style: const TextStyle(fontSize: 18))),
        ]),
      );
      if (pc == null) return;
      mv = base + pc;
    }
    if (mv == null) {
      setState(() => sel = -1);
      return;
    }
    setState(() {
      sel = -1;
      busy = true;
    });
    final e = await evCall(widget.gid, 'chmove', {'cid': widget.cid, 'mv': mv});
    if (e.isNotEmpty) {
      evToastPublic(e);
      if (mounted) setState(() => busy = false);
    }
  }

  String _mmss(int ms) {
    final s = (ms ~/ 1000).clamp(0, 9999);
    return '${(s ~/ 60).toString().padLeft(1, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _bar(String uid, String name, bool white, bool turn) {
    final left = turn && g['st'] == 'play' ? _mmss(((g['dl'] as num?)?.toInt() ?? 0) - nowMs()) : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: turn && g['st'] == 'play' ? const Color(0xFF1E2A12) : Colors.transparent, border: Border(bottom: BorderSide(color: Colors.white12))),
      child: Row(children: [
        UserAvatar(uid, size: 30),
        const SizedBox(width: 8),
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
        Text(white ? '♔ أبيض' : '♚ أسود', style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
        const SizedBox(width: 10),
        if (left.isNotEmpty) Text(left, style: TextStyle(fontWeight: FontWeight.w900, color: left.startsWith('0:') && int.tryParse(left.split(':')[1])! < 30 ? kRed : Colors.white)),
      ]),
    );
  }

  Widget _boardView() {
    final b = _board;
    final flip = iAmBlack;
    final last = (g['last'] ?? '').toString();
    final legalTargets = <String>{};
    if (sel >= 0) {
      for (final m in _legal) {
        if (m.startsWith(_nm(sel))) legalTargets.add(m.substring(2, 4));
      }
    }
    final turnW = g['turn'] == 'w';
    final inCheck = g['chk'] == true;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (c, cs) {
        final sz = cs.maxWidth / 8;
        return Stack(children: [
          for (var vi = 0; vi < 64; vi++)
            Builder(builder: (_) {
              final r = vi >> 3, f = vi & 7;
              final i = flip ? (7 - r) * 8 + (7 - f) : vi; // مربع اللوحة الفعلي
              final p = b[i];
              final dark = ((i >> 3) + (i & 7)) % 2 == 1;
              final name = _nm(i);
              var bg = dark ? const Color(0xFF7A5A3A) : const Color(0xFFE8D2A8);
              if (last.length == 4 && (name == last.substring(0, 2) || name == last.substring(2, 4))) bg = Color.alphaBlend(const Color(0x88FFEB3B), bg);
              if (i == sel) bg = const Color(0xFFFFD54A);
              if (inCheck && ((turnW && p == 'K') || (!turnW && p == 'k'))) bg = const Color(0xFFE53935);
              final white = p != '.' && p.toUpperCase() == p;
              const glyph = {'k': '♚', 'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟'};
              return Positioned(
                left: f * sz,
                top: r * sz,
                width: sz,
                height: sz,
                child: GestureDetector(
                  onTap: () => _tap(i),
                  child: Container(
                    color: bg,
                    alignment: Alignment.center,
                    child: Stack(alignment: Alignment.center, children: [
                      if (legalTargets.contains(name)) Container(width: sz * (p == '.' ? .3 : .85), height: sz * (p == '.' ? .3 : .85), decoration: BoxDecoration(shape: BoxShape.circle, color: p == '.' ? Colors.black26 : null, border: p == '.' ? null : Border.all(color: Colors.black38, width: 3))),
                      if (p != '.')
                        Text(glyph[p.toLowerCase()]!, style: TextStyle(fontSize: sz * .78, height: 1, color: white ? Colors.white : const Color(0xFF111111), shadows: [Shadow(color: white ? Colors.black : Colors.white54, blurRadius: 2, offset: const Offset(0, 0)), Shadow(color: white ? Colors.black : Colors.white54, blurRadius: 1)])),
                    ]),
                  ),
                ),
              );
            }),
        ]);
      }),
    );
  }

  Future<void> _resign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: const Text('هل تريد الانسحاب؟ ستخسر الرهان.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')), TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('انسحاب'))],
      ),
    );
    if (ok != true) return;
    final e = await evCall(widget.gid, 'chres', {'cid': widget.cid});
    if (e.isNotEmpty) evToastPublic(e);
  }

  Future<void> _say() async {
    final t = _c.text.trim();
    if (t.isEmpty || !isPlayer) return;
    _c.clear();
    try {
      await ref('chessC/${widget.cid}').push().set(<String, Object?>{'u': myUid, 't': t.length > 200 ? t.substring(0, 200) : t, 'ts': ServerValue.timestamp});
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = g['st'] == 'done';
    final wTurn = g['turn'] == 'w';
    final wu = (g['white'] ?? '').toString(), bu = (g['black'] ?? '').toString();
    final wn = (g['wn'] ?? '').toString(), bn = (g['bn'] ?? '').toString();
    final topIsBlack = !iAmBlack; // من يظهر في الأعلى
    String banner = '';
    if (done) {
      final res = g['res'];
      banner = res == 'w' ? '🏆 فاز $wn (أبيض) — ${g['why'] ?? ''}' : res == 'b' ? '🏆 فاز $bn (أسود) — ${g['why'] ?? ''}' : res == 'd' ? '🤝 تعادل — ${g['why'] ?? ''}' : 'أُلغيت المباراة';
    } else if (g['chk'] == true) {
      banner = '⚠️ كش!';
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('♟ الشطرنج'),
        actions: [
          if (((g['eyes'] as num?)?.toInt() ?? 0) > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Center(child: Text('👁 ${g['eyes']}', style: const TextStyle(fontWeight: FontWeight.w900)))),
          if (isPlayer && !done) TextButton(onPressed: _resign, child: const Text('انسحاب', style: TextStyle(color: kRed, fontWeight: FontWeight.w900))),
        ],
      ),
      body: g.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(children: [
                topIsBlack ? _bar(bu, bn, false, !wTurn) : _bar(wu, wn, true, wTurn),
                _boardView(),
                iAmBlack ? _bar(bu, bn, false, !wTurn) : _bar(wu, wn, true, wTurn),
                if (banner.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(banner, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: done ? const Color(0xFFFFD54A) : kRed))),
                if (isPlayer && !done && _myTurn) const Text('دورك الآن', style: TextStyle(color: Color(0xFF7CFFB2), fontWeight: FontWeight.w800)),
                Expanded(
                  child: isPlayer
                      ? Column(children: [
                          Expanded(
                            child: ListView(reverse: true, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                              for (final m in _chat.reversed)
                                Align(
                                  alignment: m['u'] == myUid ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                                  child: Container(margin: const EdgeInsets.symmetric(vertical: 2), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: m['u'] == myUid ? const Color(0xFF1F3D2B) : const Color(0xFF22262D), borderRadius: BorderRadius.circular(10)), child: Text((m['t'] ?? '').toString())),
                                ),
                            ]),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                            child: Row(children: [
                              Expanded(child: TextField(controller: _c, textInputAction: TextInputAction.send, onSubmitted: (_) => _say(), decoration: const InputDecoration(isDense: true, hintText: 'تحدث مع خصمك...'))),
                              IconButton(onPressed: _say, icon: const Icon(Icons.send_rounded)),
                            ]),
                          ),
                        ])
                      : const Center(child: Text('أنت تشاهد المباراة 👁', style: TextStyle(color: kMu))),
                ),
              ]),
            ),
    );
  }
}
