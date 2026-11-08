import 'aichat.dart';
import 'devtools3.dart';
import 'dino.dart';
import 'football.dart';
import 'kingdoms.dart';
import 'viewer.dart';
import 'servertime.dart';
import 'visuals.dart';
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
import 'friends.dart';
import 'board.dart';
import 'update.dart';
import 'support.dart' show checkSupportReply;
import 'ipreport.dart';
import 'empcard.dart';
import 'gift.dart';
import 'unread.dart';
import 'roulette.dart';
import 'vip.dart';
import 'sorter.dart';
import 'status.dart';
import 'widgets.dart';

const Map<String, String> kKinds = {
  'main': 'نقابة',
  'ads': 'إعلانات',
  'shop': 'المتجر',
  'news': 'الصحيفة',
  'upd': 'التحديثات',
  'work': 'الوورك',
  'adm': 'قروب اجتماع',
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
/// اسم جروب الإدارة (قروب اجتماع وليس نقابة)
const String kAdminsName = '𝑨𝑫𝑴𝑰𝑵𝑺';

String groupKind(String g) {
  final m = groupsCache[g];
  if (m != null && (m['adm'] == true || m['name'] == kAdminsName)) return 'adm';
  return (m?['kind'] ?? 'main').toString();
}

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
  final bool viewable;
  const GroupPhoto(this.gid, {super.key, this.size = 46, this.viewable = false});

  @override
  Widget build(BuildContext context) {
    final name = groupName(gid);
    return FutureBuilder<MemoryImage?>(
      future: groupPhoto(gid),
      builder: (c, s) {
        final img = s.data;
        final box = Container(
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
        if (!viewable || img == null) return box;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupPhotoViewer(gid: gid))),
          child: box,
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
          child: Session.isEmp
              ? const Row(mainAxisSize: MainAxisSize.min, children: [CoinIcon(size: 15), SizedBox(width: 4), InfinityMark(size: 15)])
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const CoinIcon(size: 15),
                  const SizedBox(width: 4),
                  Text(fmtN(n), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: neg ? kRed : kTx)),
                ]),
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
  Timer? _boardT;
  Timer? _idleOff;
  StreamSubscription<DatabaseEvent>? presenceSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Session.ensurePid();
    BellService.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkNeedPw(context);
      claimDino();
    });
    _reload().then((_) {
      WarWatcher.start();
      checkVisitExpiry();
      Board.sync();
      if (mounted) checkUpdate(context);
      if (mounted) checkSupportReply(context);
    });
    _boardT = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !appInBackground()) Board.sync();
    });
    Sfx.syncBgm();
    reportIp();
    initPush().then((_) => startBackgroundPolling());
    clearBadge();
    presenceSub = FirebaseDatabase.instance.ref('.info/connected').onValue.listen((e) {
      if (e.snapshot.value == true && myUid.isNotEmpty) {
        final p = ref('presence/$myUid');
        p.onDisconnect().remove();
        p.set(true);
        ref('seen/$myUid/t').onDisconnect().set(ServerValue.timestamp);
        markSeen();
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
      // رجوع للتطبيق: أعد الاتصال بالقاعدة
      _idleOff?.cancel();
      try {
        FirebaseDatabase.instance.goOnline();
      } catch (_) {}
      if (myUid.isNotEmpty) {
        final pr = ref('presence/$myUid');
        pr.onDisconnect().remove();
        pr.set(true);
      }
      reportIp();
      clearBadge();
      Sfx.unblock('bg');
      Board.sync();
      if (mounted) checkUpdate(context);
    } else {
      Sfx.block('bg');
      // يظهر العضو «غير متصل» فور خروجه من التطبيق
      if (st == AppLifecycleState.paused && myUid.isNotEmpty) {
        ref('presence/$myUid').remove().catchError((_) {});
      }
      // التطبيق بالخلفية أكثر من 60 ثانية: اقطع اتصال القاعدة لتوفير حد الـ100 اتصال المجاني.
      // الإشعارات تبقى تصل عبر FCM، وتتزامن الرسائل عند الرجوع. (المطورون يبقون متصلين لمهامهم)
      if (st == AppLifecycleState.paused && !Session.isDev) {
        _idleOff?.cancel();
        _idleOff = Timer(const Duration(seconds: 60), () {
          try {
            FirebaseDatabase.instance.goOffline();
          } catch (_) {}
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    devTimer?.cancel();
    _boardT?.cancel();
    _idleOff?.cancel();
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
                  Row(children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: tint(col, .38), borderRadius: BorderRadius.circular(9)),
                        child: Text(groupName(g),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ),
                    if (dot)
                      Container(
                        margin: const EdgeInsetsDirectional.only(start: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: context.accent, borderRadius: BorderRadius.circular(10)),
                        child: const Text('@', style: TextStyle(color: kDarkText, fontWeight: FontWeight.w900, fontSize: 13)),
                      ),
                    if (kind == 'main') ShieldBadge(until: (groupsCache[g]?['prot'] as num?)?.toInt() ?? 0),
                    UnreadBadge(gid: g),
                  ]),
                  const SizedBox(height: 3),
                  Text(kKinds[kind] ?? '', style: const TextStyle(fontSize: 12, color: kMu)),
                ],
              ),
            ),
            if (memCache[g] == 'v') const Tag('زائر'),
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
                        if (kind == 'main') 'prot': nowMs() + 7 * 86400000,
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: AppButton('🏆 المتصدرون', kind: 'g', compact: true, onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BoardScreen()))),
        ),
      ),
      floatingActionButton: Session.isDev
          ? FloatingActionButton(onPressed: _newGroup, child: const Icon(Icons.add))
          : null,
      body: Stack(children: [
      SafeArea(
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
                                        ]),
                        const SizedBox(height: 3),
                        const Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [BalanceChip(), StatusBadge()]),
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
                  IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FriendsScreen())), icon: const Icon(Icons.person_add_alt_1)),
                  if (Session.isDev) IconButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShopScreen())), icon: const Icon(Icons.shopping_bag_outlined)),
                  const BellButton(),
                  Stack(clipBehavior: Clip.none, children: [
                    IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings_outlined)),
                    // نقطة تنبيه للمطورين: جلسات مشبوهة لم تُراجَع بعد
                    if (Session.isDev)
                      PositionedDirectional(
                        top: 8,
                        end: 8,
                        child: StreamBuilder(
                          stream: ref('susp').onValue,
                          builder: (c, s) {
                            final v = s.data?.snapshot.value;
                            var n = 0;
                            if (v is Map) {
                              v.forEach((k, x) {
                                if (x is Map && x['st'] == null) n++;
                              });
                            }
                            return n > 0 ? Container(width: 11, height: 11, decoration: BoxDecoration(color: kRed, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5))) : const SizedBox.shrink();
                          },
                        ),
                      ),
                  ]),
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
                            const EmperorCard(),
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
                            const KingdomsCard(),
                            if (ids.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('لا توجد قروبات بعد', style: TextStyle(color: kMu)))),
                            SecCard(title: 'المساعد', children: [
                              ListTile(
                                leading: Icon(Icons.smart_toy_outlined, color: context.accent2),
                                title: const Text('مساعد FIR 🤖', style: TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: const Text('اسأله عن أي شيء في التطبيق', style: TextStyle(color: kMu, fontSize: 12)),
                                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AiChatScreen(staff: false))),
                              ),
                            ]),
                            const FriendsSection(),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      Positioned(right: 14, bottom: Session.isDev ? 90 : 12, child: const GiftBox()),
      Positioned(right: 14, bottom: Session.isDev ? 166 : 88, child: const RouletteFab()),
      Positioned(right: 14, bottom: Session.isDev ? 242 : 164, child: const FootballFab()),
      const Positioned(left: 12, bottom: 12, child: SuggestPrompt()),
      ]),
    );
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()))
        .then((_) => mounted ? setState(() {}) : null);
  }
}
