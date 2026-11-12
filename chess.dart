import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'servertime.dart';
import 'sfx.dart';
import 'solo.dart' show evCall, evToastPublic;
import 'widgets.dart';

/// ألوان الطاولة: [مربع فاتح، مربع داكن]
const List<List<Color>> kChessPalettes = [
  [Color(0xFFE8D2A8), Color(0xFF7A5A3A)], // كلاسيك
  [Color(0xFFEEEED2), Color(0xFF769656)], // أخضر
  [Color(0xFFDEE3E6), Color(0xFF8CA2AD)], // أزرق رمادي
  [Color(0xFFE0E0E0), Color(0xFF7D8796)], // رمادي
  [Color(0xFFE8DAF0), Color(0xFF8E6FB0)], // بنفسجي
  [Color(0xFFF8E1E7), Color(0xFFC47B93)], // وردي
  [Color(0xFF8A99AE), Color(0xFF3A4556)], // ليلي
  [Color(0xFFF0E6C8), Color(0xFFB58863)], // رمل
];
const List<String> kChessPaletteNames = ['كلاسيك', 'أخضر', 'أزرق', 'رمادي', 'بنفسجي', 'وردي', 'ليلي', 'رملي'];

// ------------------------------------------------------------------
// رسم القطع بأشكالها العالمية (ستونتون) — متّجهات واضحة بدل رموز الخطوط
// ------------------------------------------------------------------
class ChessPiece extends CustomPainter {
  final String t; // k q r b n p
  final bool white;
  const ChessPiece(this.t, this.white);

