import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'core.dart';
import 'data.dart';
import 'emp.dart';
import 'guildtools.dart';
import 'update.dart';
import 'idedit.dart';
import 'home.dart';
import 'media.dart';
import 'quiz.dart';
import 'sfx.dart';
import 'sorter.dart';
import 'tally.dart';
import 'widgets.dart';

// ---------- حماية النسخة بشهادة التوقيع ----------
const MethodChannel _ch = MethodChannel('fir/sig');

Future<String> appSig() async {
  try {
    return (await _ch.invokeMethod<String>('sig')) ?? '';
  } catch (_) {
    return '';
  }
}

Future<bool> integrityOk() async {
  if (Session.isDev) return true;
  try {
    final v = (await ref('config/hashes/sig').get()).value;
    final ok = <String>[];
    if (v is Map) ok.addAll(v.values.map((e) => e.toString()));
    if (v is List) ok.addAll(v.where((e) => e != null).map((e) => e.toString()));
    if (ok.isEmpty) return true;
    final cur = await appSig();
    if (cur.isEmpty || ok.contains(cur)) return true;
    ref('tamper/$myUid').set(ServerValue.timestamp);
    return false;
  } catch (_) {
    return true;
  }
}

Future<void> approveSig() async {
  final cur = await appSig();
  if (cur.isEmpty) {
    toast('تعذر قراءة توقيع التطبيق', bad: true);
    return;
  }
  try {
    final v = (await ref('config/hashes/sig').get()).value;
    var n = 0;
    if (v is Map) {
      if (v.values.map((e) => e.toString()).contains(cur)) {
        toast('هذه النسخة معتمدة بالفعل');
        return;
      }
      n = v.length;
    }
    await ref('config/hashes/sig/$n').set(cur);
    toast('تم اعتماد توقيع النسخة ✅');
  } catch (e) {
    err(e);
  }
}

String _fmtTs(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.year}/${d.month}/${d.day} ${hhmm(ts)}';
}

/// جلب uid من ID مكوّن من 9 أرقام
Future<String?> uidFromPid(String raw) async {
  final t = normDigits(raw.trim());
  if (!RegExp(r'^\d{4,12}$').hasMatch(t)) return null;
  try {
    final s = await ref('pids/$t').get();
    return s.exists ? s.value.toString() : null;
  } catch (_) {
    return null;
  }
}

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});
  @override
  State<ToolsScreen> createState() => _ToolsState();
}

class _ToolsState extends State<ToolsScreen> {
  Future<void> _byId(String title, Future<void> Function(String uid, String name) act) async {
    final c = TextEditingController();
    await showAppSheet<void>(context, (sc) => [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          TextField(controller: c, keyboardType: TextInputType.number, maxLength: 12, decoration: const InputDecoration(hintText: 'ID المستخدم', counterText: '')),
          AppButton('متابعة', onPressed: () async {
            final u = await uidFromPid(c.text);
            if (u == null) {
              toast('ID غير موجود', bad: true);
              return;
            }
            final p = await prof(u);
            if (sc.mounted) Navigator.of(sc).pop();
            await act(u, p.name);
          }),
        ]);
  }

