import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'data.dart';
import 'home.dart';
import 'tools.dart' show uidFromPid;
import 'widgets.dart';

String _d(num? ts) {
  final t = ts?.toInt() ?? 0;
  if (t == 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  return '${d.year}/${d.month}/${d.day} ${hhmm(t)}';
}

/// «الحسابات»: بحث باللقب أو الـID وعرض ملف العضو (بدون كلمة السر)
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsState();
}

class _AccountsState extends State<AccountsScreen> {
  final c = TextEditingController();
  List<MapEntry<String, String>> hits = [];
  String? uid;
  Map<String, dynamic>? info;
  bool busy = false;

  Future<void> _search() async {
    final q = normDigits(c.text.trim());
    if (q.isEmpty) return;
    setState(() {
      busy = true;
      info = null;
      uid = null;
      hits = [];
    });
    try {
      final u = await uidFromPid(q);
      if (u != null) {
        await _open(u);
      } else {
        final v = (await ref('profiles').get()).value;
        final l = <MapEntry<String, String>>[];
        if (v is Map) {
          v.forEach((k, x) {
            final n = x is Map ? (x['name'] ?? '').toString() : '';
            if (n.contains(c.text.trim())) l.add(MapEntry(k.toString(), n));
          });
        }
        hits = l.take(30).toList();
        if (hits.isEmpty) toast('لا يوجد نتائج', bad: true);
      }
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _open(String u) async {
    setState(() => busy = true);
    try {
      Future<dynamic> g(String p) async => (await ref(p).get()).value;
      final r = await Future.wait<dynamic>([
        g('profiles/$u'), g('pdata/$u/pid'), g('roles/$u'), g('wallets/$u/bal'), g('seen/$u'),
        g('presence/$u'), g('banned/$u'), g('mod/$u'), g('deviceOf/$u'), g('flags/$u'), g('friends/$u'),
      ]);
      final gs = <String>[];
      for (final x in groupsCache.keys) {
        try {
          if ((await ref('members/$x/$u').get()).value != null) gs.add(groupName(x));
        } catch (_) {}
      }
      info = {
        'p': r[0], 'pid': r[1], 'role': r[2], 'bal': r[3], 'seen': r[4], 'on': r[5], 'ban': r[6], 'mod': r[7],
        'dev': r[8], 'flag': r[9], 'fr': r[10] is Map ? (r[10] as Map).length : 0, 'groups': gs,
      };
      uid = u;
      hits = [];
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _l(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(color: kMu, fontSize: 13)),
          TextSpan(text: v, style: const TextStyle(fontSize: 13.5)),
        ])),
      );

