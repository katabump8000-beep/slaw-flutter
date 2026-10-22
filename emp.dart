import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

/// إدارة المستخدمين (للإمبراطور فقط): بحث بالـID أو الاسم ثم تعيين مطور
class EmpScreen extends StatefulWidget {
  const EmpScreen({super.key});

  @override
  State<EmpScreen> createState() => _EmpScreenState();
}

class _EmpScreenState extends State<EmpScreen> {
  final q = TextEditingController();
  List<String> found = [];
  bool busy = false;
  String msg = '';
  List<String> devs = [];

  @override
  void initState() {
    super.initState();
    _loadDevs();
  }

  Future<void> _loadDevs() async {
    try {
      final s = await ref('devs').get();
      final v = s.value;
      if (mounted) setState(() => devs = v is Map ? v.keys.map((e) => e.toString()).toList() : <String>[]);
    } catch (_) {}
  }

  Future<void> _search() async {
    final t = normDigits(q.text.trim());
    if (t.isEmpty) return;
    setState(() {
      busy = true;
      msg = '';
      found = [];
    });
    try {
      if (RegExp(r'^\d{9}$').hasMatch(t)) {
        final s = await ref('pids/$t').get();
        if (s.exists) found = [s.value.toString()];
      } else {
        final s = await ref('profiles').get();
        final v = s.value;
        if (v is Map) {
          v.forEach((k, x) {
            if (x is Map && (x['name'] ?? '').toString().contains(t) && found.length < 30) found.add(k.toString());
          });
        }
      }
      if (found.isEmpty) msg = 'لا توجد نتائج';
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _toggle(String u, bool isDev) async {
    try {
      await db.ref().update(<String, Object?>{
        'roles/$u': isDev ? null : 'dev',
        'devs/$u': isDev ? null : true,
      });
      dropRole(u);
      toast(isDev ? 'تمت إزالة الرتبة' : 'تم التعيين كمطور ✅');
      await _loadDevs();
      if (mounted) setState(() {});
    } catch (e) {
      err(e);
    }
  }

  Widget _card(String u) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([prof(u), roleOf(u), ref('pdata/$u/pid').get()]),
      builder: (c, s) {
        if (!s.hasData) return const SizedBox(height: 70, child: Center(child: CircularProgressIndicator()));
        final p = s.data![0] as Prof;
        final r = s.data![1] as String?;
        final pid = (s.data![2] as DataSnapshot).value?.toString() ?? '';
        final isDev = r == 'dev';
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(0, 0, 0, .25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kLine),
          ),
          child: Row(
            children: [
              UserAvatar(u, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (pid.isNotEmpty) Text('ID: $pid', style: const TextStyle(color: kMu, fontSize: 12)),
                    if (r == 'emp') const Padding(padding: EdgeInsets.only(top: 3), child: InfinityMark()),
                  ],
                ),
              ),
              if (r != 'emp')
                SizedBox(
                  width: 120,
                  child: AppButton(isDev ? 'إزالة الرتبة' : 'تعيين كمطور', kind: isDev ? 'r' : 'main', compact: true, onPressed: () => _toggle(u, isDev)),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المستخدمين')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: q,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(hintText: 'ابحث بالـID (9 أرقام) أو الاسم'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: busy ? null : _search, icon: const Icon(Icons.search)),
              ],
            ),
          ),
          if (busy) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          if (msg.isNotEmpty) Padding(padding: const EdgeInsets.all(20), child: Center(child: Text(msg, style: const TextStyle(color: kMu)))),
          ...found.map(_card),
          if (devs.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 4), child: Text('المطورون الحاليون', style: TextStyle(color: kMu, fontWeight: FontWeight.w800))),
          ...devs.map(_card),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
