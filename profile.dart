import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'ai.dart';
import 'app_state.dart';
import 'data.dart';
import 'entrancefx.dart';
import 'empchat.dart';
import 'home.dart';
import 'widgets.dart';

/// بطاقة الملف التعريفي: إحصائيات التفاعل والإعجاب
Future<void> viewProfile(BuildContext context, String uid) async {
  await playEntrance(context, uid);
  if (!context.mounted) return;
  if (!context.mounted) return;
  await showAppSheet<void>(context, (sc) => [_ProfileBody(uid: uid)]);
}

class _ProfileBody extends StatefulWidget {
  final String uid;
  const _ProfileBody({required this.uid});
  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  Prof? p;
  String? role;
  String pid = '';
  int msgs = 0, wins = 0, likes = 0, contrib = 0, pubs = 0, pride = 100;
  bool liked = false;
  bool loading = true;
  bool priv = false;
  String note = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Object?> _g(String path) async {
    try {
      return (await ref(path).get()).value;
    } catch (_) {
      return null;
    }
  }

  int _n(Object? v) => v is num ? v.toInt() : 0;

  Future<void> _load() async {
    final u = widget.uid;
    p = await prof(u);
    role = await roleOf(u);
    pid = (await _g('pdata/$u/pid'))?.toString() ?? '';
    msgs = _n(await _g('msgTotal/$u'));
    wins = _n(await _g('wins/$u'));
    likes = _n(await _g('likeCount/$u'));
    pubs = _n(await _g('pubCount/$u'));
    pride = await prideOf(u);
    priv = (await _g('pdata/$u/priv')) == true;
    note = ((await _g('pdata/$u/note')) ?? '').toString();
    final mg = memCache.entries.where((e) => e.value == true && groupKind(e.key) == 'main').map((e) => e.key).toList();
    if (mg.isNotEmpty) {
      final c = await _g('guildStats/${mg.first}/contrib/$u');
      contrib = _n(c);
    }
    final l = await _g('likes/$u/$myUid');
    liked = l is num && DateTime.now().millisecondsSinceEpoch - l < 43200000;
    if (mounted) setState(() => loading = false);
  }

  Future<void> _like() async {
    if (liked || widget.uid == myUid) return;
    try {
      await db.ref().update(<String, Object?>{
        'likes/${widget.uid}/$myUid': ServerValue.timestamp,
        'likeCount/${widget.uid}': ServerValue.increment(1),
      });
      setState(() {
        liked = true;
        likes++;
      });
    } catch (e) {
      err(e);
    }
  }

  Widget _stat(String t, String v) => Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .3), borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine)),
          child: Column(children: [Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: context.accent2)), Text(t, style: const TextStyle(fontSize: 11, color: kMu))]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (loading || p == null) return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    final tag = rankTag(role);
    final isDevPeer = (role == 'dev' || role == 'emp') && Session.isDev && widget.uid != myUid;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: UserAvatar(widget.uid, size: 92)),
      const SizedBox(height: 6),
      Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(p!.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if (role == 'emp') ...[const SizedBox(width: 6), const InfinityMark(size: 22)],
        ]),
      ),
      const SizedBox(height: 6),
      Center(child: Wrap(spacing: 6, runSpacing: 6, children: [if (role == 'dev' || role == 'emp') const DevBadge(), if (tag != null) tag, ageTag(p!, role: role), Tag(p!.gender == 'f' ? 'أنثى' : 'ذكر'), if (pubs > 10) const Tag('رتبة عالية 🌟')])),
      if (pid.isNotEmpty) Center(child: Text('ID: $pid', style: const TextStyle(color: kMu, letterSpacing: 1.5))),
      const SizedBox(height: 8),
      if (note.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .25), borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine)),
          child: Text(note, textAlign: TextAlign.center, style: const TextStyle(height: 1.7)),
        ),
      if (priv && widget.uid != myUid && !Session.isDev)
        const Padding(padding: EdgeInsets.all(14), child: Center(child: Text('🔒 هذا الملف التعريفي خاص', style: TextStyle(color: kMu))))
      else ...[
        Row(children: [_stat('رسائل', '$msgs'), _stat('فوز بالفعاليات', '$wins'), _stat('مساهمة الترقية', '$contrib')]),
        Row(children: [_stat('النشر', '$pubs'), _stat('درجة الفخر', '$pride%'), _stat('الإعجابات', '$likes')]),
      ],
      const SizedBox(height: 8),
      if (widget.uid != myUid)
        Center(
          child: GestureDetector(
            onTap: _like,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(shape: BoxShape.circle, color: liked ? context.accent : const Color.fromRGBO(255, 255, 255, .06), border: Border.all(color: liked ? context.accent : kLine)),
              child: Icon(Icons.thumb_up_alt_rounded, size: 30, color: liked ? kDarkText : kMu),
            ),
          ),
        ),
      if (isDevPeer || (Session.isDev && (role == 'dev' || role == 'emp') && widget.uid != myUid))
        Padding(padding: const EdgeInsets.only(top: 10), child: AppButton('مراسلة', kind: 'g', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DevDmScreen(peer: widget.uid))))),
    ]);
  }
}