  @override
  Widget build(BuildContext context) {
    final i = info;
    final p = i?['p'] is Map ? Map<String, dynamic>.from(i!['p'] as Map) : <String, dynamic>{};
    final seen = i?['seen'] is Map ? Map<String, dynamic>.from(i!['seen'] as Map) : <String, dynamic>{};
    final mod = i?['mod'] is Map ? Map<String, dynamic>.from(i!['mod'] as Map) : <String, dynamic>{};
    final modUntil = (mod['until'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('الحسابات')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        TextField(
          controller: c,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'اكتب اللقب أو الـID',
            suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search),
          ),
        ),
        const SizedBox(height: 8),
        const Text('ايها المطور رجاءا استعمل هذه الميزة في إسترجاع الحسابات ولا تنتهك حقوق أحد!', style: TextStyle(color: kRed, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.6)),
        if (busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        for (final h in hits)
          ListTile(title: Text(h.value), subtitle: Text(h.key, style: const TextStyle(color: kMu, fontSize: 11)), onTap: () => _open(h.key)),
        if (i != null && uid != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .28), borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                UserAvatar(uid!, size: 46),
                const SizedBox(width: 10),
                Expanded(child: Text((p['name'] ?? '—').toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              ]),
              _l('ID', (i['pid'] ?? '—').toString()),
              _l('الرتبة', i['role'] == 'dev' ? 'مطور' : (uid == Session.emp ? 'إمبراطور' : 'عضو')),
              _l('الجنس', p['gender'] == 'f' ? 'أنثى' : 'ذكر'),
              _l('تاريخ التسجيل', _d(p['ts'] as num?)),
              _l('الرصيد', i['bal'] is num ? fmtN(i['bal'] as num) : '—'),
              _l('الحالة', i['on'] == true ? 'متصل الآن 🟢' : 'غير متصل'),
              _l('آخر ظهور', _d(seen['t'] as num?)),
              _l('نسخة التطبيق', (seen['b'] ?? '—').toString()),
              _l('النقابات', (i['groups'] as List).isEmpty ? '—' : (i['groups'] as List).join('، ')),
              _l('عدد الأصدقاء', '${i['fr']}'),
              _l('حظر التطبيق', i['ban'] != null ? 'محظور ⛔' : 'لا'),
              _l('تقييد الشات', modUntil > DateTime.now().millisecondsSinceEpoch ? 'مقيد حتى ${_d(modUntil)}' : 'لا'),
              _l('جهاز مرتبط', i['dev'] != null ? 'نعم' : 'لا'),
              _l('علامة بيئة مشبوهة', i['flag'] != null ? 'نعم ⚠️' : 'لا'),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: AppButton('نسخ الـUID', kind: 'g', compact: true, onPressed: () {
                  Clipboard.setData(ClipboardData(text: uid!));
                  toast('تم النسخ');
                })),
                const SizedBox(width: 8),
                if (modUntil > DateTime.now().millisecondsSinceEpoch)
                  Expanded(child: AppButton('تحرير التقييد', compact: true, onPressed: () async {
                    try {
                      await ref('mod/$uid/until').set(0);
                      toast('تم التحرير ✅');
                      await _open(uid!);
                    } catch (e) {
                      err(e);
                    }
                  })),
              ]),
              const SizedBox(height: 8),
              const Text('كلمات السر لا تُعرض لأحد — حتى المطورين — لأن من يملكها يدخل بحساب العضو. لمن نسي حسابه استخدم «تحرير الجهاز» من أداة «المقيدون».', style: TextStyle(color: kMu, fontSize: 11.5, height: 1.6)),
            ]),
          ),
      ]),
    );
  }
}

/// حذف أي قروب (يتم الحذف على السيرفر: رسائل، أعضاء، إحصائيات ...)
class DeleteGroupScreen extends StatelessWidget {
  const DeleteGroupScreen({super.key});

  Future<void> _del(BuildContext context, String g) async {
    final ok = await showAppSheet<bool>(context, (sc) => [
          Text('حذف «${groupName(g)}» نهائياً؟', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const Text('تُحذف كل رسائله وأعضائه وإحصائياته ولا يمكن التراجع.', textAlign: TextAlign.center, style: TextStyle(color: kMu, fontSize: 12.5)),
          AppButton('نعم، احذف', kind: 'r', onPressed: () => Navigator.of(sc).pop(true)),
          AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(sc).pop(false)),
        ]);
    if (ok != true) return;
    try {
      await ref('delGroup/$g').set(<String, Object?>{'by': myUid, 'ts': ServerValue.timestamp});
      toast('تم إرسال أمر الحذف للسيرفر ✅');
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = groupsCache.keys.toList()..sort((a, b) => groupName(a).compareTo(groupName(b)));
    return Scaffold(
      appBar: AppBar(title: const Text('حذف قروب')),
      body: ListView(children: [
        for (final g in ks)
          ListTile(
            leading: GroupPhoto(g, size: 36),
            title: Text(groupName(g)),
            subtitle: Text(kKinds[(groupsCache[g]?['kind'] ?? '').toString()] ?? '', style: const TextStyle(color: kMu, fontSize: 12)),
            trailing: const Icon(Icons.delete_outline, color: kRed),
            onTap: () => _del(context, g),
          ),
      ]),
    );
  }
}