  RRect _base(double x, double y, double w, double h) => RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(4));

  @override
  void paint(Canvas cv, Size s) {
    cv.save();
    cv.scale(s.width / 100, s.height / 100);
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: white ? const [Color(0xFFFFFFFF), Color(0xFFD6D6D6)] : const [Color(0xFF5A5A5A), Color(0xFF151515)],
      ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = white ? const Color(0xFF1A1A1A) : const Color(0xFF000000);
    final hi = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = white ? const Color(0x33000000) : const Color(0x66FFFFFF);
    void shape(Path p) {
      cv.drawPath(p, fill);
      cv.drawPath(p, line);
    }

    void rr(RRect r) {
      cv.drawRRect(r, fill);
      cv.drawRRect(r, line);
    }

    switch (t) {
      case 'p':
        cv.drawCircle(const Offset(50, 30), 12, fill);
        cv.drawCircle(const Offset(50, 30), 12, line);
        shape(Path()
          ..moveTo(37, 76)
          ..quadraticBezierTo(39, 56, 45, 45)
          ..lineTo(55, 45)
          ..quadraticBezierTo(61, 56, 63, 76)
          ..close());
        rr(_base(41, 41, 18, 6));
        rr(_base(28, 76, 44, 11));
        cv.drawLine(const Offset(45, 56), const Offset(44, 72), hi);
        break;
      case 'r':
        shape(Path()
          ..moveTo(30, 16)
          ..lineTo(30, 30)
          ..lineTo(36, 37)
          ..lineTo(36, 68)
          ..lineTo(30, 76)
          ..lineTo(70, 76)
          ..lineTo(64, 68)
          ..lineTo(64, 37)
          ..lineTo(70, 30)
          ..lineTo(70, 16)
          ..lineTo(62, 16)
          ..lineTo(62, 24)
          ..lineTo(56, 24)
          ..lineTo(56, 16)
          ..lineTo(44, 16)
          ..lineTo(44, 24)
          ..lineTo(38, 24)
          ..lineTo(38, 16)
          ..close());
        cv.drawLine(const Offset(36, 37), const Offset(64, 37), line);
        rr(_base(24, 76, 52, 11));
        cv.drawLine(const Offset(41, 42), const Offset(41, 66), hi);
        break;
      case 'b':
        cv.drawCircle(const Offset(50, 13), 5, fill);
        cv.drawCircle(const Offset(50, 13), 5, line);
        shape(Path()
          ..moveTo(50, 19)
          ..cubicTo(72, 34, 68, 52, 58, 56)
          ..lineTo(42, 56)
          ..cubicTo(32, 52, 28, 34, 50, 19)
          ..close());
        cv.drawLine(const Offset(46, 30), const Offset(56, 42), line);
        shape(Path()
          ..moveTo(42, 56)
          ..lineTo(36, 76)
          ..lineTo(64, 76)
          ..lineTo(58, 56)
          ..close());
        rr(_base(36, 53, 28, 6));
        rr(_base(26, 76, 48, 11));
        break;
      case 'n':
        shape(Path()
          ..moveTo(30, 78)
          ..cubicTo(30, 60, 36, 52, 44, 44)
          ..cubicTo(38, 44, 32, 48, 24, 56)
          ..lineTo(19, 51)
          ..cubicTo(24, 43, 34, 32, 40, 28)
          ..lineTo(38, 14)
          ..lineTo(47, 21)
          ..cubicTo(54, 15, 63, 17, 68, 26)
          ..cubicTo(78, 38, 76, 62, 72, 78)
          ..close());
        cv.drawCircle(const Offset(52, 29), 2.6, Paint()..color = white ? const Color(0xFF1A1A1A) : const Color(0xFFEDEDED));
        cv.drawLine(const Offset(24, 52), const Offset(28, 55), line);
        rr(_base(26, 78, 50, 10));
        cv.drawLine(const Offset(60, 40), const Offset(66, 60), hi);
        break;
      case 'q':
        shape(Path()
          ..moveTo(26, 34)
          ..lineTo(34, 66)
          ..lineTo(66, 66)
          ..lineTo(74, 34)
          ..lineTo(62, 50)
          ..lineTo(60, 26)
          ..lineTo(50, 46)
          ..lineTo(40, 26)
          ..lineTo(38, 50)
          ..close());
        for (final o in const [Offset(26, 31), Offset(38, 22), Offset(50, 17), Offset(62, 22), Offset(74, 31)]) {
          cv.drawCircle(o, 4.4, fill);
          cv.drawCircle(o, 4.4, line);
        }
        shape(Path()
          ..moveTo(34, 66)
          ..lineTo(30, 78)
          ..lineTo(70, 78)
          ..lineTo(66, 66)
          ..close());
        rr(_base(26, 78, 48, 10));
        break;
      case 'k':
        shape(Path()..addRect(const Rect.fromLTWH(46, 6, 8, 26)));
        shape(Path()..addRect(const Rect.fromLTWH(39, 13, 22, 8)));
        shape(Path()
          ..moveTo(33, 66)
          ..cubicTo(25, 46, 31, 32, 50, 32)
          ..cubicTo(69, 32, 75, 46, 67, 66)
          ..close());
        cv.drawLine(const Offset(40, 44), const Offset(60, 44), hi);
        shape(Path()
          ..moveTo(33, 66)
          ..lineTo(29, 78)
          ..lineTo(71, 78)
          ..lineTo(67, 66)
          ..close());
        rr(_base(25, 78, 50, 10));
        break;
    }
    cv.restore();
  }

  @override
  bool shouldRepaint(covariant ChessPiece o) => o.t != t || o.white != white;
}

/// حلقة وقت تتقلص حول صورة اللاعب
class _Ring extends CustomPainter {
  final double v; // 0..1
  final bool on;
  _Ring(this.v, this.on);
  @override
  void paint(Canvas cv, Size s) {
    final r = Rect.fromLTWH(2, 2, s.width - 4, s.height - 4);
    cv.drawArc(r, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white12);
    if (!on) return;
    final c = Color.lerp(const Color(0xFFE53935), const Color(0xFF43E07A), v.clamp(0.0, 1.0))!;
    cv.drawArc(r, -math.pi / 2, math.pi * 2 * v.clamp(0.0, 1.0), false, Paint()..style = PaintingStyle.stroke..strokeWidth = 3.4..strokeCap = StrokeCap.round..color = c);
  }