  void _pride() => _byId('درجة الفخر', (u, name) async {
        var cur = 100;
        try {
          final s = await ref('pride/$u').get();
          if (s.value is num) cur = (s.value as num).toInt();
        } catch (_) {}
        final c = TextEditingController(text: '$cur');
        if (!mounted) return;
        await showAppSheet<void>(context, (sc) => [
              Text('درجة فخر $name', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Center(child: Text('الحالية: $cur%', style: const TextStyle(color: kMu))),
              TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'القيمة الجديدة 0-100')),
              AppButton('حفظ', onPressed: () async {
                final v = int.tryParse(normDigits(c.text));
                if (v == null || v < 0 || v > 100) {
                  toast('قيمة بين 0 و 100', bad: true);
                  return;
                }
                try {
                  await ref('pride/$u').set(v);
                  if (v < 40) {
                    final up = <String, Object?>{'wallets/$u/bal': 0};
                    if (u != Session.emp) {
                      up['roles/$u'] = null;
                      up['devs/$u'] = null;
                      for (final g in groupsCache.keys) {
                        up['groupAdmins/$g/$u'] = null;
                      }
                    }
                    await db.ref().update(up);
                  }
                  if (sc.mounted) Navigator.of(sc).pop();
                  toast('تم ✅');
                } catch (e) {
                  err(e);
                }
              }),
            ]);
      });

  void _support() => _byId('تعيين مسؤول الدعم', (u, name) async {
        try {
          await ref('config/support').set(u);
          toast('تم تعيين $name مسؤولاً عن الدعم ✅');
        } catch (e) {
          err(e);
        }
      });

  void _hour() async {
    final c = TextEditingController();
    try {
      final v = (await ref('meta/tallyHour').get()).value;
      c.text = v is num ? '${v.toInt()}' : '23';
    } catch (_) {}
    if (!mounted) return;
    showAppSheet<void>(context, (sc) => [
          const Text('ساعة الحسبة اليومية (0-23)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          TextField(controller: c, keyboardType: TextInputType.number),
          AppButton('حفظ', onPressed: () async {
            final v = int.tryParse(normDigits(c.text));
            if (v == null || v < 0 || v > 23) {
              toast('0 إلى 23', bad: true);
              return;
            }
            try {
              await ref('meta/tallyHour').set(v);
              if (sc.mounted) Navigator.of(sc).pop();
              toast('تم الحفظ ✅');
            } catch (e) {
              err(e);
            }
          }),
        ]);
  }

  Widget _t(IconData i, String t, VoidCallback f, {String? sub}) =>
      ListTile(leading: Icon(i), title: Text(t), subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: kMu, fontSize: 12)), onTap: f);

  @override
  Widget build(BuildContext context) {
    final emp = Session.isEmp;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: Text(emp ? 'أدوات الإمبراطور' : 'أدوات المطورين')),
      body: ListView(children: [
        _t(Icons.casino_outlined, 'الفعاليات ⚙️', () => go(const QuizAdminScreen()), sub: 'صور الحيوانات والشخصيات'),
        _t(Icons.bar_chart, 'الإحصائيات', () => go(const StatsScreen())),
        _t(Icons.people_alt_outlined, 'الفرز', () => go(const SorterScreen()), sub: 'كل المستخدمين، النسخة، آخر ظهور، حذف'),
        _t(Icons.shield_outlined, 'درجة الفخر (بالـID)', _pride),
        _t(Icons.badge_outlined, 'تعديل معرّفات', () => go(EmpScreen(canAppoint: emp)), sub: 'ابحث عن أي مستخدم وعدّل معرّفه'),
        _t(Icons.edit_outlined, 'تعديل معرّفي', () => editPidDialog(context, myUid)),
        if (emp) ...[
          const Divider(),
          _t(Icons.block, 'المقيدون', () => go(const RestrictedScreen()), sub: 'من ظهرت له رسالة «لا يمكن إنشاء حساب آخر»'),
          _t(Icons.restart_alt, 'تصفير المتصدرين', () async {
            final ok = await showAppSheet<bool>(context, (sc) => [
                  const Text('هل أنت متأكد من تصفير المتصدرين؟', style: TextStyle(fontSize: 16)),
                  AppButton('نعم، صفّر', kind: 'r', onPressed: () => Navigator.of(sc).pop(true)),
                  AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(sc).pop(false)),
                ]);
            if (ok == true) await resetLeaderboard();
          }),
          _t(Icons.schedule, 'ساعة الحسبة اليومية', _hour),
          _t(Icons.merge_type, 'دمج نقابات', () => mergeGuilds(context), sub: 'نقل الأعضاء إلى نقابة واحدة باسم جديد'),
          _t(Icons.tune, 'تعديل مستوى النقابة', () => editGuildLevels(context), sub: 'الهجوم والدفاع'),
          _t(Icons.science_outlined, 'تجارب', () => warTrial(context), sub: 'عرض الحرب عندك فقط'),
          _t(Icons.system_update, 'نشر تحديث', () => publishUpdateSheet(context), sub: 'يظهر للأعضاء عند فتح التطبيق'),
          _t(Icons.support_agent, 'تعيين مسؤول الدعم', _support, sub: 'يصله إشعار البلاغات'),
          _t(Icons.library_music_outlined, 'تعيين موسيقى بالخلفية', () => uploadBgm(), sub: 'مستوى الصوت 15%'),
          _t(Icons.help_outline, 'التعليمات (فيديو)', () => uploadVideo('guide'), sub: 'يظهر عند الضغط على 🔽'),
          _t(Icons.slideshow, 'حالة الإمبراطور (فيديو)', () => uploadVideo('status'), sub: 'يظهر عند الضغط على صورتك'),
          _t(Icons.verified_user_outlined, 'اعتماد هذه النسخة', approveSig, sub: 'يقفل أي نسخة معدّلة على الأعضاء'),
        ],
      ]),
    );
  }
}

