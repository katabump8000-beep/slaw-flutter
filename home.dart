import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'aljesi.dart';
import 'bell.dart';
import 'chat.dart';
import 'core.dart';
import 'data.dart';
import 'empchat.dart';
import 'media.dart';
import 'notif.dart';
import 'settings.dart';
import 'sfx.dart';
import 'shop.dart';
import 'tally.dart';
import 'tools.dart';
import 'war.dart';
import 'widgets.dart';

const Map<String, String> kKinds = {
  'main': 'نقابة',
  'ads': 'إعلانات',
  'shop': 'المتجر',
  'news': 'الصحيفة',
  'upd': 'التحديثات',
  'work': 'الوورك',
};

/// القروبات المحمّلة وعضويتي فيها (true أو 'v' للزائر)
final Map<String, Map<String, dynamic>> groupsCache = {};
final Map<String, dynamic> memCache = {};

const List<String> _pal = ['#2a6cff', '#e53935', '#8e24aa', '#00897b', '#f9a825', '#d81b60', '#43a047', '#ff7a1a'];

String groupColor(String g) {
  final c = groupsCache[g]?['c']?.toString();
  if (hexOk(c)) return c!;
  var h = 0;
  for (final r in g.runes) {
    h = (h * 31 + r) & 0x7fffffff;
  }
  return _pal[h % _pal.length];
}

String groupName(String g) => (groupsCache[g]?['name'] ?? 'قروب').toString();
String groupKind(String g) => (groupsCache[g]?['kind'] ?? 'main').toString();

Future<void> loadGroups() async {
  final gs = await ref('groups').get();
  groupsCache.clear();
  memCache.clear();
  final v = gs.value;
  if (v is Map) {
    v.forEach((k, x) {
      if (x is Map) groupsCache[k.toString()] = Map<String, dynamic>.from(x);
    });
  }
  await Future.wait(groupsCache.keys.map((g) async {
    try {
      final s = await ref('members/$g/$myUid').get();
      if (s.exists) memCache[g] = s.value;
    } catch (_) {}
  }));

  Future<void> join(String g) async {
    try {
      await ref('members/$g/$myUid').set(true);
      memCache[g] = true;
    } catch (_) {}
  }

  for (final g in groupsCache.keys.toList()) {
    final k = groupKind(g);
    if ((k == 'news' || k == 'upd') && memCache[g] == null) await join(g);
  }
  final hasMain = memCache.entries.any((e) => e.value == true && groupKind(e.key) == 'main');
  if (hasMain) {
    for (final g in groupsCache.keys.toList()) {
      final k = groupKind(g);
      if ((k == 'ads' || k == 'shop') && memCache[g] == null) await join(g);
    }
  }
  if (Session.isDev) {
    for (final g in groupsCache.keys.toList()) {
      if (memCache[g] == null) await join(g);
    }
  }
}

final Map<String, Future<MemoryImage?>> _gph = {};

Future<MemoryImage?> groupPhoto(String g) => _gph.putIfAbsent(g, () async {
      try {
        final s = await ref('groupPhotos/$g').get();
        final d = s.value?.toString() ?? '';
        final i = d.indexOf(',');
        if (i < 0) return null;
        return MemoryImage(base64Decode(d.substring(i + 1)));
      } catch (_) {
        return null;
      }
    });

void dropGroupPhoto(String g) => _gph.remove(g);

class GroupPhoto extends StatelessWidget {
  final String gid;
  final double size;
  const GroupPhoto(this.gid, {super.key, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final name = groupName(gid);
    return FutureBuilder<MemoryImage?>(
      future: groupPhoto(gid),
      builder: (c, s) {
        final img = s.data;
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tint(groupColor(gid), .5),
            image: img == null ? null : DecorationImage(image: img, fit: BoxFit.cover),
          ),
          child: img == null
              ? Text(firstChar(name), style: TextStyle(fontSize: size * .4, fontWeight: FontWeight.w800))
              : null,
        );
      },
    );
  }
}

