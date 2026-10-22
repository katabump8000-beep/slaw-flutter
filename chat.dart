import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'crop.dart';
import 'data.dart';
import 'home.dart';
import 'invite.dart';
import 'profile.dart';
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
  final ScrollController scroll = ScrollController();
  final TextEditingController ctrl = TextEditingController();
  final List<StreamSubscription<DatabaseEvent>> subs = [];
  Map<String, dynamic> admins = {};
  Map<String, dynamic> bios = {};
  bool locked = false;
  bool hasMore = true;
  String oldest = '';
  final Set<String> pendingSeen = <String>{};
  final Set<String> doneSeen = <String>{};
  Timer? seenTimer;
  Map<String, String>? nameIdx;
  final Map<String, Uint8List> imgCache = {};

  String get kind => groupKind(gid);
  bool get visitor => memCache[gid] == 'v';
  bool get isStaff => Session.isDev || admins[myUid] == true;
  bool get canWrite => Session.isDev || (kind == 'main' && (!locked || isStaff));

  @override
  void initState() {
    super.initState();
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
    _welcome();
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    seenTimer?.cancel();
    _flush();
    scroll.dispose();
    ctrl.dispose();
    super.dispose();
  }

  void _put(DataSnapshot s) {
    final k = s.key;
    final v = s.value;
    if (k == null || v is! Map || !mounted) return;
    setState(() {
      msgs[k] = Map<String, dynamic>.from(v);
      if (oldest.isEmpty || k.compareTo(oldest) < 0) oldest = k;
    });
  }

  Future<void> _welcome() async {
    if (kind != 'main' || memCache[gid] != true) return;
    try {
      final s = await ref('welcomed/$gid/$myUid').get();
      if (s.exists) return;
      final k = ref('messages/$gid').push().key!;
      await db.ref().update(<String, Object?>{
        'welcomed/$gid/$myUid': true,
        'messages/$gid/$k': <String, Object?>{
          'from': myUid,
          'type': 'sys',
          'k': 'welcome',
          'text': '🔥 انضم ${Session.me.name} إلى النقابة، رحّبوا به! حصل على 100 رصيد كعضو جديد.',
          'ts': ServerValue.timestamp,
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
  Map<String, Object?> _base(String type) => <String, Object?>{
        'from': myUid,
        'type': type,
        'ts': ServerValue.timestamp,
        'color': Session.me.color,
        if (visitor) 'vis': true,
      };

  Future<String> _post(Map<String, Object?> m, {bool count = true}) async {
    final k = ref('messages/$gid').push().key!;
    final up = <String, Object?>{'messages/$gid/$k': m};
    if (kind == 'main' && count) up['stats/$gid/$myUid'] = ServerValue.increment(1);
    await db.ref().update(up);
    return k;
  }

  Future<void> _sendText() async {
    final t = ctrl.text.trim();
    if (t.isEmpty) return;
    ctrl.clear();
    try {
      final m = _base('text');
      m['text'] = t;
      final k = await _post(m);
      _notifyMentions(k, t);
    } catch (e) {
      ctrl.text = t;
      err(e);
    }
  }

  Future<void> _sendImage() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null || !mounted) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      final d = await cropImage(context, bytes,
          out: const [900, 720, 560, 420, 320], limit: 55000, round: false, title: 'قص الصورة', ratio: 4 / 3);
      if (d == null || !mounted) return;
      final preview = dataUrlBytes(d);
      final cc = TextEditingController();
      final cap = await showAppSheet<String>(context, (sc) => [
            const Text('إرسال صورة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (preview != null)
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(preview, height: 190, fit: BoxFit.cover)),
            TextField(controller: cc, maxLength: 200, minLines: 1, maxLines: 3, decoration: const InputDecoration(hintText: 'اكتب شرحاً للصورة (اختياري)')),
            AppButton('إرسال', onPressed: () => Navigator.of(sc).pop(cc.text.trim())),
          ]);
      if (cap == null) return;
      final m = _base('image');
      m['img'] = d;
      if (cap.isNotEmpty) m['cap'] = cap;
      final k = await _post(m);
      if (cap.contains('@')) _notifyMentions(k, cap);
    } catch (e) {
      err(e);
    }
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
      try {
        await ref('notifs/$u').push().set(<String, Object?>{
          't': 'men',
          'from': myUid,
          'g': gid,
          'm': groupName(gid).length > 40 ? groupName(gid).substring(0, 40) : groupName(gid),
          'mid': mid,
          'tx': text.length > 90 ? text.substring(0, 90) : text,
          'ts': ServerValue.timestamp,
        });
      } catch (_) {}
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
    final idx = await _names();
    if (!mounted) return;
    final s = TextEditingController();
    showAppSheet<void>(context, (sc) => [
          const Text('اذكر عضواً', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          StatefulBuilder(builder: (c, set) {
            final q = s.text.trim();
            final names = idx.keys.where((n) => q.isEmpty || n.contains(q)).take(40).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: s, onChanged: (_) => set(() {}), decoration: const InputDecoration(hintText: 'ابحث بالاسم')),
                const SizedBox(height: 8),
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
              ],
            );
          }),
        ]);
  }

  // ---------- القائمة المطولة ----------
  void _menu(String id) {
    final m = msgs[id];
    if (m == null) return;
    final type = (m['type'] ?? '').toString();
    if (type == 'sys') return;
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
          if (own && type == 'text')
            AppButton('✏️ تعديل', kind: 'g', onPressed: () {
              Navigator.of(sc).pop();
              _edit(id, (m['text'] ?? '').toString());
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
              await ref('messages/$gid/$id').update(<String, Object?>{
                'text': t,
                'edited': true,
                'editedAt': DateTime.now().millisecondsSinceEpoch,
              });
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

  void _info() {
    final m = groupsCache[gid] ?? <String, dynamic>{};
    showAppSheet<void>(context, (sc) => [
          Center(child: GroupPhoto(gid, size: 80)),
          Center(child: Text(groupName(gid), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
          Center(child: Tag(kKinds[kind] ?? '')),
          Text((m['desc'] ?? '').toString().isEmpty ? 'لا يوجد وصف' : (m['desc'] ?? '').toString(), style: const TextStyle(color: kMu, height: 1.7)),
          if (kind == 'main' && memCache[gid] == true) InviteSection(gid: gid),
        ]);
  }

  Widget _composer() {
    if (!canWrite) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        color: kBg2,
        child: SafeArea(
          top: false,
          child: Text(kind == 'main' ? 'الشات مقفل من المشرفين 🔒' : 'للقراءة فقط', textAlign: TextAlign.center, style: const TextStyle(color: kMu)),
        ),
      );
    }
    return Container(
      color: kBg2,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(onPressed: _sendImage, icon: const Icon(Icons.photo_outlined)),
            IconButton(onPressed: _mentionPicker, icon: const Icon(Icons.alternate_email)),
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
            Material(
              color: context.accent,
              shape: const CircleBorder(),
              child: IconButton(onPressed: _sendText, icon: const Icon(Icons.send, color: kDarkText, matchTextDirection: true)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = msgs.keys.toList()..sort();
    final rows = keys.reversed.toList();
    final more = hasMore && msgs.length >= 30;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _info,
          child: Row(children: [
            GroupPhoto(gid, size: 36),
            const SizedBox(width: 10),
            Expanded(child: Text(groupName(gid), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17))),
          ]),
        ),
        actions: [IconButton(onPressed: _info, icon: const Icon(Icons.info_outline))],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scroll,
              reverse: true,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              itemCount: rows.length + (more ? 1 : 0),
              itemBuilder: (c, i) {
                if (i == rows.length) {
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(child: TextButton(onPressed: _older, child: const Text('تحميل رسائل أقدم'))),
                  );
                }
                final id = rows[i];
                final m = msgs[id]!;
                final from = (m['from'] ?? '').toString();
                final type = (m['type'] ?? 'text').toString();
                if (type != 'sys' && from != myUid) _queueSeen(id, m);
                final bio = bios[from];
                return MsgBubble(
                  key: ValueKey(id),
                  id: id,
                  m: m,
                  mine: from == myUid,
                  admin: admins[from] == true,
                  bio: bio is Map ? Map<String, dynamic>.from(bio) : null,
                  cache: imgCache,
                  onLong: () => _menu(id),
                );
              },
            ),
          ),
          _composer(),
        ],
      ),
    );
  }
}

