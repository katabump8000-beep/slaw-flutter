import 'devtools2.dart';
import 'viewer.dart';
import 'solo.dart';
import 'servertime.dart';
import 'unread.dart';
import 'visuals.dart';
import 'shop.dart' show ShopScreen;
import 'stickers.dart';
import 'vip.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as im;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'ai.dart';
import 'aljesi.dart';
import 'app_state.dart';
import 'bell.dart';
import 'notif.dart';
import 'core.dart';
import 'crop.dart';
import 'data.dart';
import 'entrance.dart';
import 'bets.dart';
import 'events.dart';
import 'extras.dart';
import 'home.dart';
import 'info.dart';
import 'media.dart';
import 'msgstyle.dart';
import 'profile.dart';
import 'reports.dart';
import 'sfx.dart';
import 'tally.dart';
import 'war.dart';
import 'widgets.dart';

Uint8List? dataUrlBytes(String d) {
  try {
    final i = d.indexOf(',');
    if (i < 0) return null;
    return base64Decode(d.substring(i + 1));
  } catch (_) {
    return null;
  }
}

final Map<String, Future<String>> _stk = {};
Future<String> stickerData(String sid) {
  final c = prefs.getString('st_$sid');
  if (c != null && c.isNotEmpty) return Future<String>.value(c);
  return _stk.putIfAbsent(sid, () async {
    try {
      final d = (await ref('stickers/$sid/d').get()).value?.toString() ?? '';
      if (d.isNotEmpty) prefs.setString('st_$sid', d);
      return d;
    } catch (_) {
      return '';
    }
  });
}

class ChatScreen extends StatefulWidget {
  final String gid;
  final String focusMid;
  const ChatScreen({super.key, required this.gid, this.focusMid = ''});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  String get gid => widget.gid;
  final Map<String, Map<String, dynamic>> msgs = {};
  final Map<String, GlobalKey> keys = {};
  final ScrollController scroll = ScrollController();
  final TextEditingController ctrl = TextEditingController();
  final List<StreamSubscription<DatabaseEvent>> subs = [];
  Map<String, dynamic> admins = {};
  Map<String, dynamic> bios = {};
  bool locked = false;
  bool hasMore = true;
  bool boostOn = false;
  bool recording = false;
  String status = '';
  int muteUntil = 0;
  String oldest = '';
  final Set<String> pendingSeen = <String>{};
  final Set<String> doneSeen = <String>{};
  Timer? seenTimer;
  Timer? recTimer;
  Timer? recTick;
  StreamSubscription<Amplitude>? _ampSub;
  bool recPaused = false;
  int recSecs = 0;
  Uint8List? recBase; // مسودة محفوظة نكمل عليها
  int recBaseSecs = 0;
  final List<double> recLevels = <double>[];
  final AudioRecorder rec = AudioRecorder();
  Map<String, String>? nameIdx;
  final Map<String, Uint8List> imgCache = {};
  final Map<String, int> evEnds = {};
  final Map<String, String> _eidOf = {};
  Timer? _evTimer;
  int _lockUntil = 0;
  bool _evLive = false;
  bool _offline = false;
  Timer? _offT;
  int _srvScore = 0;
  Timer? _expTimer;
  final Set<String> _warHidden = {};
  String _jumpId = '';
  String _hlId = '';
  bool _live = false;
  final Set<String> _fresh = <String>{};
  Timer? _hlT;
  List<String> _mentionMids = <String>[];
  int _lastMention = 0;
  int _mentionRun = 0;
  final Map<String, List<int>> _myScore = {}; // eid -> [نقاطي, وقت التحديث]

  String get kind => groupKind(gid);
  bool get visitor => memCache[gid] == 'v';
  bool get isStaff => Session.isDev || admins[myUid] == true;
  bool get canWrite => Session.isDev || ((kind == 'main' || kind == 'adm') && (!locked || isStaff));
  bool get muted => muteUntil > nowMs();

