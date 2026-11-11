import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'app_state.dart';
import 'ai.dart' show imageUnsafe;
import 'chat.dart' show VoiceBubble, StickerThumb, ImageViewer, dataUrlBytes;
import 'crop.dart';
import 'data.dart';
import 'friends.dart' show removeFriend;
import 'profile.dart';
import 'reports.dart';
import 'widgets.dart';

/// بطاقة «دردشة الإمبراطور»: أول عنصر في الشاشة الرئيسية
class EmpChatCard extends StatelessWidget {
  const EmpChatCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (Session.isEmp) {
      return StreamBuilder<DatabaseEvent>(
        stream: ref('emp/req').onValue,
        builder: (c, s) {
          final v = s.data?.snapshot.value;
          final n = v is Map ? v.values.where((x) => x is Map && x['st'] == 'p').length : 0;
          return _card(context, 'طلبات الدردشة', n > 0 ? '$n طلب بانتظارك' : 'لا توجد طلبات جديدة', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmpRequestsScreen())), dot: n > 0);
        },
      );
    }
    return StreamBuilder<DatabaseEvent>(
      stream: ref('emp/req/$myUid').onValue,
      builder: (c, s) {
        final v = s.data?.snapshot.value;
        final st = v is Map ? (v['st'] ?? '').toString() : '';
        final sub = st == 'ok' ? 'اضغط للمراسلة' : st == 'p' ? 'بانتظار قبول الإمبراطور' : st == 'no' ? 'لم يُقبل الطلب' : 'أرسل طلب صداقة للإمبراطور';
        return _card(context, 'دردشة الإمبراطور', sub, () {
          if (st == 'ok') {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmpChatScreen(uid: myUid)));
          } else if (st.isEmpty) {
            _ask(context);
          } else {
            toast(st == 'p' ? 'طلبك بانتظار الإمبراطور' : 'لم يتم قبول الطلب');
          }
        });
      },
    );
  }

  Widget _card(BuildContext context, String t, String sub, VoidCallback f, {bool dot = false}) => InkWell(
        onTap: f,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD4AF37)),
            gradient: const LinearGradient(colors: [Color(0xFF3A0F1C), Color(0xFF14070C)]),
          ),
          child: Row(children: [
            const InfinityMark(size: 30),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontWeight: FontWeight.w900)), Text(sub, style: const TextStyle(color: kMu, fontSize: 12))])),
            if (dot) Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: context.accent)),
          ]),
        ),
      );

  void _ask(BuildContext context) {
    final c = TextEditingController();
    showAppSheet<void>(context, (sc) => [
          const Text('طلب صداقة للإمبراطور', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          TextField(controller: c, maxLength: 200, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'اكتب سبب طلبك (اختياري)')),
          AppButton('إرسال الطلب', onPressed: () async {
            try {
              await ref('emp/req/$myUid').set(<String, Object?>{'st': 'p', 'ts': ServerValue.timestamp, 'tx': c.text.trim()});
              if (sc.mounted) Navigator.of(sc).pop();
              toast('تم إرسال الطلب ✅');
            } catch (e) {
              err(e);
            }
          }),
        ]);
  }
}

class EmpRequestsScreen extends StatelessWidget {
  const EmpRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الدردشة')),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref('emp/req').onValue,
        builder: (c, s) {
          final v = s.data?.snapshot.value;
          final rows = <MapEntry<String, Map<dynamic, dynamic>>>[];
          if (v is Map) v.forEach((k, x) => x is Map ? rows.add(MapEntry(k.toString(), x)) : null);
          if (rows.isEmpty) return const Center(child: Text('لا توجد طلبات', style: TextStyle(color: kMu)));
          return ListView(children: [
            for (final r in rows)
              ListTile(
                leading: UserAvatar(r.key, size: 44),
                title: FutureBuilder<Prof>(future: prof(r.key), builder: (c, s) => Text(s.data?.name ?? '...', style: const TextStyle(fontWeight: FontWeight.w800))),
                subtitle: Text((r.value['tx'] ?? '').toString().isEmpty ? (r.value['st'] == 'ok' ? 'مقبول' : r.value['st'] == 'no' ? 'مرفوض' : 'بانتظار القرار') : r.value['tx'].toString(), style: const TextStyle(color: kMu)),
                trailing: r.value['st'] == 'p'
                    ? Wrap(children: [
                        IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () => ref('emp/req/${r.key}').update({'st': 'ok'})),
                        IconButton(icon: const Icon(Icons.cancel, color: kRed), onPressed: () => ref('emp/req/${r.key}').update({'st': 'no'})),
                      ])
                    : null,
                onTap: r.value['st'] == 'ok' ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmpChatScreen(uid: r.key))) : null,
              ),
          ]);
        },
      ),
    );
  }
}

