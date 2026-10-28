import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
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
  const _Thread({required this.path, required this.title});
  @override
  State<_Thread> createState() => _ThreadState();
}

class _ThreadState extends State<_Thread> {
  final Map<String, Map<dynamic, dynamic>> msgs = {};
  final c = TextEditingController();
  StreamSubscription<DatabaseEvent>? sub;

  @override
  void initState() {
    super.initState();
    sub = ref(widget.path).orderByKey().limitToLast(60).onChildAdded.listen((e) {
      final v = e.snapshot.value;
      if (v is Map && e.snapshot.key != null && mounted) setState(() => msgs[e.snapshot.key!] = v);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    sub?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final keys = msgs.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Expanded(
          child: ListView(reverse: true, padding: const EdgeInsets.all(10), children: [
            for (final k in keys.reversed)
              Align(
                alignment: msgs[k]!['from'] == myUid ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: msgs[k]!['from'] == myUid ? const Color(0xFF7A2A00) : const Color(0xFF26304A)),
                  child: Text((msgs[k]!['text'] ?? '').toString(), style: const TextStyle(height: 1.5)),
                ),
              ),
          ]),
        ),
        Container(
          color: kBg2,
          padding: const EdgeInsets.all(8),
          child: SafeArea(top: false, child: Row(children: [
            Expanded(child: TextField(controller: c, decoration: const InputDecoration(hintText: 'اكتب رسالة…'))),
            IconButton(onPressed: _send, icon: Icon(Icons.send, color: context.accent, matchTextDirection: true)),
          ])),
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
  Widget build(BuildContext context) => _Thread(path: 'emp/msg/$uid', title: Session.isEmp ? 'مراسلة عضو' : 'دردشة الإمبراطور');
}

/// مراسلة بين مطورين
class DevDmScreen extends StatelessWidget {
  final String peer;
  const DevDmScreen({super.key, required this.peer});
  @override
  Widget build(BuildContext context) {
    final p = [myUid, peer]..sort();
    return _Thread(path: 'dm/${p[0]}/${p[1]}', title: 'مراسلة مطور');
  }
}