class RestrictedScreen extends StatefulWidget {
  const RestrictedScreen({super.key});
  @override
  State<RestrictedScreen> createState() => _RestrictedState();
}

class _RestrictedState extends State<RestrictedScreen> {
  List<MapEntry<String, Map<String, dynamic>>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = (await ref('restricted').get()).value;
      final l = <MapEntry<String, Map<String, dynamic>>>[];
      if (v is Map) v.forEach((k, x) => x is Map ? l.add(MapEntry(k.toString(), Map<String, dynamic>.from(x))) : null);
      l.sort((a, b) => ((b.value['ts'] as num?) ?? 0).compareTo((a.value['ts'] as num?) ?? 0));
      rows = l;
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('المقيدون (${rows.length})')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? const Center(child: Text('لا يوجد مقيدون', style: TextStyle(color: kMu)))
              : ListView(children: [
                  for (final r in rows)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .25), borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('حاول التسجيل بلقب: ${r.value['n']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        FutureBuilder<Prof>(future: prof((r.value['o'] ?? '').toString()), builder: (c, s) => Text('صاحب الحساب الأصلي: ${s.data?.name ?? '...'}', style: const TextStyle(color: kMu))),
                        Text(_fmtTs(((r.value['ts'] as num?) ?? 0).toInt()), style: const TextStyle(color: kMu, fontSize: 12)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: AppButton('تحرير الجهاز', kind: 'g', compact: true, onPressed: () async {
                            try {
                              await ref('devices/${r.value['h']}').remove();
                              toast('تم تحرير الجهاز');
                            } catch (e) {
                              err(e);
                            }
                          })),
                          const SizedBox(width: 8),
                          Expanded(child: AppButton('حذف السجل', kind: 'r', compact: true, onPressed: () async {
                            try {
                              await ref('restricted/${r.key}').remove();
                              await _load();
                            } catch (e) {
                              err(e);
                            }
                          })),
                        ]),
                      ]),
                    ),
                ]),
    );
  }
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsState();
}

class _StatsState extends State<StatsScreen> {
  int users = 0, online = 0, installs = 0, noLink = 0, groups = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = (await ref('profiles').get()).value;
      users = p is Map ? p.length : 0;
      final o = (await ref('presence').get()).value;
      online = o is Map ? o.length : 0;
      groups = groupsCache.length;
      final i = (await ref('installs').get()).value;
      if (i is Map) {
        installs = i.length;
        final keys = i.keys.map((e) => e.toString()).take(400).toList();
        final res = await Future.wait(keys.map((h) => ref('devices/$h').get().then((s) => s.exists).catchError((_) => true)));
        noLink = res.where((x) => !x).length;
      }
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Widget _row(String t, int v) => ListTile(title: Text(t), trailing: Text('$v', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: context.accent2)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإحصائيات'), actions: [IconButton(onPressed: () {
        setState(() => loading = true);
        _load();
      }, icon: const Icon(Icons.refresh))]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              _row('عدد المستخدمين', users),
              _row('المتصلون الآن', online),
              _row('القروبات', groups),
              _row('حمّلوا التطبيق', installs),
              _row('حمّلوه ولم يدخلوا عبر رابط', noLink),
              const Padding(padding: EdgeInsets.all(16), child: Text('المساحة المستخدمة: Firebase ← Realtime Database ← Usage', style: TextStyle(color: kMu, height: 1.8))),
            ]),
    );
  }
}

/// مهام المطورين الدورية (حرب، حسبة، فخر، سجل الدخول)
Future<void> postJoinLogs() async {
  try {
    final w = feedGid('work');
    if (w == null) return;
    final v = (await ref('joinLog').get()).value;
    if (v is! Map) return;
    for (final e in v.entries) {
      final x = e.value;
      if (x is! Map || x['posted'] == true) continue;
      final u = e.key.toString();
      final inv = (x['i'] ?? '').toString();
      final name = (await prof(u)).name;
      final iname = (await prof(inv)).name;
      var cnt = 0;
      try {
        final c = (await ref('pubCount/$inv').get()).value;
        cnt = c is num ? c.toInt() : 0;
      } catch (_) {}
      await botSay(w, '👋 دخل $name إلى ${groupName((x['g'] ?? '').toString())} من طرف $iname\n💰 المكافأة: 200 للداعي\n📣 عدد نشر $iname: $cnt', k: 'note');
      await ref('joinLog/$u/posted').set(true);
    }
  } catch (_) {}
}
