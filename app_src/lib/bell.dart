import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'profile.dart';
import 'widgets.dart';

/// إشعار واحد (من notifs أو sus أو reports)
class NotifItem {
  final String src; // n = notifs, s = sus, r = reports
  final String k;
  final Map<String, dynamic> v;
  NotifItem(this.src, this.k, this.v);

  int get ts => v['ts'] is num ? (v['ts'] as num).toInt() : 0;
  String get t => src == 's' ? 'sus' : (v['t'] ?? '').toString();
  String get from => (v['from'] ?? '').toString();
  String get m => (v['m'] ?? '').toString();
  num get a => v['a'] is num ? v['a'] as num : 0;
}

class NotifText {
  final String plain;
  final String text;
  final IconData icon;
  const NotifText(this.plain, this.text, this.icon);
}

String _or(String s, String d) => s.isEmpty ? d : s;

/// نص الإشعار حسب نوعه
NotifText notifLine(NotifItem n, String name) {
  final a = fmtN(n.a);
  switch (n.t) {
    case 'fr':
      return NotifText('طلب صداقة جديد', 'أرسل لك $name طلب صداقة', Icons.person_add);
    case 'tr':
      return NotifText('وصلك رصيد $a', 'وصلك رصيد $a من $name', Icons.swap_horiz);
    case 'sus':
      return NotifText('حساب مشبوه', 'حساب مشبوه: $name', Icons.warning_amber);
    case 'men':
      return NotifText('منشن', 'ذكرك $name في «${_or(n.m, 'نقابة')}»', Icons.alternate_email);
    case 'gift':
      return NotifText('هدية', 'وصلتك هدية من $name', Icons.card_giftcard);
    default:
      final m = _or(n.m, 'إشعار');
      return NotifText(m, m, Icons.notifications);
  }
}

/// يراقب الإشعارات ويحسب غير المقروء
class BellService {
  static final Map<String, NotifItem> items = {};
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);
  static int seen = 0;
  static final List<StreamSubscription<DatabaseEvent>> _subs = [];

  static void start() {
    stop();
    unread.value = 0;
    seen = prefs.getInt('bell_seen_$myUid') ?? 0;
    _subs.add(ref('notifs/$myUid').onChildAdded.listen((e) => _add('n', e.snapshot), onError: (_) {}));
    if (Session.isDev) {
      _subs.add(ref('sus').onChildAdded.listen((e) => _add('s', e.snapshot), onError: (_) {}));
      _subs.add(ref('reports').onChildAdded.listen((e) => _add('r', e.snapshot), onError: (_) {}));
    }
  }

  static void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    items.clear();
  }

  static void _add(String src, DataSnapshot s) {
    final v = s.value;
    final key = s.key;
    if (v is! Map || key == null) return;
    final id = '$src$key';
    if (items.containsKey(id)) return;
    final n = NotifItem(src, key, Map<String, dynamic>.from(v));
    items[id] = n;
    unread.value = items.values.where((x) => x.ts > seen).length;
    final fresh = n.ts > seen && DateTime.now().millisecondsSinceEpoch - n.ts < 20000;
    if (fresh && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      toast(notifLine(n, '').plain, accent: true);
    }
  }

  static void markSeen() {
    seen = DateTime.now().millisecondsSinceEpoch + 5000;
    prefs.setInt('bell_seen_$myUid', seen);
    unread.value = 0;
  }
}

/// أيقونة الجرس مع عدّاد غير المقروء
class BellButton extends StatelessWidget {
  final VoidCallback onTap;
  const BellButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color.fromRGBO(255, 255, 255, .06),
            ),
            child: const Icon(Icons.notifications_none, size: 22),
          ),
        ),
        Positioned(
          top: -3,
          left: -3,
          child: ValueListenableBuilder<int>(
            valueListenable: BellService.unread,
            builder: (context, n, _) {
              if (n <= 0) return const SizedBox.shrink();
              return Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(9)),
                child: Text(
                  n > 99 ? '99+' : '$n',
                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class BellScreen extends StatefulWidget {
  const BellScreen({super.key});

  @override
  State<BellScreen> createState() => _BellScreenState();
}

class _BellScreenState extends State<BellScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => BellService.markSeen());
  }

  @override
  Widget build(BuildContext context) {
    final items = BellService.items.values.toList()..sort((a, b) => b.ts.compareTo(a.ts));
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: items.isEmpty
          ? const Center(child: Text('لا توجد إشعارات', style: TextStyle(color: kMu)))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (c, i) => NotifRow(
                key: ValueKey('${items[i].src}${items[i].k}'),
                n: items[i],
                onRemoved: () => setState(() {}),
              ),
            ),
    );
  }
}

class NotifRow extends StatefulWidget {
  final NotifItem n;
  final VoidCallback onRemoved;
  const NotifRow({super.key, required this.n, required this.onRemoved});

  @override
  State<NotifRow> createState() => _NotifRowState();
}

class _NotifRowState extends State<NotifRow> {
  String text = '...';
  bool done = false;

  @override
  void initState() {
    super.initState();
    _name();
  }

  void _set(String name) {
    if (mounted) setState(() => text = notifLine(widget.n, name).text);
  }

  Future<void> _name() async {
    final n = widget.n;
    if (n.src == 's') {
      _set((await prof(n.k)).name);
    } else if (n.src == 'r') {
      final a = await prof(n.from);
      final b = await prof(n.v['tg']?.toString() ?? '');
      if (mounted) {
        setState(() => text = 'بلاغ: ${a.name} أبلغ عن ${b.name} — ${n.v['r'] ?? ''}');
      }
    } else if (n.from.isNotEmpty) {
      _set((await prof(n.from)).name);
    } else {
      _set('');
    }
  }

  Future<void> _accept() async {
    final n = widget.n;
    try {
      await db.ref().update(<String, Object?>{
        'friends/$myUid/${n.from}': true,
        'friends/${n.from}/$myUid': true,
        'freq/$myUid/${n.from}': null,
        'notifs/$myUid/${n.k}': null,
      });
      if (mounted) setState(() => done = true);
      toast('تمت إضافة الصديق', accent: true);
    } catch (e) {
      err(e);
    }
  }

  Future<void> _ignore() async {
    final n = widget.n;
    try {
      await db.ref().update(<String, Object?>{
        'freq/$myUid/${n.from}': null,
        'notifs/$myUid/${n.k}': null,
      });
      BellService.items.remove('n${n.k}');
      widget.onRemoved();
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.n;
    final line = notifLine(n, '');
    final isReq = n.t == 'fr' && n.src == 'n' && !done;
    return Opacity(
      opacity: done ? .5 : 1,
      child: InkWell(
        onTap: n.src == 'r' ? () => viewProfile(context, n.v['tg']?.toString() ?? '') : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color.fromRGBO(255, 190, 140, .1))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(line.icon, color: context.accent2, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.7)),
                    if (n.ts > 0)
                      Text(hhmm(n.ts), style: const TextStyle(fontSize: 11, color: kMu)),
                    if (isReq)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            AppButton('قبول', compact: true, onPressed: _accept),
                            const SizedBox(width: 8),
                            AppButton('تجاهل', kind: 'g', compact: true, onPressed: _ignore),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
