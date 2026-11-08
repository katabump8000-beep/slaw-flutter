import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

// ======================================================================
// أدوات المطورين: شعاري / الإنجازات / السجل / الكشف
// ======================================================================

// ---------- بيانات الشارات الإضافية لكل عضو (إنجاز + شعارات مخفية) ----------
final Map<String, List<Object?>> _bx = <String, List<Object?>>{};

Future<Map<String, dynamic>> badgeExtra(String uid) {
  final c = _bx[uid];
  final n = DateTime.now().millisecondsSinceEpoch;
  if (c != null && n - (c[0] as int) < 180000) return c[1] as Future<Map<String, dynamic>>;
  final f = _loadBadge(uid);
  _bx[uid] = <Object?>[n, f];
  return f;
}

Future<Map<String, dynamic>> _loadBadge(String uid) async {
  try {
    final a = (await ref('pdata/$uid/ach').get()).value;
    final h = (await ref('pdata/$uid/hide').get()).value;
    return <String, dynamic>{
      'ach': a is Map ? Map<String, dynamic>.from(a) : null,
      'hide': h is Map ? Map<String, dynamic>.from(h) : <String, dynamic>{},
    };
  } catch (_) {
    return <String, dynamic>{};
  }
}

void badgeForget(String uid) => _bx.remove(uid);

/// وسم الإنجاز الذي يضعه المطور بجانب اسم العضو في كل رسالة
Widget? achTag(Map<String, dynamic> ex) {
  final a = ex['ach'];
  if (a is! Map) return null;
  final t = (a['t'] ?? '').toString();
  if (t.isEmpty) return null;
  final c = hexOk(a['c']?.toString()) ? hexColor(a['c'].toString()) : const Color(0xFFFFD54A);
  return Tag(t, fg: c);
}

// ---------- شعاري: إظهار/إخفاء الشارات بجانب اسم المطور ----------
class ShiarScreen extends StatefulWidget {
  const ShiarScreen({super.key});

  @override
  State<ShiarScreen> createState() => _ShiarState();
}

class _ShiarState extends State<ShiarScreen> {
  static const List<List<String>> items = [
    ['dev', 'شارة «مطور» / «المؤسس»'],
    ['rank', 'رتبة عليا / الإمبراطور'],
    ['age', 'أسطورة / نخبة / مخضرم / عضو'],
    ['adm', 'مشرف'],
  ];
  Map<dynamic, dynamic> hide = {};
  StreamSubscription<DatabaseEvent>? sub;