class _Thread extends StatefulWidget {
  final String path;
  final String title;
  final String? peer;
  const _Thread({required this.path, required this.title, this.peer});
  @override
  State<_Thread> createState() => _ThreadState();
}

class _ThreadState extends State<_Thread> {
  final Map<String, Map<dynamic, dynamic>> msgs = {};
  final c = TextEditingController();
  StreamSubscription<DatabaseEvent>? sub, sub2, sub3, subPin;
  Map<dynamic, dynamic>? pin;
  bool muted = false;
  final AudioRecorder rec = AudioRecorder();
  bool recording = false;
  String? recPath;
  Timer? recTimer;

  @override
  void initState() {
    super.initState();
    final q = ref(widget.path).orderByKey().limitToLast(60);
    sub = q.onChildAdded.listen((e) {
      final v = e.snapshot.value;
      if (v is Map && e.snapshot.key != null && mounted) setState(() => msgs[e.snapshot.key!] = v);
    }, onError: (_) {});
    // تعديل/حذف الرسائل يظهر فوراً عند الطرفين
    sub2 = q.onChildChanged.listen((e) {
      final v = e.snapshot.value;
      if (v is Map && e.snapshot.key != null && mounted) setState(() => msgs[e.snapshot.key!] = v);
    }, onError: (_) {});
    sub3 = q.onChildRemoved.listen((e) {
      if (e.snapshot.key != null && mounted) setState(() => msgs.remove(e.snapshot.key));
    }, onError: (_) {});
    if (_isFriendDm) {
      subPin = ref(_pinPath).onValue.listen((e) {
        final v = e.snapshot.value;
        if (mounted) setState(() => pin = v is Map ? v : null);
      }, onError: (_) {});
      ref('fdmMute/$myUid/${widget.peer ?? ''}').get().then((x) {
        if (mounted) setState(() => muted = x.value == true);
      }).catchError((Object _) {});
    }
  }

  String get _pinPath => 'fdmPin/${widget.path.split('/').sublist(1).join('/')}';

  Future<void> _toggleMute() async {
    final p = widget.peer ?? '';
    if (p.isEmpty) return;
    try {
      if (muted) {
        await ref('fdmMute/$myUid/$p').remove();
      } else {
        await ref('fdmMute/$myUid/$p').set(true);
      }
      if (mounted) setState(() => muted = !muted);
      toast(muted ? 'تم كتم إشعارات هذه المحادثة 🔕' : 'تم تفعيل الإشعارات 🔔');
    } catch (e) {
      err(e);
    }
  }

