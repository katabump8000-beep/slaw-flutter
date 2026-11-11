import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'home.dart' show groupsCache, memCache;
import 'widgets.dart';

// وضع «توفير الإنترنت» (لمستخدمي باقات الرسائل النصية فقط مثل زين):
// قائمة محادثات (قروبات + أصدقاء) ثم شات رسائل نصية فقط — بلا صور ولا ملصقات ولا إعدادات ولا أزرار إضافية.

class LiteHome extends StatefulWidget {
  const LiteHome({super.key});
  @override
  State<LiteHome> createState() => _LiteHomeState();
}

class _LiteHomeState extends State<LiteHome> {
  final List<MapEntry<String, String>> _groups = [];
  final List<MapEntry<String, String>> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      Map<String, Map<String, dynamic>> gs = Map.of(groupsCache);
      if (gs.isEmpty) {
        final v = (await ref('groups').get().timeout(const Duration(seconds: 30))).value;
        if (v is Map) {
          v.forEach((k, x) {
            if (x is Map) gs[k.toString()] = {'name': x['name'], 'kind': x['kind'], 'adm': x['adm']};
          });
        }
      }
      final isDev = Session.isDev;
      final keys = gs.keys.toList();
      final ok = await Future.wait(keys.map((g) async {
        if (memCache[g] == true) return true;
        if (isDev) return true;
        try {
          return (await ref('members/$g/$myUid').get().timeout(const Duration(seconds: 20))).value == true;
        } catch (_) {
          return false;
        }
      }));
      for (var i = 0; i < keys.length; i++) {
        if (!ok[i]) continue;
        final k = (gs[keys[i]]?['kind'] ?? '').toString();
        if (k == 'ads' || k == 'shop' || k == 'upd') continue; // قنوات للقراءة فقط
        _groups.add(MapEntry(keys[i], (gs[keys[i]]?['name'] ?? 'قروب').toString()));
      }
      final fv = (await ref('friends/$myUid').get().timeout(const Duration(seconds: 20))).value;
      if (fv is Map) {
        for (final u in fv.keys) {
          final p = await prof(u.toString());
          _friends.add(MapEntry(u.toString(), p.name));
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Widget _tile(String title, String sub, VoidCallback f) => ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(sub, style: const TextStyle(color: kMu, fontSize: 12)),
        trailing: const Icon(Icons.chevron_left),
        onTap: f,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('توفير الإنترنت'), automaticallyImplyLeading: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              for (final g in _groups)
                _tile(g.value, 'مجموعة', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiteChat(path: 'messages/${g.key}', title: g.value)))),
              for (final f in _friends)
                _tile(f.value, 'صديق', () {
                  final p = [myUid, f.key]..sort();
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiteChat(path: 'fdm/${p[0]}/${p[1]}', title: f.value, dm: true)));
                }),
              if (_groups.isEmpty && _friends.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('لا توجد محادثات متاحة حالياً', style: TextStyle(color: kMu)))),
            ]),
    );
  }
}

class LiteChat extends StatefulWidget {
  final String path, title;
  final bool dm;
  const LiteChat({super.key, required this.path, required this.title, this.dm = false});

  /// مسار القراءة: نسخة نصية خفيفة يكتبها السيرفر (لا صور ولا ملفات)
  String get litePath => dm ? path.replaceFirst('fdm/', 'liteD/') : path.replaceFirst('messages/', 'lite/');
  @override
  State<LiteChat> createState() => _LiteChatState();
}

class _LiteChatState extends State<LiteChat> {
  final ctrl = TextEditingController();
  final scroll = ScrollController();
  final List<MapEntry<String, Map<String, dynamic>>> _msgs = [];
  final Map<String, String> _names = {};
  StreamSubscription<DatabaseEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref(widget.litePath).orderByKey().limitToLast(40).onChildAdded.listen((e) async {
      final v = e.snapshot.value;
      if (v is! Map) return;
      final m = Map<String, dynamic>.from(v);
      final from = (m['f'] ?? '').toString();
      if (from.isNotEmpty && !_names.containsKey(from)) {
        _names[from] = (await prof(from)).name;
      }
      if (!mounted) return;
      setState(() => _msgs.add(MapEntry(e.snapshot.key ?? '', m)));
      Future<void>.delayed(const Duration(milliseconds: 60), () {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    ctrl.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = ctrl.text.trim();
    if (t.isEmpty) return;
    ctrl.clear();
    try {
      final k = ref(widget.path).push().key!;
      final m = <String, Object?>{'from': myUid, 'ts': ServerValue.timestamp, if (!widget.dm) 'type': 'text', if (!widget.dm) 'color': Session.me.color, 'text': t};
      await ref('${widget.path}/$k').set(m);
    } catch (_) {
      ctrl.text = t;
      toast('تعذر الإرسال', bad: true);
    }
  }

  bool _textOnly(Map<String, dynamic> m) {
    return m['x'] == null && (m['t'] ?? '').toString().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(10),
            itemCount: _msgs.length,
            itemBuilder: (c, i) {
              final m = _msgs[i].value;
              final mine = m['f'] == myUid;
              final ts = (m['ts'] as num?)?.toInt() ?? 0;
              final ok = _textOnly(m);
              return Align(
                alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                child: GestureDetector(
                  onTap: ok ? null : () => showDialog<void>(context: context, builder: (d) => AlertDialog(content: const Text('أنت في وضع توفير الطاقة الفائق', textAlign: TextAlign.center), actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('حسناً'))])),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                    decoration: BoxDecoration(color: ok ? (mine ? const Color(0xFF1F3D2B) : const Color(0xFF22262D)) : Colors.black, borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (!mine) Text(_names[(m['f'] ?? '').toString()] ?? 'عضو', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF8FC1FF))),
                      Text(ok ? (m['t'] ?? '').toString() : 'صورة تعذر تحميلها\nبسبب وضع التوفير', style: TextStyle(height: 1.5, color: ok ? Colors.white : Colors.white54)),
                      Align(alignment: AlignmentDirectional.centerEnd, child: Text(hhmm(ts), style: const TextStyle(fontSize: 10.5, color: Colors.white38))),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              Expanded(child: TextField(controller: ctrl, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'اكتب رسالة...'))),
              IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}