  @override
  bool shouldRepaint(covariant _Ring o) => o.v != v || o.on != on;
}

// ------------------------------------------------------------------
class ChessScreen extends StatefulWidget {
  final String gid, cid;
  const ChessScreen({super.key, required this.gid, required this.cid});
  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen> {
  Map<dynamic, dynamic> g = {};
  Map<dynamic, dynamic> pres = {};
  StreamSubscription<DatabaseEvent>? _s, _cs, _ps;
  Timer? _tick, _hb;
  final List<Map<dynamic, dynamic>> _chat = [];
  final TextEditingController _c = TextEditingController();
  int sel = -1;
  bool busy = false;
  bool _vs = true;
  bool _vsDecided = false;
  String _prevFen = '';
  int _prevPieces = 32;
  bool _prevChk = false;
  bool _endSound = false;

  bool get isPlayer => g['white'] == myUid || g['black'] == myUid;
  bool get iAmBlack => g['black'] == myUid;

  @override
  void initState() {
    super.initState();
    _s = ref('chess/${widget.cid}').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is Map && mounted) {
        _onState(v);
      }
    }, onError: (_) {});
    _ps = ref('chessP/${widget.cid}').onValue.listen((e) {
      final v = e.snapshot.value;
      if (mounted) setState(() => pres = v is Map ? v : {});
    }, onError: (_) {});
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    evCall(widget.gid, 'chwatch', {'cid': widget.cid, 'i': 1});
  }

  void _beat() {
    if (!isPlayer) return;
    ref('chessP/${widget.cid}/$myUid').set(ServerValue.timestamp).catchError((Object _) {});
  }

  void _startPresence() {
    if (_hb != null || !isPlayer) return;
    final r = ref('chessP/${widget.cid}/$myUid');
    r.onDisconnect().set(0).catchError((Object _) {});
    _beat();
    _hb = Timer.periodic(const Duration(seconds: 10), (_) => _beat());
  }

  int _count(String fen) {
    var n = 0;
    for (final ch in fen.split(' ').first.split('')) {
      if (RegExp(r'[a-zA-Z]').hasMatch(ch)) n++;
    }
    return n;
  }

  void _snd(String f, [double v = .8]) {
    try {
      Sfx.start(f, volume: v).then((_) {}, onError: (Object _) {});
    } catch (_) {}
  }

  void _onState(Map<dynamic, dynamic> v) {
    final fen = (v['fen'] ?? '').toString();
    final chk = v['chk'] == true;
    final pieces = _count(fen);
    if (_prevFen.isNotEmpty && fen != _prevFen) {
      if (v['st'] == 'done' && v['why'] == 'كش مات') {
        _snd('mlk.mp3', 1);
        _endSound = true;
      } else if (chk && !_prevChk) {
        _snd('mlk.mp3', 1);
      } else if (pieces < _prevPieces) {
        _snd('chcap.wav', .9);
      } else {
        _snd('chmove.wav', .8);
      }
    }
    _prevFen = fen;
    _prevPieces = pieces;
    _prevChk = chk;
    setState(() {
      g = v;
      busy = false;
      if (!_vsDecided) {
        _vsDecided = true;
        final ts0 = (v['ts0'] as num?)?.toInt() ?? 0;
        // شاشة VS تظهر فقط في بداية المباراة
        _vs = ts0 > 0 && nowMs() - ts0 < 9000;
        if (_vs) {
          Future<void>.delayed(const Duration(milliseconds: 3600), () {
            if (mounted) setState(() => _vs = false);
          });
        }
      }
    });
    _chatOnce();
    _startPresence();
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
    _ps?.cancel();
    _tick?.cancel();
    _hb?.cancel();
    _c.dispose();
    if (isPlayer) ref('chessP/${widget.cid}/$myUid').set(0).catchError((Object _) {});
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

  List<Color> get _pal {
    final mine = prefs.getInt('chess_pal');
    final i = (mine != null && mine >= 0) ? mine : ((g['bc'] as num?)?.toInt() ?? 0);
    return kChessPalettes[i.clamp(0, kChessPalettes.length - 1)];
  }

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
          for (final e in const [['q', 'وزير'], ['r', 'قلعة'], ['b', 'فيل'], ['n', 'حصان']])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, e[0]),
              child: Row(children: [SizedBox(width: 34, height: 34, child: CustomPaint(painter: ChessPiece(e[0], !iAmBlack))), const SizedBox(width: 10), Text(e[1], style: const TextStyle(fontSize: 17))]),
            ),
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

  // ---------- أشرطة اللاعبين مع حلقة الوقت وإشارة ضعف الإنترنت ----------
  Widget _bar(String uid, String name, bool white, bool turn) {
    final mt = ((g['mt'] as num?)?.toInt() ?? 60) * 1000;
    final active = turn && g['st'] == 'play';
    final rem = ((g['dl'] as num?)?.toInt() ?? 0) - nowMs();
    final frac = (rem / mt).clamp(0.0, 1.0).toDouble();
    final secs = (rem / 1000).ceil().clamp(0, 999);
    final pv = pres[uid];
    final p = pv is num ? pv.toInt() : -1;
    final isOpp = uid != myUid;
    int age = 0;
    if (p == 0) {
      age = 999999;
    } else if (p > 0) {
      age = nowMs() - p;
    }
    final weak = isOpp && g['st'] == 'play' && p >= 0 && (p == 0 || age > 25000);
    final dead = weak && (p == 0 || age > 60000);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: active ? const Color(0xFF16240F) : Colors.transparent, border: const Border(bottom: BorderSide(color: Colors.white12))),
      child: Row(children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(size: const Size(48, 48), painter: _Ring(frac, active)),
            ClipOval(child: SizedBox(width: 36, height: 36, child: UserAvatar(uid, size: 36))),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            Row(children: [
              SizedBox(width: 16, height: 16, child: CustomPaint(painter: ChessPiece('k', white))),
              const SizedBox(width: 4),
              Text(white ? 'أبيض' : 'أسود', style: const TextStyle(fontSize: 12, color: Colors.white70)),
              if (weak) ...[
                const SizedBox(width: 8),
                Icon(Icons.signal_wifi_connected_no_internet_4, size: 15, color: dead ? kRed : Colors.amber),
                const SizedBox(width: 3),
                Text(dead ? 'منقطع منذ دقيقة' : 'إنترنت ضعيف', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: dead ? kRed : Colors.amber)),
              ],
            ]),
          ]),
        ),
        if (active) Text('$secs', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: secs <= 10 ? kRed : Colors.white)),
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
    final pal = _pal;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (c, cs) {
        final sz = cs.maxWidth / 8;
        return Stack(children: [
          for (var vi = 0; vi < 64; vi++)
            Builder(builder: (_) {
              final r = vi >> 3, f = vi & 7;
              final i = flip ? (7 - r) * 8 + (7 - f) : vi;
              final p = b[i];
              final dark = ((i >> 3) + (i & 7)) % 2 == 1;
              final name = _nm(i);
              var bg = dark ? pal[1] : pal[0];
              if (last.length == 4 && (name == last.substring(0, 2) || name == last.substring(2, 4))) bg = Color.alphaBlend(const Color(0x88FFEB3B), bg);
              if (i == sel) bg = const Color(0xFFFFD54A);
              if (inCheck && ((turnW && p == 'K') || (!turnW && p == 'k'))) bg = const Color(0xFFE53935);
              final white = p != '.' && p.toUpperCase() == p;
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
                      if (legalTargets.contains(name)) Container(width: sz * (p == '.' ? .3 : .9), height: sz * (p == '.' ? .3 : .9), decoration: BoxDecoration(shape: BoxShape.circle, color: p == '.' ? Colors.black26 : null, border: p == '.' ? null : Border.all(color: Colors.black38, width: 3))),
                      if (p != '.') SizedBox(width: sz * .9, height: sz * .9, child: CustomPaint(painter: ChessPiece(p.toLowerCase(), white))),
                      if (f == 0) Positioned(left: 2, top: 1, child: Text('${8 - (i >> 3)}', style: TextStyle(fontSize: sz * .2, color: dark ? pal[0] : pal[1], fontWeight: FontWeight.w800))),
                      if (r == 7) Positioned(right: 2, bottom: 0, child: Text('abcdefgh'[i & 7], style: TextStyle(fontSize: sz * .2, color: dark ? pal[0] : pal[1], fontWeight: FontWeight.w800))),
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

  void _palSheet() {
    showAppSheet<void>(context, (sc) => [
          const Text('لون الطاولة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
            for (var i = 0; i < kChessPalettes.length; i++)
              GestureDetector(
                onTap: () {
                  prefs.setInt('chess_pal', i);
                  Navigator.of(sc).pop();
                  setState(() {});
                },
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 56, height: 56, child: GridView.count(crossAxisCount: 2, physics: const NeverScrollableScrollPhysics(), children: [for (var k = 0; k < 4; k++) ColoredBox(color: (k == 0 || k == 3) ? kChessPalettes[i][0] : kChessPalettes[i][1])]))),
                  const SizedBox(height: 3),
                  Text(kChessPaletteNames[i], style: const TextStyle(fontSize: 11)),
                ]),
              ),
          ]),
        ]);
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

  Widget _vsOverlay(String wu, String wn, String bu, String bn) {
    return AnimatedOpacity(
      opacity: _vs ? 1 : 0,
      duration: const Duration(milliseconds: 500),
      child: IgnorePointer(
        ignoring: !_vs,
        child: Container(
          color: const Color(0xF2080A12),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: .6, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (c, k, _) => Transform.scale(
                scale: k,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [ClipOval(child: SizedBox(width: 92, height: 92, child: UserAvatar(wu, size: 92))), const SizedBox(height: 8), Text(wn, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 4), SizedBox(width: 34, height: 34, child: CustomPaint(painter: const ChessPiece('n', true)))])),
                  const Text('VS', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Color(0xFFFFD54A), shadows: [Shadow(color: Colors.orange, blurRadius: 18)])),
                  Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [ClipOval(child: SizedBox(width: 92, height: 92, child: UserAvatar(bu, size: 92))), const SizedBox(height: 8), Text(bn, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 4), SizedBox(width: 34, height: 34, child: CustomPaint(painter: const ChessPiece('r', false)))])),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = g['st'] == 'done';
    final wTurn = g['turn'] == 'w';
    final wu = (g['white'] ?? '').toString(), bu = (g['black'] ?? '').toString();
    final wn = (g['wn'] ?? '').toString(), bn = (g['bn'] ?? '').toString();
    final topIsBlack = !iAmBlack;
    String banner = '';
    if (done) {
      final res = g['res'];
      banner = res == 'w' ? '🏆 فاز $wn (أبيض) — ${g['why'] ?? ''}' : res == 'b' ? '🏆 فاز $bn (أسود) — ${g['why'] ?? ''}' : res == 'd' ? '🤝 تعادل — ${g['why'] ?? ''}' : 'أُلغيت المباراة';
    } else if (g['chk'] == true) {
      banner = '⚠️ كش ملك!';
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('الشطرنج'),
        actions: [
          if (((g['eyes'] as num?)?.toInt() ?? 0) > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Center(child: Text('👁 ${g['eyes']}', style: const TextStyle(fontWeight: FontWeight.w900)))),
          IconButton(onPressed: _palSheet, icon: const Icon(Icons.palette_outlined)),
          if (isPlayer && !done) TextButton(onPressed: _resign, child: const Text('انسحاب', style: TextStyle(color: kRed, fontWeight: FontWeight.w900))),
        ],
      ),
      body: g.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              SafeArea(
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
              Positioned.fill(child: _vsOverlay(wu, wn, bu, bn)),
            ]),
    );
  }
}