  @override
  void initState() {
    super.initState();
    markGroupRead(gid);
    openChatGid = gid;
    // نحفظ الرسائل التي ذُكرت فيها قبل مسح الإشعارات: يظهر زر @ صغير للانتقال إليها
    final mm = BellService.items.values.where((n) => (n.t == 'men' || n.t == 'all' || n.t == 'rep') && n.g == gid && n.mid.isNotEmpty).toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));
    _mentionMids = mm.map((n) => n.mid).toList();
    BellService.clearMentions(gid);
    locked = groupsCache[gid]?['locked'] == true;
    final q = ref('messages/$gid').orderByKey().limitToLast(30);
    subs.add(q.onChildAdded.listen((e) => _put(e.snapshot), onError: (_) {}));
    subs.add(q.onChildChanged.listen((e) => _put(e.snapshot), onError: (_) {}));
    subs.add(q.onChildRemoved.listen((e) {
      final k = e.snapshot.key;
      if (k != null && mounted) setState(() => msgs.remove(k));
    }, onError: (_) {}));
    subs.add(ref('groupAdmins/$gid').onValue.listen((e) {
      final v = e.snapshot.value;
      if (mounted) setState(() => admins = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{});
    }, onError: (_) {}));
    subs.add(ref('groups/$gid/locked').onValue.listen((e) {
      if (mounted) setState(() => locked = e.snapshot.value == true);
    }, onError: (_) {}));
    subs.add(ref('groupBios/$gid').onValue.listen((e) {
      final v = e.snapshot.value;
      if (mounted) setState(() => bios = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{});
    }, onError: (_) {}));
    subs.add(ref('groupStatus/$gid/t').onValue.listen((e) {
      if (mounted) setState(() => status = e.snapshot.value?.toString() ?? '');
    }, onError: (_) {}));
    subs.add(ref('evScore/$gid/$myUid/n').onValue.listen((e) {
      final v = e.snapshot.value;
      if (mounted) setState(() => _srvScore = v is num ? v.toInt() : 0);
    }, onError: (_) {}));
    _names(); // تحميل مسبق لأسماء الأعضاء: قائمة @ تظهر فوراً
    subs.add(FirebaseDatabase.instance.ref('.info/connected').onValue.listen((e) {
      final on = e.snapshot.value == true;
      _offT?.cancel();
      if (on) {
        if (_offline && mounted) setState(() => _offline = false);
      } else {
        _offT = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _offline = true);
        });
      }
    }, onError: (_) {}));
    subs.add(ref('evLive/$gid').onValue.listen((e) {
      _evLive = e.snapshot.value != null;
    }, onError: (_) {}));
    subs.add(ref('evLock/$gid/until').onValue.listen((e) {
      final v = e.snapshot.value;
      _lockUntil = v is num ? v.toInt() : 0;
    }, onError: (_) {}));
    subs.add(ref('evEnd/$gid').onValue.listen((e) {
      final v = e.snapshot.value;
      evEnds.clear();
      if (v is Map) {
        v.forEach((k, x) {
          if (x is num) evEnds[k.toString()] = x.toInt();
        });
      }
      _evTimer?.cancel();
      // أعد الرسم عند حلول وقت اختفاء أقرب فعالية منتهية
      final now = nowMs();
      final next = evEnds.values.map((t) => t + 180000 - now).where((d) => d > 0).fold<int>(1 << 30, (a, b) => b < a ? b : a);
      if (next < (1 << 30)) _evTimer = Timer(Duration(milliseconds: next + 400), () => mounted ? setState(() {}) : null);
      if (mounted) setState(() {});
    }, onError: (_) {}));
    subs.add(ref('mod/$myUid/until').onValue.listen((e) {
      final v = e.snapshot.value;
      if (mounted) setState(() => muteUntil = v is num ? v.toInt() : 0);
    }, onError: (_) {}));
    subs.add(ref('entrance/$gid').onValue.listen((e) {
      final v = e.snapshot.value;
      if (shouldShowEntrance(v, gid) && mounted && v is Map) {
        Navigator.of(context).push(PageRouteBuilder<void>(opaque: true, pageBuilder: (_, __, ___) => EntranceScreen(emperor: v['t'] == 'emp', name: (v['n'] ?? '').toString())));
      }
    }, onError: (_) {}));
    ref('boost/$myUid').get().then((s) {
      if (mounted) boostOn = s.exists;
    }).catchError((_) {});
    _expTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && (_eidOf.isNotEmpty || _myScore.isNotEmpty)) setState(() {});
    });
    Future<void>.delayed(const Duration(milliseconds: 2500), () => _live = true);
    _welcome();
    _entranceTriggers();
    if (widget.focusMid.isNotEmpty) Future<void>.delayed(const Duration(milliseconds: 900), () => _focus(0));
  }

  void _entranceTriggers() {
    final now = nowMs();
    if (Session.isEmp && (prefs.getBool('emp_enter') ?? false)) {
      prefs.setBool('emp_enter', false);
      announceEntrance(gid, 'emp');
    } else if (Session.isDev && !Session.isEmp) {
      final last = prefs.getInt('ls_$gid') ?? 0;
      if (last > 0 && now - last > 90 * 60000) announceEntrance(gid, 'dev');
    }
    prefs.setInt('ls_$gid', now);
  }

  @override
  void dispose() {
    _evTimer?.cancel();
    _expTimer?.cancel();
    _hlT?.cancel();
    if (openChatGid == gid) openChatGid = '';
    BellService.clearMentions(gid);
    prefs.setInt('ls_$gid', nowMs());
    for (final s in subs) {
      s.cancel();
    }
    seenTimer?.cancel();
    recTimer?.cancel();
    recTick?.cancel();
    _ampSub?.cancel();
    if (recording) {
      rec.cancel().catchError((Object _) {});
      Sfx.unblock('rec');
    }
    _flush();
    rec.dispose();
    scroll.dispose();
    ctrl.dispose();
    markGroupRead(gid);
    super.dispose();
  }

  void _put(DataSnapshot s) {
    final k = s.key;
    final v = s.value;
    if (k == null || v is! Map || !mounted) return;
    final m = Map<String, dynamic>.from(v);
    _checkWin(k, m);
    _trackScore(m);
    if (_live && !msgs.containsKey(k) && (m['type'] ?? 'text') != 'sys') {
      final mine = (m['from'] ?? '').toString() == myUid;
      Sfx.msg(mine);
      if (_fresh.length > 300) _fresh.clear();
      _fresh.add(k);
    }
    setState(() {
      msgs[k] = m;
      if (oldest.isEmpty || k.compareTo(oldest) < 0) oldest = k;
    });
  }

  /// رسائل الفعالية (التي تحمل eid) تختفي بعد 3 دقائق من انتهاء الفعالية
  bool _hiddenEv(String id, Map<String, dynamic> m) {
    if (m['type'] != 'sys' || m['k'] != 'bot') return false;
    final d = (m['d'] ?? '').toString();
    if (!d.contains('"eid"')) return false;
    var eid = _eidOf[id];
    if (eid == null) {
      try {
        final j = jsonDecode(d);
        eid = j is Map ? (j['eid'] ?? '').toString() : '';
      } catch (_) {
        eid = '';
      }
      _eidOf[id] = eid;
    }
    final end = evEnds[eid];
    final now = nowMs();
    if (end == null) {
      // فعالية عالقة (أُغلق جهاز مشغّلها قبل أن تنتهي): تختفي بعد 25 دقيقة بدل أن تبقى معلّقة
      final ts = (m['ts'] as num?)?.toInt() ?? 0;
      return ts > 0 && now - ts > 25 * 60000;
    }
    return now > end + 180000;
  }

  /// نسبة تقدّم اللاعب (n/10) تظهر له وحده فوق صندوق الكتابة أثناء الفعالية
  void _trackScore(Map<String, dynamic> m) {
    if (m['k'] != 'bot') return;
    final tx = (m['text'] ?? '').toString();
    final mt = RegExp(r'✅ (.+?) هو من أجاب — (\d+)/10').firstMatch(tx);
    if (mt == null) return;
    if (mt.group(1)!.trim() != Session.me.name.trim()) return;
    var eid = '';
    try {
      final j = jsonDecode((m['d'] ?? '{}').toString());
      if (j is Map) eid = (j['eid'] ?? '').toString();
    } catch (_) {}
    if (eid.isEmpty) return;
    _myScore[eid] = [int.tryParse(mt.group(2)!) ?? 0, nowMs()];
  }

  Widget _scoreChip() {
    final now = nowMs();
    if (_offline) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: const Color(0xFF7A1F1F),
        child: const Row(children: [
          Text('⚠️', style: TextStyle(fontSize: 20)),
          SizedBox(width: 10),
          Expanded(child: Text('لا يتوفر لديك اتصال بالانترنت!', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
        ]),
      );
    }
    if (_evLive && _srvScore > 0) {
      final s2 = _srvScore.clamp(0, 10);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        color: accentA(context, .12),
        child: Row(children: [
          const Text('🎯', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text('تقدّمك في الفعالية: $s2/10', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: s2 / 10, minHeight: 6, backgroundColor: Colors.white12, color: context.accent))),
        ]),
      );
    }
    for (final e in _myScore.entries) {
      if (evEnds[e.key] != null || now - e.value[1] > 25 * 60000) continue;
      final sc = e.value[0].clamp(0, 10);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        color: accentA(context, .12),
        child: Row(children: [
          const Text('🎯', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text('تقدّمك في الفعالية: $sc/10', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: sc / 10, minHeight: 6, backgroundColor: Colors.white12, color: context.accent))),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  void _checkWin(String id, Map<String, dynamic> m) {
    if (m['k'] != 'bot' || m['d'] is! String) return;
    final ts = (m['ts'] as num?)?.toInt() ?? 0;
    if (nowMs() - ts > 300000) return;
    try {
      final j = jsonDecode(m['d'] as String);
      if (j is Map && j['win'] == myUid && !(prefs.getBool('win_$id') ?? false)) {
        prefs.setBool('win_$id', true);
        final amt = j['amt'] is num ? (j['amt'] as num).toInt().clamp(0, 100000) : 0;
        if (amt > 0) creditChunks(amt);
        ref('wins/$myUid').get().then((s) {
          final n = s.value is num ? (s.value as num).toInt() : 0;
          ref('wins/$myUid').set(n + 1);
        });
      }
      if (j is Map && j['rf'] is Map && (j['rf'] as Map)[myUid] is num && !(prefs.getBool('rf_$id') ?? false)) {
        prefs.setBool('rf_$id', true);
        final a = ((j['rf'] as Map)[myUid] as num).toInt().clamp(0, 100000);
        if (a > 0) creditChunks(a);
      }
    } catch (_) {}
  }

  /// خلفية سوداء مظللة لمدة 3 ثوانٍ على الرسالة التي انتقلنا إليها
  void _flash(String id) {
    if (!mounted) return;
    _hlT?.cancel();
    setState(() => _hlId = id);
    _hlT = Timer(const Duration(seconds: 4), () {
      if (mounted && _hlId == id) setState(() => _hlId = '');
    });
  }

  /// الانتقال إلى الرسالة المردود عليها عند الضغط على اقتباس الرد
  Future<void> _jumpTo(String id, [int tries = 0]) async {
    if (!mounted || id.isEmpty) return;
    if (tries == 0) setState(() => _jumpId = id);
    final ctx = keys[id]?.currentContext;
    if (msgs.containsKey(id) && ctx != null) {
      await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), alignment: .4);
      _flash(id);
      return;
    }
    if (tries >= 6) {
      toast('تعذر الوصول للرسالة الأصلية');
      return;
    }
    if (!msgs.containsKey(id)) {
      if (hasMore) {
        await _older();
      } else {
        toast('الرسالة الأصلية غير موجودة');
        return;
      }
    } else {
      final ks = _orderedKeys().reversed.toList();
      final i = ks.indexOf(id);
      if (i >= 0 && scroll.hasClients) {
        await scroll.animateTo((i * 110.0).clamp(0.0, scroll.position.maxScrollExtent), duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    }
    Future<void>.delayed(const Duration(milliseconds: 450), () => _jumpTo(id, tries + 1));
  }

  Future<void> _focus(int tries) async {
    if (!mounted) return;
    final id = widget.focusMid;
    final ctx = keys[id]?.currentContext;
    if (msgs.containsKey(id) && ctx != null) {
      await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), alignment: .4);
      _flash(id);
      return;
    }
    if (tries < 4 && hasMore) {
      await _older();
      Future<void>.delayed(const Duration(milliseconds: 500), () => _focus(tries + 1));
    }
  }

  Future<void> _welcome() async {
    if (kind != 'main' || memCache[gid] != true) return;
    try {
      final s = await ref('welcomed/$gid/$myUid').get();
      if (s.exists) return;
      final name = Session.me.name;
      final pic = await charImage(name);
      final k = ref('messages/$gid').push().key!;
      final text = '╮─❖『 👑 ترحيب 』❖─╭\n\n'
          'أضــاءت مملكة 𝑭𝑰𝑹 بانضمامك إلينا!\n'
          'أهلًا وسهلًا بك في المكان الذي لا يعرف الملل، ولا يتوقف فيه الحماس. 🌟\n'
          'لقد أنرت المملكة بحضورك، ويسعدنا جدًا انضمامك إلى عائلتنا. 🤍\n\n'
          'آلَــلـقــــــب: $name\n'
          'آلَمِــــنـــــشــــن: @$name\n\n'
          'الدخول اجباري لهنا:\n'
          '╮──────────────╭\n'
          '📢 الإعــلانــات: تم اضافتك حيث يمكنك ان ترى من فاز ومن ترقى\n'
          '🛒 الــمــتــجــر: تم اضافتك حيث يحوي زر يمكنك من خلاله الشراء\n'
          '╯──────────────╰\n'
          '🌸 نتمنى لك قضاء أجمل الأوقات معنا، وندعوك للمشاركة والتفاعل باستمرار.\n\n'
          '╮──────────────╭\n'
          'تــوقــيــع:\n'
          '🍷 𝑭𝑰𝑹 亗 511🍂\n'
          '╯──────────────╰';
      await db.ref().update(<String, Object?>{
        'welcomed/$gid/$myUid': true,
        'messages/$gid/$k': <String, Object?>{
          'from': myUid, 'type': 'sys', 'k': 'welcome', 'text': text, 'ts': ServerValue.timestamp,
          if (pic != null) 'pic': pic,
        },
      });
    } catch (_) {}
  }

  // ---------- المشاهدة ----------
  void _queueSeen(String id, Map<String, dynamic> m) {
    final seen = m['seen'];
    if (seen is Map && seen.containsKey(myUid)) return;
    if (!doneSeen.add(id)) return;
    pendingSeen.add(id);
    seenTimer ??= Timer(const Duration(milliseconds: 1300), _flush);
  }

  Future<void> _flush() async {
    seenTimer = null;
    if (pendingSeen.isEmpty) return;
    final up = <String, Object?>{};
    for (final id in pendingSeen) {
      up['messages/$gid/$id/seen/$myUid'] = ServerValue.timestamp;
    }
    pendingSeen.clear();
    try {
      await db.ref().update(up);
    } catch (_) {}
  }

  // ---------- الإرسال ----------
  Map<String, String>? _reply;

  Future<void> _startReply(Map<String, dynamic> m, [String id = '']) async {
    final type = (m['type'] ?? 'text').toString();
    var t = '';
    if (type == 'sys') {
      var st = (m['text'] ?? '').toString().replaceAll(RegExp(r'[╮─❖『』╭╰]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if ((m['d'] ?? '').toString().contains('"bet"')) st = 'فعالية الرهانات 🎈';
      if (st.isEmpty) return;
      if (!mounted) return;
      setState(() => _reply = {'n': (m['k'] ?? '') == 'welcome' ? 'رسالة الترحيب' : 'ALJESI', 't': st.length > 100 ? st.substring(0, 100) : st, 'i': id});
      return;
    }
    if (type == 'text') {
      t = (m['text'] ?? '').toString();
    } else if (type == 'image') {
      final c = (m['cap'] ?? '').toString();
      t = c.isNotEmpty ? c : 'صورة';
    } else if (type == 'sticker') {
      t = 'ملصق';
    } else if (type == 'audio') {
      t = 'تسجيل صوتي';
    }
    if (t.isEmpty) return;
    final p = await prof((m['from'] ?? '').toString());
    if (!mounted) return;
    setState(() => _reply = {'n': p.name, 't': t.length > 100 ? t.substring(0, 100) : t, 'i': id});
  }

  Map<String, Object?> _base(String type) => <String, Object?>{
        'from': myUid,
        'type': type,
        'ts': ServerValue.timestamp,
        'color': (Session.isEmp && (prefs.getString('txtc') ?? '').isNotEmpty) ? prefs.getString('txtc')! : Session.me.color,
        if (visitor) 'vis': true,
        if (myMsgStyleCode() != null) 'ms': myMsgStyleCode(),
        if (_reply != null) 'rpn': _reply!['n'],
        if (_reply != null) 'rpt': _reply!['t'],
        if (_reply != null && (_reply!['i'] ?? '').isNotEmpty) 'rpi': _reply!['i'],
      };

  Future<String> _post(Map<String, Object?> m, {bool count = true}) async {
    final k = ref('messages/$gid').push().key!;
    final up = <String, Object?>{'messages/$gid/$k': m};
    if (kind == 'main' && count) {
      up['stats/$gid/$myUid'] = ServerValue.increment(boostOn ? 2 : 1);
      up['msgTotal/$myUid'] = ServerValue.increment(1);
    }
    await db.ref().update(up);
    if (mounted && _reply != null) setState(() => _reply = null);
    return k;
  }

  bool _gate() {
    if (muted) {
      toast('أنت مقيد من الشات — باقي ${leftText(muteUntil)}', bad: true);
      return false;
    }
    return true;
  }

  /// تطبيق العقوبة وعرض النتيجة (بطاقة تحذير للرتب العالية في أول مخالفة)
  Future<void> _punish(String kind, String lead) async {
    final r = await applyPunish(kind);
    if (!mounted) return;
    if (r.warn) {
      await showAppSheet<void>(context, (sc) => [
            const Text('⚠️ تحذير', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFFFFC857))),
            Text(r.text, textAlign: TextAlign.center, style: const TextStyle(height: 1.9, fontSize: 14.5)),
            AppButton('حسناً', onPressed: () => Navigator.of(sc).pop()),
          ]);
    } else {
      toast('$lead ${r.text}', bad: true);
    }
  }

  Future<void> _sendText() async {
    final t = ctrl.text.trim();
    if (t.isEmpty || !_gate()) return;
    if (_offline) {
      toast('لا يتوفر لديك اتصال بالانترنت!', bad: true);
      return;
    }
    if (_lockUntil > nowMs() && !Session.isDev) {
      toast('الشات مقفل لحظات بسبب بدء الفعالية 🔒', bad: true);
      return;
    }
    var lv = (_evLive && evSafeWord(t)) ? 0 : badLevel(t); // أثناء الفعالية: إجابة مثل «كلب» ليست مخالفة
    if (lv == 1 && Session.isDev) lv = 0; // الإمبراطور والمطورون مستثنون من عقوبة الشتم الخفيف
    if (lv > 0) {
      ctrl.clear();
      await _punish(lv == 2 ? 'severe' : 'mild', 'رسالة مخالفة!');
      return;
    }
    if (!Session.isDev && spamHit()) {
      ctrl.clear();
      await _punish('spam', 'تم رصد سبام.');
      return;
    }
    if (!Session.isDev && t.contains('@')) {
      final nowM = nowMs();
      // مسموح 5 رسائل منشن متتالية (كل واحدة خلال 30 ثانية من السابقة)، والسادسة تقييد
      _mentionRun = nowM - _lastMention < 30000 ? _mentionRun + 1 : 1;
      _lastMention = nowM;
      if (_mentionRun > 5) {
        _mentionRun = 0;
        ctrl.clear();
        await mentionLock();
        toast('تكرار المنشن! تم تقييدك من الشات 30 ثانية', bad: true);
        return;
      }
    }
    ctrl.clear();
    try {
      final m = _base('text');
      m['text'] = t;
      final k = await _post(m);
      _notifyMentions(k, t);
      _notifyAll(k, t);
      if (isCommandText(t) && mounted) await runCommand(context, gid, t);
    } catch (e) {
      ctrl.text = t;
      err(e);
    }
  }

  /// فحص الصورة بالذكاء الاصطناعي قبل الإرسال
  Future<bool> _clean(Uint8List bytes) async {
    final bad = await imageUnsafe(bytes);
    if (bad == true) {
      await _punish('image', 'تم رصد محتوى غير لائق.');
      return false;
    }
    return true;
  }

  Future<String?> _overlay(Uint8List b, String text, int pos, Color col) async {
    try {
      final codec = await ui.instantiateImageCodec(b);
      final fr = await codec.getNextFrame();
      final src = fr.image;
      final rc = ui.PictureRecorder();
      final cv = ui.Canvas(rc);
      cv.drawImage(src, Offset.zero, ui.Paint());
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: col, fontSize: src.width / 11, fontWeight: FontWeight.w900, shadows: const [Shadow(color: Colors.black, blurRadius: 8)])),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        maxLines: 3,
      )..layout(maxWidth: src.width * .9);
      final dy = pos == 0 ? src.height * .05 : (pos == 1 ? (src.height - tp.height) / 2 : src.height - tp.height - src.height * .05);
      tp.paint(cv, Offset((src.width - tp.width) / 2, dy));
      final out = await rc.endRecording().toImage(src.width, src.height);
      final bd = await out.toByteData(format: ui.ImageByteFormat.png);
      final decoded = im.decodePng(bd!.buffer.asUint8List());
      if (decoded == null) return null;
      var q = 82;
      List<int> jpg;
      do {
        jpg = im.encodeJpg(decoded, quality: q);
        q -= 12;
      } while (jpg.length * 4 / 3 > 55000 && q > 20);
      if (jpg.length * 4 / 3 > 58000) return null;
      return 'data:image/jpeg;base64,${base64Encode(jpg)}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendImage() async {
    if (!_gate()) return;
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null || !mounted) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      var d = await cropImage(context, bytes, out: const [900, 720, 560, 420, 320], limit: 55000, round: false, title: 'قص الصورة', ratio: 4 / 3);
      if (d == null || !mounted) return;
      final preview = dataUrlBytes(d);
      final tt = TextEditingController();
      final cc = TextEditingController();
      var pos = 2;
      var col = Colors.white;
      final r = await showAppSheet<Map<String, dynamic>>(context, (sc) => [
            StatefulBuilder(builder: (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('إرسال صورة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (preview != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(preview, height: 190, fit: BoxFit.cover)),
                  TextField(controller: tt, maxLength: 60, decoration: const InputDecoration(hintText: 'نص فوق الصورة (اختياري)', counterText: '')),
                  Row(children: [
                    for (final e in {0: 'أعلى', 1: 'وسط', 2: 'أسفل'}.entries)
                      Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text(e.value), selected: pos == e.key, onSelected: (_) => set(() => pos = e.key))),
                    const Spacer(),
                    for (final cl in [Colors.white, const Color(0xFFFFE066), const Color(0xFFFF5A4D), const Color(0xFF5DE0E6)])
                      GestureDetector(onTap: () => set(() => col = cl), child: Container(width: 26, height: 26, margin: const EdgeInsets.only(left: 6), decoration: BoxDecoration(shape: BoxShape.circle, color: cl, border: Border.all(color: col == cl ? kRed : Colors.transparent, width: 2)))),
                  ]),
                  TextField(controller: cc, maxLength: 200, minLines: 1, maxLines: 3, decoration: const InputDecoration(hintText: 'اكتب شرحاً للصورة (اختياري)')),
                  AppButton('إرسال', onPressed: () => Navigator.of(sc).pop(<String, dynamic>{'t': tt.text.trim(), 'p': pos, 'c': col, 'cap': cc.text.trim()})),
                ])),
          ]);
      if (r == null) return;
      if ((r['t'] as String).isNotEmpty && preview != null) {
        final o = await _overlay(preview, r['t'] as String, r['p'] as int, r['c'] as Color);
        if (o != null) d = o;
      }
      final finalBytes = dataUrlBytes(d);
      if (finalBytes != null && !await _clean(finalBytes)) return;
      final m = _base('image');
      m['img'] = d;
      final cap = r['cap'] as String;
      if (cap.isNotEmpty) m['cap'] = cap;
      final k = await _post(m);
      if (cap.contains('@')) _notifyMentions(k, cap);
    } catch (e) {
      err(e);
    }
  }

  // ---------- الملصقات ----------
  List<String> _recent() => (prefs.getString('rstk') ?? '').split(',').where((e) => e.isNotEmpty).toList();

  void _pushRecent(String sid) {
    final l = _recent()..remove(sid);
    l.insert(0, sid);
    prefs.setString('rstk', l.take(10).join(','));
  }

  Color _stkColor(int n) => n <= 25 ? const Color(0xFF4CE07A) : (n <= 50 ? const Color(0xFFFFD54A) : (n <= 75 ? const Color(0xFFE65100) : const Color(0xFFFF3B3B)));

  Future<void> _stickers() async {
    if (!_gate()) return;
    List<String> mine = [];
    try {
      final v = (await ref('myStickers/$myUid').get()).value;
      if (v is Map) mine = v.keys.map((e) => e.toString()).toList();
    } catch (_) {}
    if (!mounted) return;
    Future<void> sendSticker(String sid) async {
      try {
        final m = _base('sticker');
        m['sid'] = sid;
        await _post(m, count: false);
        _pushRecent(sid);
      } catch (e) {
        err(e);
      }
    }
    var delMode = false;
    final sel = <String>{};
    showAppSheet<void>(context, (sc) => [
          StatefulBuilder(
            builder: (c, set) {
              final rec = _recent().where((s) => mine.contains(s)).toList();
              Future<void> doDelete(List<String> ids) async {
                if (ids.isEmpty) return;
                try {
                  await db.ref().update(<String, Object?>{for (final s in ids) 'myStickers/$myUid/$s': null});
                  mine.removeWhere(ids.contains);
                  sel.clear();
                  delMode = false;
                  set(() {});
                  toast('تم الحذف ✅');
                } catch (e) {
                  err(e);
                }
              }

              Future<void> deleteAll() async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('هل انت واثق من حذفك كل الملصقات؟'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('لا')),
                      TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('نعم، احذف الكل')),
                    ],
                  ),
                );
                if (ok == true) await doDelete(List<String>.from(mine));
              }

              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Text('الملصقات', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: _stkColor(mine.length).withAlpha(40), borderRadius: BorderRadius.circular(10), border: Border.all(color: _stkColor(mine.length))),
                    child: Text('${mine.length}/100', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _stkColor(mine.length))),
                  ),
                  IconButton(
                    onPressed: () => set(() {
                      delMode = !delMode;
                      sel.clear();
                    }),
                    icon: Icon(delMode ? Icons.close : Icons.delete_outline, color: const Color(0xFFFF4D4D)),
                  ),
                ]),
                if (delMode) ...[
                  InkWell(
                    onTap: deleteAll,
                    child: const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Row(children: [Icon(Icons.check_box_outline_blank, size: 20, color: Color(0xFFFF4D4D)), SizedBox(width: 8), Text('حذف كل الملصقات', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFFF4D4D)))])),
                  ),
                  Row(children: [
                    Expanded(child: AppButton('حذف (${sel.length})', kind: 'r', compact: true, onPressed: sel.isEmpty ? null : () => doDelete(sel.toList()))),
                    const SizedBox(width: 8),
                    Expanded(child: AppButton('الغاء', kind: 'g', compact: true, onPressed: () => set(() {
                          delMode = false;
                          sel.clear();
                        }))),
                  ]),
                  const SizedBox(height: 8),
                ],
                if (rec.isNotEmpty && !delMode)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(border: Border.all(color: kLine), borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('آخر 10 ملصقات استخدمتها', style: TextStyle(color: kMu, fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final sid in rec)
                          GestureDetector(
                            onTap: () {
                              Navigator.of(sc).pop();
                              sendSticker(sid);
                            },
                            child: _StickerImg(sid: sid, size: 60),
                          ),
                      ]),
                    ]),
                  ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (!delMode)
                    GestureDetector(
                      onTap: () {
                        if (mine.length >= 100) {
                          toast('وصلت للحد الأقصى: 100 ملصق', bad: true);
                          return;
                        }
                        Navigator.of(sc).pop();
                        _newSticker();
                      },
                      child: Container(width: 76, height: 76, decoration: BoxDecoration(border: Border.all(color: kLine, width: 2), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.add, color: context.accent2, size: 30)),
                    ),
                  for (final sid in mine)
                    GestureDetector(
                      onTap: () {
                        if (delMode) {
                          set(() => sel.contains(sid) ? sel.remove(sid) : sel.add(sid));
                          return;
                        }
                        Navigator.of(sc).pop();
                        sendSticker(sid);
                      },
                      child: Stack(children: [
                        _StickerImg(sid: sid, size: 76),
                        if (delMode)
                          Positioned(
                            top: 2,
                            left: 2,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(color: sel.contains(sid) ? const Color(0xFFFF4D4D) : const Color(0x99000000), borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.white, width: 1.5)),
                              child: sel.contains(sid) ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                            ),
                          ),
                      ]),
                    ),
                ]),
              ]);
            },
          ),
        ]);
  }

  Future<void> _newSticker() async {
    try {
      final cnt = (await ref('myStickers/$myUid').get()).children.length;
      if (cnt >= 100) {
        toast('وصلت للحد الأقصى: 100 ملصق', bad: true);
        return;
      }
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null || !mounted) return;
      final d = await cropImage(context, await x.readAsBytes(), out: const [256, 200, 150], limit: 24000, round: false, title: 'قص الملصق', ratio: 1);
      if (d == null) return;
      final b = dataUrlBytes(d);
      if (b != null && !await _clean(b)) return;
      final sid = ref('stickers').push().key!;
      await db.ref().update(<String, Object?>{'stickers/$sid': <String, Object?>{'u': myUid, 'd': d}, 'myStickers/$myUid/$sid': true});
      prefs.setString('st_$sid', d);
      toast('تم إنشاء الملصق ✅');
    } catch (e) {
      err(e);
    }
  }

  // ---------- الصوت (للذكور فقط) ----------
  // تسجيل بمؤثرات: إيقاف مؤقت (أزرق) | إرسال (أخضر) | إلغاء (أحمر) | حفظ كمسودة (أصفر).
  // صيغة ADTS تسمح بدمج المسودة مع الجزء الجديد بالتسلسل البسيط.
  static const int _recMax = 30;

  Future<File> _draftFile() async => File('${(await getApplicationDocumentsDirectory()).path}/voice_draft.m4a');

  Future<void> _toggleRec() async {
    if (!_gate() || recording) return;
    try {
      if (!await rec.hasPermission()) {
        toast('فعّل إذن الميكروفون', bad: true);
        return;
      }
      recBase = null;
      recBaseSecs = 0;
      final f = await _draftFile();
      final ds = prefs.getInt('vdraft_s') ?? 0;
      if (await f.exists() && ds > 0) {
        final go = await showDialog<String>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('هل تريد اكمال صوت المحفوظ؟'),
            content: Text('لديك تسجيل محفوظ مدته $ds ثانية.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, 'new'), child: const Text('تسجيل جديد')),
              TextButton(onPressed: () => Navigator.pop(d, 'send'), child: const Text('إرسال المحفوظ')),
            ],
          ),
        );
        if (go == null) return;
        if (go == 'send') {
          final bytes = await f.readAsBytes();
          final dd = 'data:audio/mp4;base64,${base64Encode(bytes)}';
          if (dd.length > 140000) {
            toast('التسجيل طويل جداً', bad: true);
            return;
          }
          final m = _base('audio');
          m['au'] = dd;
          m['dur'] = max(1, ds);
          await _post(m, count: false);
          await f.delete();
          prefs.setInt('vdraft_s', 0);
          return;
        }
        await f.delete();
        prefs.setInt('vdraft_s', 0);
      }
      final dir = (await getTemporaryDirectory()).path;
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 24000, sampleRate: 16000, numChannels: 1), path: '$dir/v_${DateTime.now().millisecondsSinceEpoch}.m4a');
      Sfx.block('rec');
      recSecs = recBaseSecs;
      recPaused = false;
      recLevels.clear();
      setState(() => recording = true);
      _ampSub?.cancel();
      _ampSub = rec.onAmplitudeChanged(const Duration(milliseconds: 90)).listen((a) {
        if (recPaused) return;
        recLevels.add(((a.current + 45) / 45).clamp(0.06, 1.0).toDouble());
        if (recLevels.length > 34) recLevels.removeAt(0);
        if (mounted) setState(() {});
      });
      recTick?.cancel();
      recTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (recPaused || !recording) return;
        recSecs++;
        if (recSecs >= _recMax) {
          _recSend();
        } else if (mounted) {
          setState(() {});
        }
      });
    } catch (e) {
      _recEnd();
      err(e);
    }
  }

  void _recEnd() {
    recTick?.cancel();
    _ampSub?.cancel();
    Sfx.unblock('rec');
    if (mounted) setState(() => recording = false);
  }

  Future<Uint8List?> _recCollect() async {
    final p = await rec.stop();
    final bb = BytesBuilder();
    if (recBase != null) bb.add(recBase!);
    if (p != null) bb.add(await File(p).readAsBytes());
    final out = bb.takeBytes();
    return out.isEmpty ? null : out;
  }

  Future<void> _recPauseResume() async {
    try {
      if (recPaused) {
        await rec.resume();
      } else {
        await rec.pause();
      }
      setState(() => recPaused = !recPaused);
    } catch (e) {
      err(e);
    }
  }

  Future<void> _recCancel() async {
    try {
      await rec.cancel();
    } catch (_) {}
    recBase = null;
    _recEnd();
  }

  Future<void> _recDraft() async {
    try {
      final b = await _recCollect();
      _recEnd();
      if (b == null) return;
      final f = await _draftFile();
      await f.writeAsBytes(b, flush: true);
      prefs.setInt('vdraft_s', max(1, recSecs));
      recBase = null;
      toast('تم حفظ الصوت كمسودة 💾');
    } catch (e) {
      _recEnd();
      err(e);
    }
  }

  Future<void> _recSend() async {
    if (!recording) return;
    try {
      final b = await _recCollect();
      _recEnd();
      if (b == null) return;
      final d = 'data:audio/mp4;base64,${base64Encode(b)}';
      if (d.length > 140000) {
        toast('التسجيل طويل جداً', bad: true);
        return;
      }
      final m = _base('audio');
      m['au'] = d;
      m['dur'] = min(_recMax, max(1, recSecs));
      await _post(m, count: false);
      recBase = null;
      final f = await _draftFile();
      if (await f.exists()) await f.delete();
      prefs.setInt('vdraft_s', 0);
    } catch (e) {
      _recEnd();
      err(e);
    }
  }

  Widget _recBtn(IconData ic, Color c, String label, VoidCallback f) => Expanded(
        child: GestureDetector(
          onTap: f,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c, boxShadow: [BoxShadow(color: c.withAlpha(150), blurRadius: 14, spreadRadius: 1)]),
              child: Icon(ic, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  Widget _recPanel() {
    final mm = (recSecs ~/ 60).toString().padLeft(2, '0');
    final ss = (recSecs % 60).toString().padLeft(2, '0');
    final t = DateTime.now().millisecondsSinceEpoch / 600.0;
    return Container(
      color: kBg2,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.fiber_manual_record, size: 14, color: recPaused ? Colors.amber : kRed),
            const SizedBox(width: 6),
            Text(recPaused ? 'متوقف مؤقتاً  $mm:$ss' : 'جارٍ التسجيل  $mm:$ss', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
              for (var i = 0; i < 34; i++)
                Builder(builder: (_) {
                  final idx = i - (34 - recLevels.length);
                  final lv = idx >= 0 ? recLevels[idx] : .06;
                  final col = HSVColor.fromAHSV(1, ((i * 11) + t * 40) % 360, .75, 1).toColor();
                  return Container(
                    width: 5,
                    height: 4 + lv * 40,
                    margin: const EdgeInsets.symmetric(horizontal: 1.2),
                    decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(3), boxShadow: [BoxShadow(color: col.withAlpha(110), blurRadius: 6)]),
                  );
                }),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _recBtn(recPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, const Color(0xFF2F80ED), recPaused ? 'استئناف' : 'إيقاف مؤقت', _recPauseResume),
            _recBtn(Icons.send_rounded, const Color(0xFF2EBB5E), 'إرسال', _recSend),
            _recBtn(Icons.close_rounded, const Color(0xFFE53935), 'إلغاء', _recCancel),
            _recBtn(Icons.bookmark_rounded, const Color(0xFFF2C21A), 'حفظ مسودة', _recDraft),
          ]),
        ]),
      ),
    );
  }

  // ---------- الإشارات @ ----------
  Future<Map<String, String>> _names() async {
    final cached = nameIdx;
    if (cached != null) return cached;
    final out = <String, String>{};
    try {
      final s = await ref('members/$gid').get();
      final v = s.value;
      if (v is Map) {
        final ids = v.keys.map((e) => e.toString()).where((u) => u != myUid).take(300).toList();
        final ps = await Future.wait(ids.map(prof));
        for (var i = 0; i < ids.length; i++) {
          out[ps[i].name] = ids[i];
        }
      }
    } catch (_) {}
    nameIdx = out;
    return out;
  }

  static final RegExp _allRe = RegExp(r'@(الكل|all)', caseSensitive: false);

  /// @الكل: إشعار فوري لكل أعضاء القروب (للمشرفين والمطورين والإمبراطور)
  Future<void> _notifyAll(String mid, String text) async {
    if (!_allRe.hasMatch(text)) return;
    if (!Session.isDev && admins[myUid] == null) {
      toast('الأمر @الكل للمشرفين والمطورين والإمبراطور فقط');
      return;
    }
    try {
      final v = (await ref('members/$gid').get()).value;
      if (v is! Map) return;
      final gname = groupName(gid).length > 40 ? groupName(gid).substring(0, 40) : groupName(gid);
      final tx = text.length > 90 ? text.substring(0, 90) : text;
      final ids = v.entries.where((e) => e.value == true && e.key.toString() != myUid).map((e) => e.key.toString()).toList();
      for (var i = 0; i < ids.length; i += 150) {
        final up = <String, Object?>{};
        for (final u in ids.skip(i).take(150)) {
          final k = ref('notifs/$u').push().key!;
          up['notifs/$u/$k'] = <String, Object?>{'t': 'all', 'from': myUid, 'g': gid, 'm': gname, 'mid': mid, 'tx': tx, 'ts': ServerValue.timestamp};
        }
        await db.ref().update(up);
      }
      toast('تم إرسال إشعار للجميع 📣 (${ids.length})');
    } catch (e) {
      err(e);
    }
  }

  Future<void> _notifyMentions(String mid, String text) async {
    if (!text.contains('@')) return;
    final idx = await _names();
    final names = idx.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    var rest = text;
    final done = <String>{};
    for (final n in names) {
      final tag = '@$n';
      if (!rest.contains(tag)) continue;
      rest = rest.replaceAll(tag, '');
      final u = idx[n]!;
      if (!done.add(u)) continue;
      await sendNotif(u, {'t': 'men', 'g': gid, 'm': groupName(gid).length > 40 ? groupName(gid).substring(0, 40) : groupName(gid), 'mid': mid, 'tx': text.length > 90 ? text.substring(0, 90) : text});
    }
  }

  void _insertMention(String name) {
    var t = ctrl.text;
    if (t.endsWith('@')) t = t.substring(0, t.length - 1);
    final pre = (t.isEmpty || t.endsWith(' ')) ? '' : ' ';
    ctrl.text = '$t$pre@$name ';
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
  }

  Future<void> _mentionPicker() async {
    if (memCache[gid] != true && !isStaff) {
      toast('لا يمكن رؤية أعضاء هذا القروب', bad: true);
      return;
    }
    final s = TextEditingController();
    // تفتح القائمة فوراً؛ الأسماء تُحمَّل مسبقاً عند دخول الشات (وهنا إن لم تكتمل)
    showAppSheet<void>(context, (sc) => [
          const Text('اذكر عضواً', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          FutureBuilder<Map<String, String>>(
            future: _names(),
            builder: (c0, snap) {
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              final idx = snap.data!;
              return StatefulBuilder(builder: (c, set) {
                final q = s.text.trim();
                final names = idx.keys.where((n) => q.isEmpty || n.contains(q)).take(40).toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(controller: s, onChanged: (_) => set(() {}), decoration: const InputDecoration(hintText: 'ابحث بالاسم')),
                  const SizedBox(height: 8),
                  if (isStaff && (q.isEmpty || 'الكل'.contains(q)))
                    ListTile(
                      dense: true,
                      leading: const CircleAvatar(radius: 17, child: Icon(Icons.campaign_outlined, size: 18)),
                      title: const Text('الكل'),
                      subtitle: const Text('تنبيه فوري لكل أعضاء القروب', style: TextStyle(color: kMu, fontSize: 11.5)),
                      onTap: () {
                        Navigator.of(sc).pop();
                        _insertMention('الكل');
                      },
                    ),
                  ...names.map((n) => ListTile(
                        dense: true,
                        leading: UserAvatar(idx[n]!, size: 34),
                        title: Text(n),
                        onTap: () {
                          Navigator.of(sc).pop();
                          _insertMention(n);
                        },
                      )),
                  if (names.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Center(child: Text('لا نتائج', style: TextStyle(color: kMu)))),
                ]);
              });
            },
          ),
        ]);
  }

  // ---------- القائمة المطولة ----------
  void _menu(String id) {
    final m = msgs[id];
    if (m == null) return;
    final type = (m['type'] ?? '').toString();
    if (type == 'sys') {
      // رسائل البوت والترحيب والفعاليات: الحذف للمطورين والإمبراطور فقط
      if (!Session.isDev) return;
      showAppSheet<void>(context, (sc) => [
            AppButton('↩️ رد', kind: 'g', onPressed: () {
              Navigator.of(sc).pop();
              _startReply(m);
            }),
            AppButton('🗑 حذف رسالة البوت', kind: 'r', onPressed: () async {
              Navigator.of(sc).pop();
              try {
                await ref('messages/$gid/$id').remove();
              } catch (e) {
                err(e);
              }
            }),
          ]);
      return;
    }
    final own = (m['from'] ?? '').toString() == myUid;
    showAppSheet<void>(context, (sc) => [
          AppButton('👁 من شاهد الرسالة', kind: 'g', onPressed: () {
            Navigator.of(sc).pop();
            _seenSheet(id);
          }),
          if (type == 'text')
            AppButton('📋 نسخ', kind: 'g', onPressed: () {
              Navigator.of(sc).pop();
              Clipboard.setData(ClipboardData(text: (m['text'] ?? '').toString()));
              toast('تم النسخ');
            }),
          if (type == 'sticker' && (m['sid'] ?? '').toString().isNotEmpty)
            StealStickerButton(sid: (m['sid'] ?? '').toString(), close: () => Navigator.of(sc).pop()),
          if (own && type == 'text')
            AppButton('✏️ تعديل', kind: 'g', onPressed: () {
              Navigator.of(sc).pop();
              _edit(id, (m['text'] ?? '').toString());
            }),
          if (!own)
            AppButton('🚩 ابلاغ عن الرسالة', kind: 'g', onPressed: () async {
              Navigator.of(sc).pop();
              final ev = await _evidence(around: id);
              if (!mounted) return;
              reportChat(context, kind: 'msg', where: groupName(gid), gid: gid, peer: (m['from'] ?? '').toString(), lines: ev);
            }),
          if (own || isStaff)
            AppButton('🗑 حذف', kind: 'r', onPressed: () async {
              Navigator.of(sc).pop();
              try {
                await ref('messages/$gid/$id').remove();
              } catch (e) {
                err(e);
              }
            }),
        ]);
  }

  /// بحث عن كلمة في آخر 800 رسالة (للمطورين)
  Future<void> _searchChat() async {
    final c = TextEditingController();
    final q = await showAppSheet<String>(context, (sc) => [
          const Text('🔎 بحث في الشات', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'اكتب الكلمة')),
          AppButton('بحث', onPressed: () => Navigator.of(sc).pop(c.text.trim())),
        ]);
    if (q == null || q.isEmpty || !mounted) return;
    try {
      final snap = await ref('messages/$gid').orderByKey().limitToLast(800).get();
      final v = snap.value;
      final hits = <MapEntry<String, Map<dynamic, dynamic>>>[];
      if (v is Map) {
        v.forEach((k, x) {
          if (x is Map && (x['text'] ?? '').toString().contains(q)) hits.add(MapEntry(k.toString(), x));
        });
      }
      hits.sort((a, b) => b.key.compareTo(a.key));
      if (!mounted) return;
      if (hits.isEmpty) {
        toast('لا توجد نتائج');
        return;
      }
      final shown = hits.take(40).toList();
      final names = <String, String>{};
      for (final h in shown) {
        final u = (h.value['from'] ?? '').toString();
        if (u.isNotEmpty && !names.containsKey(u)) names[u] = (await prof(u)).name;
      }
      if (!mounted) return;
      showAppSheet<void>(context, (sc) => [
            Text('النتائج (${hits.length})', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            for (final h in shown)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .25), borderRadius: BorderRadius.circular(12)),
                child: Text('${names[(h.value['from'] ?? '').toString()] ?? 'النظام'}: ${(h.value['text'] ?? '').toString()}', style: const TextStyle(height: 1.6)),
              ),
          ]);
    } catch (e) {
      err(e);
    }
  }

  /// حذف كل رسائل الشات (للمطورين)
  Future<void> _clearChat() async {
    final ok = await showAppSheet<bool>(context, (sc) => [
          const Text('حذف كل رسائل هذا الشات نهائياً؟', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          AppButton('نعم، احذف الشات', kind: 'r', onPressed: () => Navigator.of(sc).pop(true)),
          AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(sc).pop(false)),
        ]);
    if (ok != true) return;
    try {
      await ref('messages/$gid').remove();
      if (mounted) setState(() => msgs.clear());
      toast('تم حذف الشات ✅');
    } catch (e) {
      err(e);
    }
  }

  static const String _pushChars = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

  /// وقت إنشاء مفتاح Firebase (أول 8 رموز) بالمللي ثانية
  int _keyTime(String k) {
    var t = 0;
    for (var i = 0; i < 8 && i < k.length; i++) {
      final x = _pushChars.indexOf(k[i]);
      t = t * 64 + (x < 0 ? 0 : x);
    }
    return t;
  }

  /// ترتيب الرسائل بوقت الخادم (ts) فتبقى متسلسلة حتى لو اختلفت ساعات الأجهزة
  List<String> _orderedKeys() {
    final ks = msgs.keys.toList();
    int eff(String k) {
      final t = (msgs[k]?['ts'] as num?)?.toInt() ?? 0;
      return t > 0 ? t : _keyTime(k);
    }
    ks.sort((a, b) {
      final c = eff(a).compareTo(eff(b));
      return c != 0 ? c : a.compareTo(b);
    });
    return ks;
  }

  /// آخر الرسائل (نصاً) لإرفاقها كدليل مع البلاغ
  Future<List<String>> _evidence({String? around}) async {
    final ks = _orderedKeys();
    var end = ks.length;
    if (around != null) {
      final i = ks.indexOf(around);
      if (i >= 0) end = i + 1;
    }
    final start = end - 12 < 0 ? 0 : end - 12;
    final out = <String>[];
    for (final k in ks.sublist(start, end)) {
      final m = msgs[k]!;
      final type = (m['type'] ?? 'text').toString();
      if (type == 'sys') continue;
      final nm = (await prof((m['from'] ?? '').toString())).name;
      final t = type == 'text' ? (m['text'] ?? '').toString() : (type == 'image' ? '[صورة]' : (type == 'sticker' ? '[ملصق]' : '[تسجيل صوتي]'));
      out.add('$nm: ${t.length > 120 ? t.substring(0, 120) : t}');
    }
    return out;
  }

  void _seenSheet(String id) {
    final m = msgs[id];
    if (m == null) return;
    final from = (m['from'] ?? '').toString();
    final seen = m['seen'];
    final rows = <MapEntry<String, int>>[];
    if (seen is Map) {
      seen.forEach((k, v) {
        if (k.toString() != from) rows.add(MapEntry(k.toString(), v is num ? v.toInt() : 0));
      });
    }
    rows.sort((a, b) => a.value.compareTo(b.value));
    showAppSheet<void>(context, (sc) => [
          Text('شاهدها (${rows.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('لم يشاهدها أحد بعد', style: TextStyle(color: kMu)))),
          ...rows.map((r) => ListTile(
                dense: true,
                leading: UserAvatar(r.key, size: 34),
                title: FutureBuilder<Prof>(future: prof(r.key), builder: (c, s) => Text(s.data?.name ?? '...')),
                trailing: Text(hhmm(r.value), style: const TextStyle(color: kMu, fontSize: 12)),
              )),
        ]);
  }

  void _edit(String id, String old) {
    final c = TextEditingController(text: old);
    showAppSheet<void>(context, (sc) => [
          const Text('تعديل الرسالة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          TextField(controller: c, minLines: 2, maxLines: 6, maxLength: 2000),
          AppButton('حفظ', onPressed: () async {
            final t = c.text.trim();
            if (t.isEmpty) return;
            Navigator.of(sc).pop();
            try {
              await ref('messages/$gid/$id').update(<String, Object?>{'text': t, 'edited': true, 'editedAt': nowMs()});
            } catch (e) {
              err(e);
            }
          }),
        ]);
  }

  Future<void> _older() async {
    if (oldest.isEmpty) return;
    try {
      final s = await ref('messages/$gid').orderByKey().endBefore(oldest).limitToLast(30).get();
      final v = s.value;
      if (v is! Map || v.isEmpty) {
        if (mounted) setState(() => hasMore = false);
        return;
      }
      if (!mounted) return;
      setState(() {
        v.forEach((k, x) {
          if (x is Map) {
            final key = k.toString();
            msgs[key] = Map<String, dynamic>.from(x);
            if (key.compareTo(oldest) < 0) oldest = key;
          }
        });
        if (v.length < 30) hasMore = false;
      });
    } catch (e) {
      err(e);
    }
  }

  void _avatarTap(String from) {
    // الحالة لا تُعرض إلا من دائرة الإمبراطور في الواجهة الرئيسية؛ هنا يُعرض الملف التعريفي دائماً
    viewProfile(context, from);
  }

  Widget _composer() {
    final r = _reply;
    if (r == null) return _composerBody();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        color: kBg2,
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
        child: Row(children: [
          Icon(Icons.reply_rounded, size: 18, color: context.accent2),
          const SizedBox(width: 8),
          Expanded(child: Text('رد على ${r['n']}: ${r['t']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: kMu))),
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _reply = null), icon: const Icon(Icons.close, size: 18)),
        ]),
      ),
      _composerBody(),
    ]);
  }

  void _cmdsSheet() {
    const cmds = [
      ['.اوامر', 'قائمة الأوامر', ''],
      ['.العاب', 'قائمة الألعاب', ''],
      ['.رصيدي', 'رصيدك الحالي', ''],
      ['.تفاصيلي', 'ملفك وإحصائياتك', ''],
      ['.معلوماته', 'ملف عضو: اذكره بـ @', '1'],
      ['.تحويل', 'حوّل رصيداً: .تحويل @اسم 50', '1'],
      ['.كريستال', 'لعبة الكريستال', ''],
      ['.اعلام', 'فعالية الأعلام', ''],
      ['.كتابة', 'فعالية الكتابة', ''],
      ['.تفكيك', 'فعالية التفكيك', ''],
      ['.الوان', 'فعالية الألوان', ''],
      ['.رهانات', 'فعالية الرهانات', ''],
      ['.المتصدرين', 'قائمة المتصدرين', ''],
      ['.الغاء', 'إلغاء الفعالية الجارية', ''],
    ];
    showAppSheet<void>(context, (sc) => [
          const Text('📋 الأوامر', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          for (final cm in cmds)
            ListTile(
              dense: true,
              title: Text(cm[0], style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(cm[1], style: const TextStyle(color: kMu, fontSize: 12)),
              onTap: () {
                Navigator.of(sc).pop();
                if (cm[2] == '1') {
                  ctrl.text = '${cm[0]} ';
                  ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
                } else {
                  ctrl.text = cm[0];
                  _sendText();
                }
              },
            ),
        ]);
  }

  void _plusMenu() {
    const cols = ['#ff7a1a', '#ff4d4d', '#ff4fa0', '#a64bff', '#5b7bff', '#2ec8ff', '#19c7b0', '#2ee07a', '#ffd83b', '#9aa4b2'];
    showAppSheet<void>(context, (sc) => [
          const Text('➕ المزيد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          AppButton('📋 الأوامر', onPressed: () {
            Navigator.of(sc).pop();
            _cmdsSheet();
          }),
          const SizedBox(height: 8),
          AppButton('🖼️ إرسال صورة', kind: 'g', onPressed: () {
            Navigator.of(sc).pop();
            _sendImage();
          }),
          if (Session.isDev) ...[
            const SizedBox(height: 8),
            AppButton('✨ تأثير رسائلي', kind: 'g', onPressed: () {
              Navigator.of(sc).pop();
              showMsgStyleSheet(context);
            }),
          ],
          if (Session.isEmp) ...[
          const SizedBox(height: 12),
          const Text('لون رسائلك (يبقى ثابتاً)', style: TextStyle(color: kMu, fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final cl in cols)
              GestureDetector(
                onTap: () {
                  prefs.setString('txtc', cl);
                  Navigator.of(sc).pop();
                  toast('تم تغيير لون رسائلك');
                },
                child: Container(width: 38, height: 38, decoration: BoxDecoration(color: hexColor(cl), shape: BoxShape.circle, border: Border.all(color: Colors.white24))),
              ),
            GestureDetector(
              onTap: () {
                prefs.setString('txtc', '');
                Navigator.of(sc).pop();
                toast('عاد اللون الافتراضي');
              },
              child: Container(width: 38, height: 38, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white38)), child: const Icon(Icons.restart_alt, size: 20)),
            ),
          ]),
          ],
        ]);
  }

  Widget _composerBody() {
    if (!canWrite) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        color: kBg2,
        child: SafeArea(
          top: false,
          child: kind == 'shop'
              ? AppButton('🛒 تسوّق', glow: true, onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShopScreen())))
              : Text(kind == 'main' ? 'الشات مقفل من المشرفين 🔒' : 'للقراءة فقط', textAlign: TextAlign.center, style: const TextStyle(color: kMu)),
        ),
      );
    }
    if (muted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        color: const Color(0xFF3A0A0A),
        child: SafeArea(top: false, child: MuteCountdown(until: muteUntil, onDone: () {
          if (mounted) setState(() {});
        })),
      );
    }
    if (recording) return _recPanel();
    return Container(
      color: kBg2,
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
      child: SafeArea(
        top: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(visualDensity: VisualDensity.compact, onPressed: _plusMenu, icon: const Icon(Icons.add_circle_outline)),
          IconButton(visualDensity: VisualDensity.compact, onPressed: _stickers, icon: const Icon(Icons.emoji_emotions_outlined)),
          IconButton(visualDensity: VisualDensity.compact, onPressed: _mentionPicker, icon: const Icon(Icons.alternate_email)),
          if (Session.me.gender == 'm')
            IconButton(visualDensity: VisualDensity.compact, onPressed: _toggleRec, icon: const Icon(Icons.mic_none)),
          Expanded(
            child: TextField(
              controller: ctrl,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(hintText: 'اكتب رسالة…', counterText: ''),
              onChanged: (t) {
                if (t.endsWith('@')) _mentionPicker();
              },
            ),
          ),
          const SizedBox(width: 6),
          Material(color: context.accent, shape: const CircleBorder(), child: IconButton(onPressed: _sendText, icon: Transform.flip(flipX: true, child: const Icon(Icons.send, color: kDarkText)))),
        ]),
      ),
    );
  }

  Widget _warStrip() {
    return const SizedBox(); // أُلغيت رسائل «تتعرضون لهجوم…/تشنون حرباً…» نهائياً
    // ignore: dead_code
    if (kind != 'main') return const SizedBox();
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
      builder: (c, _) {
        final now = nowMs();
        for (final en in WarWatcher.feeds.entries) {
          final f = en.value;
          if (f['res'] != null || _warHidden.contains(en.key)) continue;
          final at = f['ag'] == gid, df = f['dg'] == gid;
          if (!at && !df) continue;
          final st = (f['st'] as num?)?.toInt() ?? 0;
          final s = ((st - now) / 1000).floor();
          String p(int x) => x.toString().padLeft(2, '0');
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: at ? const Color(0xFF7A5200) : const Color(0xFF7A0A0A),
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 34),
                child: Center(
                  child: Text(
                    '${at ? '⚔️ تشنون حرباً على «${f['dn']}»' : '🚨 تتعرضون لهجوم من «${f['an']}»'}\n${s > 0 ? 'تبدأ المعركة بعد ${p(s ~/ 3600)}:${p((s % 3600) ~/ 60)}:${p(s % 60)}' : 'بانتظار الحسم…'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ),
              ),
              if (Session.isDev)
                PositionedDirectional(
                  end: 4,
                  top: -4,
                  child: InkWell(
                    onTap: () => setState(() => _warHidden.add(en.key)),
                    child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.close, size: 18)),
                  ),
                ),
            ]),
          );
        }
        return const SizedBox();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ks = _orderedKeys();
    final rows = ks.reversed.toList();
    final more = hasMore && msgs.length >= 30;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupInfoScreen(gid: gid))),
          child: Row(children: [GroupPhoto(gid, size: 36, viewable: true), const SizedBox(width: 10), Expanded(child: Text(groupName(gid), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17))), GuildMuteButton(gid)]),
        ),
        actions: [
          if (kind == 'main') GamesActionButton(onTap: () => showGamesSheet(context, gid)),
          if (kind == 'main')
            IconButton(
              tooltip: 'ابلاغ عن الدردشة',
              icon: const Icon(Icons.flag_outlined),
              onPressed: () async {
                final ev = await _evidence();
                if (!mounted) return;
                reportChat(context, kind: 'guild', where: groupName(gid), gid: gid, lines: ev);
              },
            ),
          if (Session.isDev)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'find') {
                  _searchChat();
                } else if (v == 'clear') {
                  _clearChat();
                } else if (v == 'kashf') {
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const KashfScreen()));
                }
              },
              itemBuilder: (_) => [
                if (kind == 'ads') const PopupMenuItem<String>(value: 'kashf', child: Row(children: [Icon(Icons.leaderboard_outlined, size: 20), SizedBox(width: 10), Text('كشف')])),
                const PopupMenuItem<String>(value: 'find', child: Row(children: [Icon(Icons.search, size: 20), SizedBox(width: 10), Text('بحث في الشات')])),
                const PopupMenuItem<String>(value: 'clear', child: Row(children: [Icon(Icons.delete_forever_outlined, size: 20, color: Color(0xFFFF6B6B)), SizedBox(width: 10), Text('حذف الشات')])),
              ],
            ),
          IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupInfoScreen(gid: gid))), icon: const Icon(Icons.info_outline)),
        ],
      ),
      body: ChatWallpaper(child: Column(children: [
        if (status.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(8), color: accentA(context, .14), child: Text('📌 $status', style: const TextStyle(fontSize: 13))),
        _warStrip(),
        if (kind == 'news') const WarCancelBar(),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            reverse: true,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            itemCount: rows.length + (more ? 1 : 0),
            findChildIndexCallback: (Key k) {
              if (k is ValueKey<String>) {
                final i = rows.indexOf(k.value);
                return i < 0 ? null : i;
              }
              return null;
            },
            itemBuilder: (c, i) {
              if (i == rows.length) {
                return Padding(padding: const EdgeInsets.all(8), child: Center(child: TextButton(onPressed: _older, child: const Text('تحميل رسائل أقدم'))));
              }
              final id = rows[i];
              final m = msgs[id]!;
              if (_hiddenEv(id, m)) return const SizedBox.shrink();
              final from = (m['from'] ?? '').toString();
              final type = (m['type'] ?? 'text').toString();
              if (type != 'sys' && from != myUid) _queueSeen(id, m);
              final bio = bios[from];
              final bubble = MsgBubble(
                id: id,
                m: m,
                mine: from == myUid,
                admin: admins[from] == true,
                viewerStaff: isStaff,
                bio: bio is Map ? Map<String, dynamic>.from(bio) : null,
                cache: imgCache,
                onLong: () => _menu(id),
                onJump: (i) => _jumpTo(i),
                onAvatar: () => _avatarTap(from),
                onReply: (type == 'sys' && !((m['k'] ?? '') == 'bot' || (m['k'] ?? '') == 'welcome')) ? null : () => _startReply(m, id),
                gid: gid,
              );
              return AnimatedContainer(
                // مفتاح ثابت بالمعرّف: GlobalKey لكل رسالة كان يسبب تداخل الرسائل وتعلّق بطاقات البوت
                key: (id == widget.focusMid || id == _jumpId) ? keys.putIfAbsent(id, () => GlobalKey()) : ValueKey<String>(id),
                duration: const Duration(milliseconds: 300),
                decoration: (id == _hlId || _mentionMids.contains(id))
                    ? BoxDecoration(
                        color: context.accent.withAlpha(38),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.accent, width: 2),
                        boxShadow: [BoxShadow(color: context.accent.withAlpha(190), blurRadius: 22, spreadRadius: 2)],
                      )
                    : BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.transparent, width: 2)),
                child: _fresh.contains(id)
                    ? TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        child: bubble,
                        builder: (ctx, v, ch) {
                          final rtl = Directionality.of(ctx) == TextDirection.rtl;
                          final dx = from == myUid ? 0.0 : (rtl ? 70.0 : -70.0) * (1 - v);
                          final dy = from == myUid ? 40.0 * (1 - v) : 0.0;
                          return Opacity(opacity: v, child: Transform.translate(offset: Offset(dx, dy), child: ch));
                        },
                      )
                    : bubble,
              );
            },
          ),
        ),
        _scoreChip(),
        if (_mentionMids.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: GestureDetector(
                onTap: () {
                  final id = _mentionMids.removeAt(0);
                  setState(() {});
                  _jumpTo(id);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: context.accent, boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6)]),
                  child: Text(_mentionMids.length > 1 ? '@${_mentionMids.length}' : '@', style: const TextStyle(color: kDarkText, fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ),
            ),
          ),
        _composer(),
      ])),
    );
  }
}

