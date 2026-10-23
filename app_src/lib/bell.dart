import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'chat.dart';
import 'data.dart';
import 'home.dart';
import 'widgets.dart';

class NotifItem {
  final String k;
  final Map<String, dynamic> v;
  NotifItem(this.k, this.v);

  String get t => (v['t'] ?? '').toString();
  String get from => (v['from'] ?? '').toString();
  String get g => (v['g'] ?? '').toString();
  String get m => (v['m'] ?? '').toString();
  String get mid => (v['mid'] ?? '').toString();
  String get tx => (v['tx'] ?? '').toString();
  num get a => v['a'] is num ? v['a'] as num : 0;
  int get ts => v['ts'] is num ? (v['ts'] as num).toInt() : 0;
  String get groupLabel => m.isNotEmpty ? m : (g.isNotEmpty ? groupName(g) : 'قروب');
}

String notifText(NotifItem n, String who) {
  switch (n.t) {
    case 'men':
      return 'هناك من ذكر اسمك\n$who ذكرك في «${n.groupLabel}»';
    case 'tr':
      return '$who حوّل لك ${fmtN(n.a)} رصيد';
    case 'add':
      return 'تمت إضافتك إلى «${n.groupLabel}»';
    case 'kick':
      return 'تم طردك من «${n.groupLabel}»';
    case 'mute':
      return 'تم كتمك في «${n.groupLabel}»';
    default:
      return n.tx.isNotEmpty ? n.tx : 'إشعار جديد';
  }
}

IconData notifIcon(String t) {
  switch (t) {
    case 'men':
      return Icons.alternate_email;
    case 'tr':
      return Icons.payments_outlined;
    case 'add':
      return Icons.group_add_outlined;
    case 'kick':
      return Icons.logout;
    case 'mute':
      return Icons.volume_off_outlined;
    case 'war':
    case 'warend':
      return Icons.shield_outlined;
    default:
      return Icons.notifications_none;
  }
}

/// مستمع الإشعارات: notifs/{uid}
class BellService {
  static final Map<String, NotifItem> items = {};
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static final ValueNotifier<Set<String>> mentionGroups = ValueNotifier<Set<String>>(<String>{});
  static StreamSubscription<DatabaseEvent>? _a;
  static StreamSubscription<DatabaseEvent>? _r;
  static String _uid = '';
  static DateTime _startAt = DateTime.now();

  static int get seenTs => prefs.getInt('bell_seen') ?? 0;
  static int get unread => items.values.where((n) => n.ts > seenTs).length;
  static bool get muted => prefs.getBool('mute') ?? false;

  static void start() {
    if (myUid.isEmpty) return;
    if (_uid == myUid && _a != null) return;
    stop();
    _uid = myUid;
    _startAt = DateTime.now();
    final q = ref('notifs/$_uid');
    _a = q.onChildAdded.listen((e) {
      final v = e.snapshot.value;
      final k = e.snapshot.key;
      if (k == null || v is! Map) return;
      final n = NotifItem(k, Map<String, dynamic>.from(v));
      items[k] = n;
      _recompute();
      final live = DateTime.now().difference(_startAt).inSeconds > 3;
      if (live && !muted) {
        prof(n.from).then((p) => toast(notifText(n, p.name).replaceAll('\n', ' • '), accent: true));
      }
    }, onError: (_) {});
    _r = q.onChildRemoved.listen((e) {
      final k = e.snapshot.key;
      if (k == null) return;
      items.remove(k);
      _recompute();
    }, onError: (_) {});
  }

  static void stop() {
    _a?.cancel();
    _r?.cancel();
    _a = null;
    _r = null;
    _uid = '';
    items.clear();
    mentionGroups.value = <String>{};
    tick.value++;
  }

  static void _recompute() {
    mentionGroups.value = items.values.where((n) => n.t == 'men' && n.g.isNotEmpty).map((n) => n.g).toSet();
    tick.value++;
  }

  static void markSeen() {
    var mx = 0;
    for (final n in items.values) {
      if (n.ts > mx) mx = n.ts;
    }
    prefs.setInt('bell_seen', mx);
    tick.value++;
  }