class MsgBubble extends StatefulWidget {
  final String id;
  final Map<String, dynamic> m;
  final bool mine;
  final bool admin;
  final Map<String, dynamic>? bio;
  final Map<String, Uint8List> cache;
  final VoidCallback onLong;

  const MsgBubble({
    super.key,
    required this.id,
    required this.m,
    required this.mine,
    required this.admin,
    required this.bio,
    required this.cache,
    required this.onLong,
  });

  @override
  State<MsgBubble> createState() => _MsgBubbleState();
}

class _MsgBubbleState extends State<MsgBubble> {
  late final Future<List<dynamic>> who;

  String get from => (widget.m['from'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    who = Future.wait<dynamic>([prof(from), roleOf(from)]);
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
        final body = <Widget>[
          if (isHigh) const Padding(padding: EdgeInsets.only(bottom: 2), child: DevBadge()),
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(p.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  if (r == 'emp') const InfinityMark(size: 14),
                  if (tag != null) tag,
                  if (widget.admin && !isHigh) const Tag('مشرف'),
                  ageTag(p),
                  if (m['vis'] == true) const Tag('زائر'),
                ],
              ),
            ),
          if (!mine && bio != null && (bio['t'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(bio['t'].toString(), style: TextStyle(fontSize: 11, color: hexOk(bio['c']?.toString()) ? hexColor(bio['c'].toString()) : kMu)),
            ),
        ];
        if (type == 'image') {
          final b = _bytes();
          if (b != null) {
            body.add(GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ImageViewer(bytes: b))),
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(b, width: 240, fit: BoxFit.cover, gaplessPlayback: true)),
            ));
          }
          final cap = (m['cap'] ?? '').toString();
          if (cap.isNotEmpty) {
            body.add(Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text.rich(TextSpan(children: _spans(cap, context.accent2)), style: const TextStyle(fontSize: 15, height: 1.5)),
            ));
          }
        } else {
          body.add(Text.rich(TextSpan(children: _spans((m['text'] ?? '').toString(), context.accent2)), style: const TextStyle(fontSize: 15, height: 1.5)));
        }
        body.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m['edited'] == true) const Text('تم التعديل  ', style: TextStyle(fontSize: 10.5, color: Color(0xB3FFFFFF))),
              Text(hhmm(ts), style: const TextStyle(fontSize: 10.5, color: Color(0xB3FFFFFF))),
              if (mine && sc > 0) Text('   👁 $sc', style: const TextStyle(fontSize: 10.5, color: Color(0xB3FFFFFF))),
            ],
          ),
        ));
        return GestureDetector(
          onLongPress: widget.onLong,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxW, minWidth: 64),
            padding: const EdgeInsets.fromLTRB(11, 7, 11, 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [hexColor(col), hexColor(darkHex(col))],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: body),
          ),
        );
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) UserAvatar(from, size: 30, onTap: () => viewProfile(context, from)),
            if (!mine) const SizedBox(width: 6),
            Flexible(child: bubble),
          ],
        ),
      ),
    );
  }

  Widget _sys(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .9),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(0, 0, 0, .45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black, border: Border.all(color: context.accent)),
                child: Text('ALJESI', style: TextStyle(fontSize: 6, color: context.accent2, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Flexible(child: Text((widget.m['text'] ?? '').toString(), style: const TextStyle(height: 1.7, fontSize: 13.5))),
            ],
          ),
        ),
      ),
    );
  }
}

class ImageViewer extends StatelessWidget {
  final Uint8List bytes;
  const ImageViewer({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(child: InteractiveViewer(child: Image.memory(bytes))),
    );
  }
}