class BalanceChip extends StatelessWidget {
  const BalanceChip({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('wallets/$myUid/bal').onValue,
      builder: (c, s) {
        final raw = s.data?.snapshot.value;
        final n = raw is num ? raw : 0;
        final neg = n < 0 || (raw is double && raw != raw.roundToDouble());
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(0, 0, 0, .35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: neg ? kRed : kLine),
          ),
          child: Text('💰 ${fmtN(n)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: neg ? kRed : kTx)),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool loading = true;
  Timer? devTimer;
  StreamSubscription<DatabaseEvent>? presenceSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Session.ensurePid();
    BellService.start();
    _reload().then((_) {
      WarWatcher.start();
      checkVisitExpiry();
    });
    Sfx.syncBgm();
    initLocalNotifs(ask: true).then((_) => startBackgroundPolling());
    presenceSub = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((e) {
      if (e.snapshot.value == true && myUid.isNotEmpty) {
        final p = ref('presence/$myUid');
        p.onDisconnect().remove();
        p.set(true);
      }
    }, onError: (_) {});
    if (Session.isDev) {
      Future<void> tick() async {
        await settleWars();
        await runTally();
        await prideSweep();
        await postJoinLogs();
      }
      Future<void>.delayed(const Duration(seconds: 6), tick);
      devTimer = Timer.periodic(const Duration(seconds: 30), (_) => tick());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed) {
      Sfx.unblock('bg');
    } else {
      Sfx.block('bg');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    devTimer?.cancel();
    presenceSub?.cancel();
    WarWatcher.stop();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      await loadGroups();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  void _open(String g) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => ChatScreen(gid: g)))
        .then((_) => mounted ? setState(() {}) : null);
  }

  Widget _row(String g) {
    final kind = groupKind(g);
    final col = groupColor(g);
    final dot = BellService.mentionGroups.value.contains(g);
    return InkWell(
      onTap: () => _open(g),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color.fromRGBO(255, 190, 140, .08)))),
        child: Row(
          children: [
            GroupPhoto(g),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: tint(col, .38), borderRadius: BorderRadius.circular(9)),
                    child: Text(groupName(g),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  const SizedBox(height: 3),
                  Text(kKinds[kind] ?? '', style: const TextStyle(fontSize: 12, color: kMu)),
                ],
              ),
            ),
            if (memCache[g] == 'v') const Tag('زائر'),
            if (dot)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsetsDirectional.only(start: 8),
                decoration: BoxDecoration(shape: BoxShape.circle, color: context.accent),
              ),
          ],
        ),
      ),
    );
  }

  void _newGroup() {
    final nm = TextEditingController();
    var kind = 'main';
    showAppSheet<void>(context, (sc) => [
          StatefulBuilder(builder: (c, set) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('إنشاء قروب', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                TextField(controller: nm, maxLength: 40, decoration: const InputDecoration(hintText: 'اسم القروب', counterText: '')),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kKinds.entries
                      .map((e) => ChoiceChip(
                            label: Text(e.value),
                            selected: kind == e.key,
                            onSelected: (_) => set(() => kind = e.key),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                AppButton('إنشاء', onPressed: () async {
                  final name = nm.text.trim();
                  if (name.isEmpty) {
                    toast('اكتب اسم القروب', bad: true);
                    return;
                  }
                  final g = ref('groups').push().key!;
                  try {
                    await db.ref().update(<String, Object?>{
                      'groups/$g': <String, Object?>{
                        'name': name,
                        'kind': kind,
                        'locked': kind != 'main',
                        'desc': '',
                        'ts': ServerValue.timestamp,
                        'by': myUid,
                      },
                      'members/$g/$myUid': true,
                      if (kind == 'main') 'guildStats/$g': <String, Object?>{'atk': 1, 'def': 1},
                    });
                    if (sc.mounted) Navigator.of(sc).pop();
                    await _reload();
                  } catch (e) {
                    err(e);
                  }
                }),
              ],
            );
          }),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final ids = memCache.keys.where((g) => groupsCache.containsKey(g)).toList();
    final mains = ids.where((g) => groupKind(g) == 'main').toList();
    final system = ids.where((g) => groupKind(g) != 'main').toList();
    final hasMain = mains.any((g) => memCache[g] == true);
    return Scaffold(
      floatingActionButton: Session.isDev
          ? FloatingActionButton(onPressed: _newGroup, child: const Icon(Icons.add))
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: kBg2,
              child: Row(
                children: [
                  UserAvatar(myUid, size: 44, onTap: () => _openSettings()),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(Session.me.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          ),
                          if (Session.isEmp) ...[const SizedBox(width: 6), const InfinityMark()],
                        ]),
                        const SizedBox(height: 3),
                        const BalanceChip(),
                      ],
                    ),
                  ),
                  if (Session.isEmp)
                    TextButton(
                      onPressed: () {
                        prefs.setBool('emp_enter', true);
                        toast('ادخل أي نقابة');
                      },
                      child: Text('دخول', style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800)),
                    ),
                  const GuideButton(),
                  IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShopScreen())), icon: const Icon(Icons.shopping_bag_outlined)),
                  const BellButton(),
                  IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings_outlined)),
                ],
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ValueListenableBuilder<Set<String>>(
                        valueListenable: BellService.mentionGroups,
                        builder: (c, _, __) => ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const EmpChatCard(),
                            if (!hasMain && !Session.isDev)
                              Container(
                                margin: const EdgeInsets.all(12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: accentA(context, .1),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: kLine),
                                ),
                                child: Text(
                                  'أنت في غرفة الانتظار 🔥\nسيضيفك أحد المطورين إلى نقابة، أو سجّل من رابط دعوة عضو.',
                                  style: TextStyle(color: context.accent2, height: 1.8),
                                ),
                              ),
                            if (mains.isNotEmpty) SecCard(title: 'النقابات', children: mains.map(_row).toList()),
                            if (system.isNotEmpty) SecCard(title: 'النظام', children: system.map(_row).toList()),
                            if (ids.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('لا توجد قروبات بعد', style: TextStyle(color: kMu)))),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()))
        .then((_) => mounted ? setState(() {}) : null);
  }
}