Future<void> showGamesSheet(BuildContext context, String gid) async {
  final can = await canPlay(gid);
  if (!context.mounted) return;
  showAppSheet<void>(context, (sc) {
    Widget b(String t, String cmd) => AppButton(t, kind: 'g', onPressed: () {
          Navigator.of(sc).pop();
          runCommand(context, gid, '.$cmd');
        });
    return [
      const Text('🎮 الألعاب', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      AppButton('🎯 لعب منفرد وكازينو رهانات', glow: true, onPressed: () {
        Navigator.of(sc).pop();
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SoloHubScreen()));
      }),
      if (can) ...[
        const Text('فعاليات جماعية', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kMu)),
        b('⌨️ سرعة الكتابة', 'كتابة'),
        b('🎨 لعبة الألوان', 'الوان'),
        b('🧩 فعالية التفكيك', 'تفكيك'),
        b('😀 فعالية الايموجي', 'ايموجي'),
        b('💛 الحدس (رهان جماعي)', 'حدس'),
        b('🎈 البالونات (رهان جماعي)', 'بالون'),
        b('♟ تحدي الشطرنج', 'شطرنج'),
        b('🐾 فعالية الحيوانات', 'حيوانات'),
        b('🎭 تخمين الشخصيات', 'شخصيات'),
      ],
    ];
  });
}