  static Future<void> removeMany(Iterable<String> ks) async {
    final up = <String, Object?>{};
    for (final k in ks) {
      up['notifs/$_uid/$k'] = null;
    }
    if (up.isNotEmpty) await db.ref().update(up);
  }
}

/// زر الجرس مع إشارة برتقالية وعدّاد
class BellButton extends StatelessWidget {
  const BellButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BellService.tick,
      builder: (c, _, __) {
        final n = BellService.unread;
        return IconButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BellScreen())),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none),
              if (n > 0)
                Positioned(
                  top: -5,
                  right: -6,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: context.accent, borderRadius: BorderRadius.circular(9)),
                    child: Text(n > 99 ? '99+' : '$n',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kDarkText)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class BellScreen extends StatefulWidget {
  const BellScreen({super.key});

  @override
  State<BellScreen> createState() => _BellScreenState();
}

class _BellScreenState extends State<BellScreen> {
  bool selecting = false;
  final Set<String> sel = <String>{};

  @override
  void initState() {
    super.initState();
    BellService.markSeen();
    BellService.tick.addListener(_on);
  }

  @override
  void dispose() {
    BellService.tick.removeListener(_on);
    super.dispose();
  }

  void _on() {
    if (mounted) setState(() {});
  }

  List<NotifItem> get list {
    final l = BellService.items.values.toList();
    l.sort((a, b) => b.ts.compareTo(a.ts));
    return l;
  }

  Future<void> _open(NotifItem n) async {
    if (selecting) {
      setState(() => sel.contains(n.k) ? sel.remove(n.k) : sel.add(n.k));
      return;
    }
    try {
      await BellService.removeMany([n.k]);
    } catch (_) {}
    if (!mounted) return;
    if (n.g.isNotEmpty && memCache[n.g] != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(gid: n.g, focusMid: n.mid)));
    }
  }

  Future<void> _delete(Iterable<String> ks) async {
    try {
      await BellService.removeMany(ks.toList());
      sel.clear();
      if (mounted) setState(() => selecting = false);
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = list;
    final muted = BellService.muted;
    return Scaffold(
      appBar: AppBar(
        title: Text(selecting ? 'تحديد (${sel.length})' : 'الإشعارات'),
        actions: [
          IconButton(
            tooltip: 'كتم الإشعارات',
            icon: Icon(muted ? Icons.notifications_off_outlined : Icons.notifications_active_outlined),
            onPressed: () {
              prefs.setBool('mute', !muted);
              setState(() {});
              toast(!muted ? 'تم كتم الإشعارات' : 'تم تفعيل الإشعارات');
            },
          ),
          IconButton(
            tooltip: 'حذف',
            icon: Icon(selecting ? Icons.close : Icons.delete_outline),
            onPressed: () => setState(() {
              selecting = !selecting;
              sel.clear();
            }),
          ),
        ],
      ),
      body: l.isEmpty
          ? const Center(child: Text('لا توجد إشعارات', style: TextStyle(color: kMu)))
          : ListView.builder(
              itemCount: l.length,
              itemBuilder: (c, i) {
                final n = l[i];
                return ListTile(
                  onTap: () => _open(n),
                  leading: selecting
                      ? Checkbox(value: sel.contains(n.k), onChanged: (_) => _open(n))
                      : CircleAvatar(
                          backgroundColor: accentA(context, .18),
                          child: Icon(notifIcon(n.t), color: context.accent2, size: 20),
                        ),
                  title: FutureBuilder<Prof>(
                    future: prof(n.from),
                    builder: (c, s) => Text(notifText(n, s.data?.name ?? '...'), style: const TextStyle(fontSize: 14, height: 1.5)),
                  ),
                  trailing: Text(hhmm(n.ts), style: const TextStyle(fontSize: 11, color: kMu)),
                );
              },
            ),
      bottomNavigationBar: selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(child: AppButton('حذف المحدد (${sel.length})', kind: 'r', onPressed: sel.isEmpty ? null : () => _delete(sel.toList()))),
                    const SizedBox(width: 10),
                    Expanded(child: AppButton('حذف الكل', kind: 'r', onPressed: l.isEmpty ? null : () => _delete(l.map((e) => e.k).toList()))),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