  /// قائمة الضغط المطوّل على الرسالة: نسخ / تثبيت / تعديل / حذف
  void _msgMenu(String k, Map<dynamic, dynamic> m) {
    final mine = m['from'] == myUid;
    final isText = (m['au'] ?? '').toString().isEmpty && (m['img'] ?? '').toString().isEmpty && (m['sid'] ?? '').toString().isEmpty;
    final text = (m['text'] ?? '').toString();
    final pinned = pin != null && pin!['m'] == k;
    showAppSheet<void>(context, (sc) => [
          if (isText)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('نسخ'),
              onTap: () {
                Navigator.of(sc).pop();
                Clipboard.setData(ClipboardData(text: text));
                toast('تم النسخ');
              },
            ),
          if (_isFriendDm)
            ListTile(
              leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(pinned ? 'إلغاء التثبيت' : 'تثبيت'),
              onTap: () async {
                Navigator.of(sc).pop();
                try {
                  if (pinned) {
                    await ref(_pinPath).remove();
                  } else {
                    final label = (m['au'] ?? '').toString().isNotEmpty ? '🎤 رسالة صوتية' : (m['sid'] ?? '').toString().isNotEmpty ? '🏷 ملصق' : (m['img'] ?? '').toString().isNotEmpty ? '📷 صورة' : (text.length > 120 ? text.substring(0, 120) : text);
                    await ref(_pinPath).set(<String, Object?>{'m': k, 't': label, 'by': myUid});
                  }
                } catch (e) {
                  err(e);
                }
              },
            ),
          if (mine && isText && _isFriendDm)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.of(sc).pop();
                _edit(k, text);
              },
            ),
          if (mine && _isFriendDm)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)),
              title: const Text('حذف', style: TextStyle(color: Color(0xFFFF6B6B))),
              onTap: () async {
                Navigator.of(sc).pop();
                try {
                  await ref('${widget.path}/$k').remove();
                  if (pinned) await ref(_pinPath).remove();
                } catch (e) {
                  err(e);
                }
              },
            ),
        ]);
  }

  void _edit(String k, String old) {
    final t = TextEditingController(text: old);
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تعديل الرسالة'),
        content: TextField(controller: t, maxLines: 4, minLines: 1, maxLength: 2000),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              final v = t.text.trim();
              Navigator.pop(d);
              if (v.isEmpty || v == old) return;
              try {
                await ref('${widget.path}/$k').update(<String, Object?>{'text': v, 'ed': true});
              } catch (e) {
                err(e);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    sub?.cancel();
    sub2?.cancel();
    sub3?.cancel();
    subPin?.cancel();
    recTimer?.cancel();
    rec.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = c.text.trim();
    if (t.isEmpty) return;
    c.clear();
    try {
      await ref(widget.path).push().set(<String, Object?>{'from': myUid, 'text': t, 'ts': ServerValue.timestamp});
    } catch (e) {
      c.text = t;
      err(e);
    }
  }

  Future<void> _sendImg() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null || !mounted) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      final d = await cropImage(context, bytes, out: const [900, 720, 560, 420, 320], limit: 55000, round: false, title: 'قص الصورة', ratio: 4 / 3);
      if (d == null) return;
      final fb = dataUrlBytes(d);
      if (!Session.isDev && fb != null && await imageUnsafe(fb) == true) {
        toast('لا يمكن إرسال هذه الصورة', bad: true);
        return;
      }
      await ref(widget.path).push().set(<String, Object?>{'from': myUid, 'text': '📷 صورة', 'img': d, 'ts': ServerValue.timestamp});
    } catch (e) {
      err(e);
    }
  }

  Future<void> _sendSticker() async {
    List<String> mine = [];
    try {
      final v = (await ref('myStickers/$myUid').get()).value;
      if (v is Map) mine = v.keys.map((e) => e.toString()).toList();
    } catch (_) {}
    if (!mounted) return;
    if (mine.isEmpty) {
      toast('ما عندك ملصقات بعد — أنشئ ملصقاً من الشات العام أولاً');
      return;
    }
    showAppSheet<void>(context, (sc) => [
          const Text('الملصقات', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final sid in mine)
              GestureDetector(
                onTap: () async {
                  Navigator.of(sc).pop();
                  try {
                    await ref(widget.path).push().set(<String, Object?>{'from': myUid, 'text': '🏷 ملصق', 'sid': sid, 'ts': ServerValue.timestamp});
                  } catch (e) {
                    err(e);
                  }
                },
                child: StickerThumb(sid: sid, size: 76),
              ),
          ]),
        ]);
  }

  Widget _body(Map<dynamic, dynamic> m) {
    if ((m['au'] ?? '').toString().isNotEmpty) return VoiceBubble(src: m['au'].toString());
    if ((m['sid'] ?? '').toString().isNotEmpty) return StickerThumb(sid: m['sid'].toString(), size: 120);
    if ((m['img'] ?? '').toString().isNotEmpty) {
      final b = dataUrlBytes(m['img'].toString());
      if (b != null) {
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ImageViewer(bytes: b))),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(b, width: 220, fit: BoxFit.cover, gaplessPlayback: true)),
        );
      }
    }
    return Text((m['text'] ?? '').toString(), style: const TextStyle(height: 1.5));
  }

  Future<void> _startRec() async {
    try {
      if (!await rec.hasPermission()) {
        toast('فعّل إذن الميكروفون', bad: true);
        return;
      }
      final dir = (await getTemporaryDirectory()).path;
      final p = '$dir/dm_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 24000, sampleRate: 16000), path: p);
      recPath = p;
      if (mounted) setState(() => recording = true);
      recTimer = Timer(const Duration(seconds: 20), () {
        if (recording) _finishRec(send: true);
      });
    } catch (e) {
      if (mounted) setState(() => recording = false);
      err(e);
    }
  }

  Future<void> _finishRec({required bool send}) async {
    recTimer?.cancel();
    String? p;
    try {
      p = await rec.stop();
    } catch (_) {}
    p ??= recPath;
    if (mounted) setState(() => recording = false);
    if (!send || p == null) return;
    try {
      final b = await File(p).readAsBytes();
      final d = 'data:audio/mp4;base64,${base64Encode(b)}';
      if (d.length > 140000) {
        toast('التسجيل طويل جداً', bad: true);
        return;
      }
      await ref(widget.path).push().set(<String, Object?>{
        'from': myUid,
        'text': '🎤 رسالة صوتية',
        'au': d,
        'dur': min(60, max(1, b.length ~/ 3000)),
        'ts': ServerValue.timestamp,
      });
    } catch (e) {
      err(e);
    }
  }

  bool get _isFriendDm => widget.path.startsWith('fdm/');

  List<String> _evidence() {
    final ks = msgs.keys.toList()..sort();
    final last = ks.length > 14 ? ks.sublist(ks.length - 14) : ks;
    final out = <String>[];
    for (final k in last) {
      final m = msgs[k]!;
      final t = (m['au'] ?? '').toString().isNotEmpty ? '[تسجيل صوتي]' : (m['img'] ?? '').toString().isNotEmpty ? '[صورة]' : (m['sid'] ?? '').toString().isNotEmpty ? '[ملصق]' : (m['text'] ?? '').toString();
      out.add('${m['from'] == myUid ? 'المبلِّغ' : 'الطرف الآخر'}: ${t.length > 120 ? t.substring(0, 120) : t}');
    }
    return out;
  }

  Future<void> _removeFriend() async {
    final peer = widget.peer;
    if (peer == null || peer.isEmpty) return;
    await removeFriend(context, peer);
    try {
      final still = (await ref('friends/$myUid/$peer').get()).exists;
      if (!still && mounted) Navigator.of(context).pop();
    } catch (_) {}
  }

  Widget _title() {
    final peer = widget.peer;
    if (peer == null || peer.isEmpty) return Text(widget.title);
    return GestureDetector(
      onTap: () => viewProfile(context, peer),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        UserAvatar(peer, size: 34),
        const SizedBox(width: 10),
        Flexible(child: FutureBuilder<Prof>(future: prof(peer), builder: (cx, s) => Text(s.data?.name ?? widget.title, overflow: TextOverflow.ellipsis))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = msgs.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: _title(),
        actions: [
          if (_isFriendDm)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'rep') {
                  reportChat(context, kind: 'fdm', where: 'دردشة صديق', peer: widget.peer ?? '', lines: _evidence());
                } else if (v == 'del') {
                  _removeFriend();
                } else if (v == 'mute') {
                  _toggleMute();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(value: 'mute', child: Row(children: [Icon(muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined, size: 20), const SizedBox(width: 10), Text(muted ? 'تفعيل الإشعارات' : 'كتم الإشعارات')])),
                const PopupMenuItem<String>(value: 'rep', child: Row(children: [Icon(Icons.flag_outlined, size: 20), SizedBox(width: 10), Text('ابلاغ عن الدردشة')])),
                const PopupMenuItem<String>(value: 'del', child: Row(children: [Icon(Icons.person_remove_alt_1_outlined, size: 20, color: Color(0xFFFF6B6B)), SizedBox(width: 10), Text('حذف الصديق')])),
              ],
            ),
        ],
      ),
      body: Column(children: [
        if (pin != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(color: Color(0xFF1B2230), border: Border(bottom: BorderSide(color: Colors.white12))),
            child: Row(children: [
              const Icon(Icons.push_pin, size: 16, color: Color(0xFFFFC857)),
              const SizedBox(width: 8),
              Expanded(child: Text((pin!['t'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.4))),
              GestureDetector(onTap: () => ref(_pinPath).remove().catchError((Object _) {}), child: const Icon(Icons.close, size: 18, color: Colors.white54)),
            ]),
          ),
        Expanded(
          child: ListView(reverse: true, padding: const EdgeInsets.all(10), children: [
            for (final k in keys.reversed)
              Align(
                alignment: msgs[k]!['from'] == myUid ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                child: GestureDetector(
                  onLongPress: () => _msgMenu(k, msgs[k]!),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: msgs[k]!['from'] == myUid ? const Color(0xFF7A2A00) : const Color(0xFF26304A), border: pin != null && pin!['m'] == k ? Border.all(color: const Color(0xFFFFC857), width: 1.2) : null),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      _body(msgs[k]!),
                      const SizedBox(height: 3),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (msgs[k]!['ed'] == true) const Text('تم التعديل  ', style: TextStyle(fontSize: 10, color: Colors.white38)),
                        Text(hhmm((msgs[k]!['ts'] as num?)?.toInt() ?? 0), style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
                      ]),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        Container(
          color: kBg2,
          padding: const EdgeInsets.all(8),
          child: SafeArea(
            top: false,
            child: recording
                ? Row(children: [
                    IconButton(onPressed: () => _finishRec(send: false), icon: const Icon(Icons.close_rounded, color: kRed)),
                    const Expanded(child: Text('🔴 جارٍ التسجيل…', style: TextStyle(fontWeight: FontWeight.w800))),
                    IconButton(onPressed: () => _finishRec(send: true), icon: Transform.flip(flipX: true, child: Icon(Icons.send, color: context.accent))),
                  ])
                : Row(children: [
                    IconButton(onPressed: _sendImg, icon: Icon(Icons.image_outlined, color: context.accent)),
                    IconButton(onPressed: _sendSticker, icon: Icon(Icons.emoji_emotions_outlined, color: context.accent)),
                    Expanded(child: TextField(controller: c, decoration: const InputDecoration(hintText: 'اكتب رسالة…'))),
                    IconButton(onPressed: _startRec, icon: Icon(Icons.mic_rounded, color: context.accent)),
                    IconButton(onPressed: _send, icon: Transform.flip(flipX: true, child: Icon(Icons.send, color: context.accent))),
                  ]),
          ),
        ),
      ]),
    );
  }
}

/// دردشة بين الإمبراطور وعضو قبل طلبه
class EmpChatScreen extends StatelessWidget {
  final String uid;
  const EmpChatScreen({super.key, required this.uid});
  @override
  Widget build(BuildContext context) => _Thread(path: 'emp/msg/$uid', title: Session.isEmp ? 'مراسلة عضو' : 'دردشة الإمبراطور', peer: Session.isEmp ? uid : Session.emp);
}

/// مراسلة بين مطورين
class DevDmScreen extends StatelessWidget {
  final String peer;
  const DevDmScreen({super.key, required this.peer});
  @override
  Widget build(BuildContext context) {
    final p = [myUid, peer]..sort();
    return _Thread(path: 'dm/${p[0]}/${p[1]}', title: 'مراسلة مطور', peer: peer);
  }
}

/// دردشة بين صديقين
class FriendDmScreen extends StatelessWidget {
  final String peer;
  const FriendDmScreen({super.key, required this.peer});
  @override
  Widget build(BuildContext context) {
    final p = [myUid, peer]..sort();
    return _Thread(path: 'fdm/${p[0]}/${p[1]}', title: 'دردشة صديق', peer: peer);
  }
}