class _StickerImg extends StatelessWidget {
  final String sid;
  final double size;
  final bool steal;
  const _StickerImg({required this.sid, this.size = 132, this.steal = false});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: stickerData(sid),
      builder: (c, s) {
        final b = s.data == null ? null : dataUrlBytes(s.data!);
        final img = SizedBox(width: size, height: size, child: b == null ? const SizedBox() : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true)));
        if (!steal) return img;
        // ضغطة واحدة على الملصق تعرض زر «سرقة الملصق» مع اسم صانعه
        return GestureDetector(
          onTap: () => showAppSheet<void>(c, (sc) => [
                const Text('الملصق', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                StealStickerButton(sid: sid, close: () => Navigator.of(sc).pop()),
              ]),
          child: img,
        );
      },
    );
  }
}

class VoiceBubble extends StatefulWidget {
  final String src;
  const VoiceBubble({required this.src});
  @override
  State<VoiceBubble> createState() => _VoiceState();
}

class _VoiceState extends State<VoiceBubble> {
  final AudioPlayer p = AudioPlayer();
  bool playing = false;

  @override
  void dispose() {
    if (playing) Sfx.unblock('audio');
    p.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    try {
      if (playing) {
        await p.stop();
        Sfx.unblock('audio');
        setState(() => playing = false);
        return;
      }
      final b = dataUrlBytes(widget.src);
      if (b == null) return;
      Sfx.block('audio');
      setState(() => playing = true);
      p.onPlayerComplete.first.then((_) {
        Sfx.unblock('audio');
        if (mounted) setState(() => playing = false);
      });
      await p.play(BytesSource(b));
    } catch (_) {
      Sfx.unblock('audio');
      if (mounted) setState(() => playing = false);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _tap,
        child: Container(
          width: 180,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 34), const SizedBox(width: 8), Expanded(child: Container(height: 3, decoration: BoxDecoration(color: const Color(0x66FFFFFF), borderRadius: BorderRadius.circular(2))))]),
        ),
      );
}