  @override
  void initState() {
    super.initState();
    sub = ref('pdata/$myUid/hide').onValue.listen((e) {
      final v = e.snapshot.value;
      if (mounted) setState(() => hide = v is Map ? v : {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  Future<void> _toggle(String k) async {
    final hidden = hide[k] == true;
    try {
      await ref('pdata/$myUid/hide/$k').set(hidden ? null : true);
      badgeForget(myUid);
      toast(hidden ? 'تم اظهار هذا الشعار ✅' : 'تم اخفاء هذا الشعار ✅');
    } catch (e) {
      err(e);
    }
  }

  Widget _preview(String k) {
    switch (k) {
      case 'dev':
        return const DevBadge();
      case 'rank':
        return const Tag('رتبة عليا');
      case 'age':
        return const Tag('أسطورة');
      default:
        return const Tag('مشرف');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('شعاري 🏅')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('هذه الشارات تظهر بجانب اسمك في كل رسالة ترسلها. يمكنك إخفاء ما تشاء منها (الاسم يبقى دائماً).', style: TextStyle(color: kMu, fontSize: 12.5, height: 1.7)),
        const SizedBox(height: 12),
        for (final it in items)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
            child: Row(children: [
              Opacity(opacity: hide[it[0]] == true ? .35 : 1, child: _preview(it[0])),
              const SizedBox(width: 12),
              Expanded(child: Text(it[1], style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
              SizedBox(width: 90, child: AppButton(hide[it[0]] == true ? 'اظهار' : 'اخفاء', compact: true, kind: hide[it[0]] == true ? 'p' : 'g', onPressed: () => _toggle(it[0]))),
            ]),
          ),
      ]),
    );
  }
}

// ---------- الإنجازات: نص ولون يظهر بجانب اسم العضو في كل رسالة ----------
Future<void> editAchievement(BuildContext context, String uid) async {
  Object? cur;
  try {
    cur = (await ref('pdata/$uid/ach').get()).value;
  } catch (_) {}
  final tc = TextEditingController(text: cur is Map ? (cur['t'] ?? '').toString() : '');
  var col = (cur is Map && hexOk(cur['c']?.toString())) ? cur['c'].toString() : '#FFD54A';
  const cols = ['#FFD54A', '#FF6B6B', '#4CE07A', '#4DA3FF', '#C77DFF', '#FF9F43', '#FF6FB5', '#FFFFFF'];
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d2, set) => AlertDialog(
        title: const Text('الإنجازات'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('يظهر هذا النص بجانب اسمه في كل رسالة (مثل كلمة مشرف).', style: TextStyle(fontSize: 12, color: kMu)),
          TextField(controller: tc, maxLength: 16, decoration: const InputDecoration(labelText: 'النص')),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in cols)
              GestureDetector(
                onTap: () => set(() => col = c),
                child: Container(width: 30, height: 30, decoration: BoxDecoration(color: hexColor(c), shape: BoxShape.circle, border: Border.all(color: col == c ? Colors.white : Colors.transparent, width: 3))),
              ),
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await ref('pdata/$uid/ach').remove();
                badgeForget(uid);
                if (d2.mounted) Navigator.pop(d2);
                toast('تم حذف الإنجاز');
              } catch (e) {
                err(e);
              }
            },
            child: const Text('حذف'),
          ),
          TextButton(onPressed: () => Navigator.pop(d2), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              final t = tc.text.trim();
              if (t.isEmpty) {
                toast('اكتب النص', bad: true);
                return;
              }
              try {
                await ref('pdata/$uid/ach').set(<String, Object?>{'t': t, 'c': col});
                badgeForget(uid);
                if (d2.mounted) Navigator.pop(d2);
                toast('تم الحفظ ✅');
              } catch (e) {
                err(e);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}

// ---------- السجل: آخر عمليات الرصيد لعضو ----------
class LedgerScreen extends StatefulWidget {
  final String uid;
  final String name;
  const LedgerScreen({super.key, required this.uid, required this.name});

  @override
  State<LedgerScreen> createState() => _LedgerState();
}

class _LedgerState extends State<LedgerScreen> {
  final List<List<Object>> rows = []; // [نص، وقت]
  bool loading = true;
  bool searching = false;
  String q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    rows.clear();
    try {
      final s = await ref('ledger/${widget.uid}').orderByKey().limitToLast(300).get();
      final v = s.value;
      if (v is Map) {
        final keys = v.keys.map((e) => e.toString()).toList()..sort((a, b) => b.compareTo(a));
        for (final k in keys) {
          final m = v[k];
          if (m is! Map) continue;
          final a = (m['a'] as num?)?.toInt() ?? 0;
          final w = (m['w'] ?? '').toString();
          final ts = (m['ts'] as num?)?.toInt() ?? 0;
          rows.add([a >= 0 ? 'حصل على ${fmtN(a)} من $w' : 'دفع/خسر ${fmtN(-a)} في $w', ts]);
        }
      }
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تصفير السجل'),
        content: Text('هل أنت واثق من حذف سجل ${widget.name} بالكامل؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('نعم')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref('ledger/${widget.uid}').remove();
      toast('تم تصفير السجل ✅');
      await _load();
    } catch (e) {
      err(e);
    }
  }

  String _when(int ts) {
    if (ts == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.year}/${d.month}/${d.day}  ${hhmm(ts)}';
  }

  @override
  Widget build(BuildContext context) {
    final shown = q.isEmpty ? rows : rows.where((r) => (r[0] as String).contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(autofocus: true, decoration: const InputDecoration(hintText: 'ابحث في السجل', border: InputBorder.none), onChanged: (v) => setState(() => q = v.trim()))
            : Text('السجل — ${widget.name}'),
        actions: [
          IconButton(onPressed: () => setState(() { searching = !searching; if (!searching) q = ''; }), icon: Icon(searching ? Icons.close : Icons.search)),
          IconButton(tooltip: 'تصفير السجل', onPressed: _reset, icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFFF6B6B))),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : shown.isEmpty
              ? const Center(child: Text('لا توجد عمليات مسجلة', style: TextStyle(color: kMu)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: shown.length,
                  itemBuilder: (c, i) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine)),
                    child: Row(children: [
                      Expanded(child: Text(shown[i][0] as String, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                      Text(_when(shown[i][1] as int), style: const TextStyle(fontSize: 10.5, color: kMu)),
                    ]),
                  ),
                ),
    );
  }
}

// ---------- كشف: ترتيب أكثر الأعضاء فوزاً/ربحاً وأكثر النقابات فعاليات ----------
class KashfScreen extends StatefulWidget {
  const KashfScreen({super.key});

  @override
  State<KashfScreen> createState() => _KashfState();
}

class _KashfState extends State<KashfScreen> {
  Map<dynamic, dynamic>? d;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    ref('stats/top').get().then((s) {
      final v = s.value;
      if (mounted) {
        setState(() {
          d = v is Map ? v : null;
          loading = false;
        });
      }
    }).catchError((Object e) {
      if (mounted) setState(() => loading = false);
    });
  }

  Widget _section(BuildContext c, String title, String unit, dynamic list) {
    final l = list is List ? list : <dynamic>[];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c.accent2)),
        const SizedBox(height: 8),
        if (l.isEmpty) const Text('لا توجد بيانات بعد', style: TextStyle(color: kMu, fontSize: 12.5)),
        for (var i = 0; i < l.length; i++)
          if (l[i] is Map)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 26, child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: i < 3 ? const Color(0xFFFFD54A) : kMu))),
                Expanded(child: Text((l[i]['n'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                Text('${fmtN((l[i]['v'] as num?)?.toInt() ?? 0)} $unit', style: const TextStyle(fontSize: 12.5, color: kMu)),
              ]),
            ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = (d?['t'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('كشف')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? const Center(child: Text('لم تُحسب الإحصائيات بعد، حاول بعد قليل', style: TextStyle(color: kMu)))
              : ListView(padding: const EdgeInsets.all(14), children: [
                  _section(context, '🏆 أكثر الأعضاء فوزاً', 'فوز', d!['wins']),
                  _section(context, '💰 أكثر الأعضاء رصيداً', 'رصيد', d!['money']),
                  _section(context, '🎮 أكثر النقابات إنشاءً للفعاليات', 'فعالية', d!['guilds']),
                  if (t > 0) Center(child: Text('آخر تحديث: ${hhmm(t)}', style: const TextStyle(color: kMu, fontSize: 11))),
                ]),
    );
  }
}
