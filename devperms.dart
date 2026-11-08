import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'tools.dart' show kToolTitles, toolKey;
import 'widgets.dart';

/// «صلاحيات المطورين» (للإمبراطور فقط): يختار مطوراً ثم يخفي أو يظهر أي زر من أدواته
class DevPermsScreen extends StatefulWidget {
  const DevPermsScreen({super.key});

  @override
  State<DevPermsScreen> createState() => _DevPermsState();
}

class _DevPermsState extends State<DevPermsScreen> {
  List<List<String>> devs = []; // [uid, name]
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = (await ref('roles').get()).value;
      final out = <List<String>>[];
      if (v is Map) {
        for (final e in v.entries) {
          if (e.value == 'dev') out.add([e.key.toString(), (await prof(e.key.toString())).name]);
        }
      }
      if (mounted) setState(() => devs = out);
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('صلاحيات المطورين')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : devs.isEmpty
              ? const Center(child: Text('لا يوجد مطورون', style: TextStyle(color: kMu)))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  const Padding(padding: EdgeInsets.all(8), child: Text('اختر مطوراً لتحديد الأزرار التي تظهر له في أدواته.', style: TextStyle(color: kMu, fontSize: 12.5))),
                  for (final d in devs)
                    ListTile(
                      leading: UserAvatar(d[0], size: 38),
                      title: Text(d[1]),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _DevToolsScreen(uid: d[0], name: d[1]))),
                    ),
                ]),
    );
  }
}

class _DevToolsScreen extends StatefulWidget {
  final String uid;
  final String name;
  const _DevToolsScreen({required this.uid, required this.name});

  @override
  State<_DevToolsScreen> createState() => _DevToolsState();
}

class _DevToolsState extends State<_DevToolsScreen> {
  Map<dynamic, dynamic> hide = {};

  @override
  void initState() {
    super.initState();
    ref('config/hideTools/${widget.uid}').onValue.listen((e) {
      final v = e.snapshot.value;
      if (mounted) setState(() => hide = v is Map ? v : {});
    }, onError: (_) {});
  }

  Future<void> _set(String title, bool hidden) async {
    try {
      await ref('config/hideTools/${widget.uid}/${toolKey(title)}').set(hidden ? true : null);
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('أدوات ${widget.name}')),
      body: ListView(children: [
        for (final t in kToolTitles)
          ListTile(
            title: Text(t, style: const TextStyle(fontSize: 14)),
            trailing: SizedBox(width: 86, child: AppButton(hide[toolKey(t)] == true ? 'اظهار' : 'اخفاء', compact: true, kind: hide[toolKey(t)] == true ? 'p' : 'g', onPressed: () => _set(t, hide[toolKey(t)] != true))),
          ),
      ]),
    );
  }
}