class MsgBubble extends StatefulWidget {
  final String id;
  final Map<String, dynamic> m;
  final bool mine;
  final bool admin;
  final Map<String, dynamic>? bio;
  final Map<String, Uint8List> cache;
  final VoidCallback onLong;
  final VoidCallback onAvatar;
  final VoidCallback? onReply;
  final void Function(String)? onJump;
  final String gid;
  final bool viewerStaff; // هل من يشاهد الرسالة مشرف أو مطور (لأزرار البطاقات)

  const MsgBubble({super.key, this.viewerStaff = false, required this.id, required this.m, required this.mine, required this.admin, required this.bio, required this.cache, required this.onLong, required this.onAvatar, this.onReply, this.onJump, this.gid = ''});

  @override
  State<MsgBubble> createState() => _MsgBubbleState();
}

class _MsgBubbleState extends State<MsgBubble> {
  late final Future<List<dynamic>> who;

  String get from => (widget.m['from'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    who = Future.wait<dynamic>([prof(from), roleOf(from), badgeExtra(from)]);
  }

  Uint8List? _bytes() {
    final c = widget.cache[widget.id];
    if (c != null) return c;
    final b = dataUrlBytes((widget.m['img'] ?? '').toString());
    if (b != null) widget.cache[widget.id] = b;
    return b;
  }

  List<InlineSpan> _spans(String t, Color acc) {
    final out = <InlineSpan>[];
    var last = 0;
    for (final mt in RegExp(r'@\S+').allMatches(t)) {
      if (mt.start > last) out.add(TextSpan(text: t.substring(last, mt.start)));
      out.add(TextSpan(text: mt.group(0), style: TextStyle(color: acc, fontWeight: FontWeight.w800)));
      last = mt.end;
    }
    if (last < t.length) out.add(TextSpan(text: t.substring(last)));
    return out;
  }

  void _viewImg(Uint8List b) {
    Sfx.block('image');
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ImageViewer(bytes: b))).then((_) => Sfx.unblock('image'));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final type = (m['type'] ?? 'text').toString();
    if (type == 'sys') return _sys(context);
    final mine = widget.mine;
    final col = hexOk(m['color']?.toString()) ? m['color'].toString() : '#5b5be0';
    final ts = m['ts'] is num ? (m['ts'] as num).toInt() : 0;
    final seen = m['seen'];
    final sc = seen is Map ? seen.keys.where((k) => k.toString() != from).length : 0;
    final maxW = MediaQuery.of(context).size.width * .78;

    final bubble = FutureBuilder<List<dynamic>>(
      future: who,
      builder: (c, s) {
        final p = s.data != null ? s.data![0] as Prof : Prof.fallback;
        final r = s.data != null ? s.data![1] as String? : null;
        final isHigh = r == 'dev' || r == 'emp';
        final tag = rankTag(r);
        final bio = widget.bio;
        final ex = (s.data != null && s.data!.length > 2 && s.data![2] is Map) ? Map<String, dynamic>.from(s.data![2] as Map) : <String, dynamic>{};
        final hideM = ex['hide'] is Map ? ex['hide'] as Map : const {};
        bool hid(String k) => hideM[k] == true;
        final achW = achTag(ex);
        final body = <Widget>[
          if (isHigh && !hid('dev')) Padding(padding: const EdgeInsets.only(bottom: 2), child: DevBadge(founder: r == 'emp')),
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(p.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                if (tag != null && !hid('rank')) tag,
                if (widget.admin && !isHigh && !hid('adm')) const Tag('مشرف'),
                if (!hid('age')) ageTag(p, role: r),
                if (achW != null) achW,
                if (m['vis'] == true) const Tag('زائر'),
              ]),
            ),
          if (!mine && bio != null && (bio['t'] ?? '').toString().isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(bio['t'].toString(), style: TextStyle(fontSize: 11, color: hexOk(bio['c']?.toString()) ? hexColor(bio['c'].toString()) : kMu))),
          if ((m['rpt'] ?? '').toString().isNotEmpty)
            GestureDetector(
              onTap: () {
                final i = (m['rpi'] ?? '').toString();
                if (i.isNotEmpty) widget.onJump?.call(i);
              },
              child: Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(8), border: const BorderDirectional(start: BorderSide(color: Colors.white70, width: 3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('رد على ${m['rpn'] ?? ''}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                Text(m['rpt'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xCCFFFFFF))),
              ]),
            ),
            ),
        ];
        if (type == 'image') {
          final b = _bytes();
          if (b != null) {
            body.add(GestureDetector(onTap: () => _viewImg(b), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(b, width: 240, fit: BoxFit.cover, gaplessPlayback: true))));
          }
          final cap = (m['cap'] ?? '').toString();
          if (cap.isNotEmpty) body.add(Padding(padding: const EdgeInsets.only(top: 5), child: Text.rich(TextSpan(children: _spans(cap, context.accent2)), style: const TextStyle(fontSize: 15, height: 1.5))));
        } else if (type == 'sticker') {
          body.add(_StickerImg(sid: (m['sid'] ?? '').toString(), steal: true));
        } else if (type == 'audio') {
          body.add(VoiceBubble(src: (m['au'] ?? '').toString()));
        } else {
          body.add(Text.rich(TextSpan(children: _spans((m['text'] ?? '').toString(), context.accent2)), style: const TextStyle(fontSize: 15, height: 1.5)));
        }
        body.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (m['edited'] == true) const Text('تم التعديل  ', style: TextStyle(fontSize: 10.5, color: Color(0xB3FFFFFF))),
            Text(hhmm(ts), style: const TextStyle(fontSize: 10.5, color: Color(0xB3FFFFFF))),
            if (m['ok'] == true) const Text('  ✅', style: TextStyle(fontSize: 12)),
            if (mine && sc > 0) Text('   👁 $sc', style: const TextStyle(fontSize: 10.5, color: Color(0xB3FFFFFF))),
          ]),
        ));
        final mst = isHigh ? MsgStyle.parse(m['ms']) : null;
        if (mst != null && (!mst.royal || r == 'emp')) {
          return GestureDetector(
            onLongPress: widget.onLong,
            child: StyledBubble(
              st: mst,
              constraints: BoxConstraints(maxWidth: maxW, minWidth: 64),
              padding: const EdgeInsets.fromLTRB(11, 7, 11, 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: body),
            ),
          );
        }
        return GestureDetector(
          onLongPress: widget.onLong,
          child: VipBubble(
            constraints: BoxConstraints(maxWidth: maxW, minWidth: 64),
            padding: const EdgeInsets.fromLTRB(11, 7, 11, 5),
            color: hexColor(col),
            dark: hexColor(darkHex(col)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: body),
          ),
        );
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (!mine) UserAvatar(from, size: 30, onTap: widget.onAvatar),
          if (!mine) const SizedBox(width: 6),
          Flexible(child: bubble),
          if (widget.onReply != null)
            GestureDetector(
              onTap: widget.onReply,
              behavior: HitTestBehavior.opaque,
              child: const Padding(padding: EdgeInsets.fromLTRB(6, 0, 4, 6), child: Icon(Icons.reply_rounded, size: 20, color: kMu)),
            ),
        ]),
      ),
    );
  }

  Widget _sys(BuildContext context) {
    final m = widget.m;
    final k = (m['k'] ?? '').toString();
    final w = MediaQuery.of(context).size.width * .92;
    Widget? card;
    if (k == 'rank' || k == 'war') {
      try {
        final o = Map<String, dynamic>.from(jsonDecode((m['d'] ?? '{}').toString()) as Map);
        card = k == 'rank' ? RankCard(o: o) : WarCard(o: o);
      } catch (_) {}
    }
    if (card == null && k == 'bot' && (m['d'] ?? '').toString().contains('"bet"')) {
      card = BetCard(gid: widget.gid, text: (m['text'] ?? '').toString());
    }
    if (card == null && k == 'bot' && (m['d'] ?? '').toString().contains('"ev"')) {
      try {
        final o = Map<String, dynamic>.from(jsonDecode((m['d'] ?? '{}').toString()) as Map);
        if (o['ev'] == 1) {
          card = EvCard(
            text: (m['text'] ?? '').toString(),
            col: (o['col'] ?? '').toString(),
            o: o,
            at: (m['ts'] as num?)?.toInt() ?? 0,
            canCancel: Session.isDev || widget.viewerStaff || (o['by'] ?? '').toString() == myUid,
            cancelLocked: o['hot'] == true && !Session.isDev,
            onCancel: () => cancelEvent(widget.gid),
            onAct: (a, d) => evAct(widget.gid, a, d),
          );
        }
      } catch (_) {}
    }
    final canReply = widget.onReply != null && (k == 'bot' || k == 'welcome');
    Widget withReply(Widget box) => GestureDetector(
          onLongPress: widget.onLong,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Flexible(child: box),
            if (canReply)
              GestureDetector(
                onTap: widget.onReply,
                behavior: HitTestBehavior.opaque,
                child: const Padding(padding: EdgeInsets.fromLTRB(6, 0, 2, 6), child: Icon(Icons.reply_rounded, size: 20, color: kMu)),
              ),
          ]),
        );
    if (card != null) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Center(child: withReply(ConstrainedBox(constraints: BoxConstraints(maxWidth: w), child: card))));
    }
    final text = (m['text'] ?? '').toString();
    final pic = (m['pic'] ?? '').toString();
    final b = (m['img'] ?? '').toString().isEmpty ? null : _bytes();
    Widget content;
    if (k == 'welcome') {
      final lines = text.split('\n');
      content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (pic.isNotEmpty) Center(child: ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(pic, height: 170, fit: BoxFit.cover, errorBuilder: (c, e, s) => const SizedBox()))),
        const SizedBox(height: 6),
        Center(child: UserAvatar(from, size: 56)),
        const SizedBox(height: 6),
        for (final l in lines)
          l.contains('𝑭𝑰𝑹 亗')
              ? ShaderMask(blendMode: BlendMode.srcIn, shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFFB04A), Color(0xFFFF4FA0), Color(0xFF7FB2FF)]).createShader(r), child: Text(l, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)))
              : Text.rich(TextSpan(children: _spans(l, context.accent2)), textAlign: TextAlign.center, style: const TextStyle(height: 1.7, fontSize: 13.5)),
      ]);
    } else {
      content = Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black, border: Border.all(color: context.accent)), child: Text('ALJESI', style: TextStyle(fontSize: 6, color: context.accent2, fontWeight: FontWeight.w800))),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (b != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(b, width: 200, fit: BoxFit.cover))),
            Text(text, style: const TextStyle(height: 1.7, fontSize: 13.5)),
            if (k == 'bot' && (m['f'] ?? '').toString().isNotEmpty) Text('بطلب: ${m['f']}', style: const TextStyle(color: kMu, fontSize: 11)),
          ]),
        ),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Center(
        child: withReply(Container(
          constraints: BoxConstraints(maxWidth: w),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .45), borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
          child: content,
        )),
      ),
    );
  }
}

class ImageViewer extends StatelessWidget {
  final Uint8List bytes;
  const ImageViewer({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return BigImageViewer(bytes: bytes);
  }
}

/// نص الوقت المتبقي: 00:30 أو 1:05:00 أو «2 يوم 03:00:00»
String leftText(int until) {
  var s = ((until - nowMs()) / 1000).ceil();
  if (s < 0) s = 0;
  String two(int n) => n.toString().padLeft(2, '0');
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final x = s % 60;
  final core = h > 0 || d > 0 ? '${two(h)}:${two(m)}:${two(x)}' : '${two(m)}:${two(x)}';
  return d > 0 ? '$d يوم $core' : core;
}

/// عدّاد تنازلي لمدة التقييد (يتحدّث كل ثانية دون إعادة رسم الشات)
class MuteCountdown extends StatefulWidget {
  final int until;
  final VoidCallback onDone;
  const MuteCountdown({super.key, required this.until, required this.onDone});
  @override
  State<MuteCountdown> createState() => _MuteCountdownState();
}

class _MuteCountdownState extends State<MuteCountdown> {
  Timer? t;
  bool fired = false;

  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (widget.until <= nowMs() && !fired) {
        fired = true;
        widget.onDone();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('⛔ أنت مقيد من الشات — باقي ${leftText(widget.until)}', textAlign: TextAlign.center, style: const TextStyle(color: kRed, fontWeight: FontWeight.w800));
}

/// ملصق يُعرض خارج الشات (مثل الدردشة الخاصة)
class StickerThumb extends StatelessWidget {
  final String sid;
  final double size;
  const StickerThumb({super.key, required this.sid, this.size = 132});
  @override
  Widget build(BuildContext context) => _StickerImg(sid: sid, size: size);
}
