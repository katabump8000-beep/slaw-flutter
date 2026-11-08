import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'pwchange.dart';
import 'servertime.dart';
import 'widgets.dart';

// ======================================================================
// كلمة سر مؤقتة + اقتراحات الأعضاء
// ======================================================================

String _pwErr(String e) {
  switch (e) {
    case 'perm':
      return 'هذه الميزة للمطورين فقط';
    case 'emp':
      return 'لا يمكن تعيين كلمة سر لحساب الإمبراطور';
    case 'dev':
      return 'حساب مطور: تعيين كلمة سره للإمبراطور وحده';
    case 'used':
      return 'هذه الكلمة مستعملة عند حساب آخر، اختر غيرها';
    case 'bad':
      return 'كلمة السر من 6 إلى 40 حرفاً';
    case 'rules':
      return 'قواعد قاعدة البيانات لم تُحدَّث بعد (pwReq)';
    case 'net':
      return 'لا يوجد اتصال بالإنترنت';
    case 'timeout':
      return 'سيرفر المنصة لا يستجيب الآن، حاول بعد دقيقة';
    default:
      return 'تعذر تنفيذ الطلب';
  }
}

/// المطور يعيّن كلمة سر مؤقتة لعضو فقد حسابه (التنفيذ على السيرفر)
Future<void> setTempPassword(BuildContext context, String uid, String name) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('كلمة سر مؤقتة لـ $name'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('اكتب كلمة سر مؤقتة (6 أحرف على الأقل) وأعطها للعضو. عند دخوله سيظهر له: «ضع كلمة سرك الجديدة!».', style: TextStyle(fontSize: 12, color: kMu, height: 1.6)),
        TextField(controller: c, maxLength: 40, decoration: const InputDecoration(labelText: 'الكلمة المؤقتة')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('تعيين')),
      ],
    ),
  );
  final pw = c.text.trim();
  if (ok != true) return;
  if (pw.length < 6) {
    toast('6 أحرف على الأقل', bad: true);
    return;
  }
  final rid = ref('pwReq').push().key!;
  final done = Completer<Map<dynamic, dynamic>>();
  final sub = ref('pwRes/$myUid').onValue.listen((e) {
    final v = e.snapshot.value;
    if (v is Map && v['id'] == rid && !done.isCompleted) done.complete(v);
  }, onError: (_) {});
  String why = '';
  try {
    await ref('pwReq/$rid').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 't': uid, 'p': pw}).timeout(const Duration(seconds: 8));
  } catch (e) {
    why = e.toString().toLowerCase().contains('permission') ? 'rules' : 'net';
  }
  Map<dynamic, dynamic>? r;
  if (why.isEmpty) {
    try {
      r = await done.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      r = null;
    }
  }
  await sub.cancel();
  final e = r == null ? (why.isNotEmpty ? why : 'timeout') : (r['err'] ?? '').toString();
  if (e.isEmpty) {
    toast('تم تعيين الكلمة المؤقتة ✅ أعطها للعضو', accent: true);
  } else {
    toast(_pwErr(e), bad: true);
  }
}

/// عند دخول العضو بعد كلمة مؤقتة: «ضع كلمة سرك الجديدة!»
Future<void> checkNeedPw(BuildContext context) async {
  try {
    final v = (await ref('needPw/$myUid').get()).value;
    if (v == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        title: const Text('ضع كلمة سرك الجديدة!'),
        content: const Text('تم تعيين كلمة سر مؤقتة لحسابك. اختر الآن كلمة سر جديدة لا يعرفها غيرك.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('لاحقاً')),
          TextButton(
            onPressed: () async {
              Navigator.pop(d);
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen()));
              try {
                await ref('needPw/$myUid').remove();
              } catch (_) {}
            },
            child: const Text('تعيين الآن'),
          ),
        ],
      ),
    );
  } catch (_) {}
}

// ---------- اقتراح للمطورين: نافذة صغيرة جداً، مرة في الأسبوع ----------
class SuggestPrompt extends StatefulWidget {
  const SuggestPrompt({super.key});

  @override
  State<SuggestPrompt> createState() => _SuggestPromptState();
}

class _SuggestPromptState extends State<SuggestPrompt> {
  bool show = false;
  Timer? t;

  @override
  void initState() {
    super.initState();
    final last = prefs.getInt('sg_last') ?? 0;
    if (!Session.isDev && DateTime.now().millisecondsSinceEpoch - last > 7 * 86400000) {
      t = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => show = true);
      });
    }
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  void _close() {
    prefs.setInt('sg_last', DateTime.now().millisecondsSinceEpoch);
    if (mounted) setState(() => show = false);
  }

  Future<void> _write() async {
    final c = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('اقتراحك للمطورين'),
        content: TextField(controller: c, maxLength: 300, maxLines: 4, decoration: const InputDecoration(hintText: 'اكتب اقتراحك هنا')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('إرسال')),
        ],
      ),
    );
    final txt = c.text.trim();
    if (go != true || txt.isEmpty) return;
    try {
      await ref('suggest/${ref('suggest').push().key}').set(<String, Object?>{'u': myUid, 't': txt, 'ts': ServerValue.timestamp});
      toast('شكراً! وصل اقتراحك للمطورين ✅', accent: true);
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        decoration: BoxDecoration(color: const Color(0xE61E1E1E), borderRadius: BorderRadius.circular(22), border: Border.all(color: kLine)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('هل تملك اقتراح للمطورين؟', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              _close();
              _write();
            },
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: context.accent, borderRadius: BorderRadius.circular(12)), child: const Text('املك', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Colors.black))),
          ),
          IconButton(onPressed: _close, visualDensity: VisualDensity.compact, iconSize: 16, padding: const EdgeInsets.all(4), constraints: const BoxConstraints(), icon: const Icon(Icons.close)),
        ]),
      ),
    );
  }
}

/// صندوق الاقتراحات للمطورين
class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  State<SuggestionsScreen> createState() => _SuggestionsState();
}

class _SuggestionsState extends State<SuggestionsScreen> {
  final List<List<Object>> rows = []; // [key, uid, نص، ts]
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    rows.clear();
    try {
      final s = await ref('suggest').orderByKey().limitToLast(100).get();
      final v = s.value;
      if (v is Map) {
        final ks = v.keys.map((e) => e.toString()).toList()..sort((a, b) => b.compareTo(a));
        for (final k in ks) {
          final m = v[k];
          if (m is Map) rows.add([k, (m['u'] ?? '').toString(), (m['t'] ?? '').toString(), (m['ts'] as num?)?.toInt() ?? 0]);
        }
      }
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الاقتراحات 💡')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? const Center(child: Text('لا توجد اقتراحات', style: TextStyle(color: kMu)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: rows.length,
                  itemBuilder: (c, i) {
                    final r = rows[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          UserAvatar(r[1] as String, size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FutureBuilder<dynamic>(
                              future: prof(r[1] as String),
                              builder: (c2, s) => Text(s.data == null ? '...' : (s.data as dynamic).name.toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                          Text(hhmm(r[3] as int), style: const TextStyle(fontSize: 11, color: kMu)),
                          IconButton(
                            onPressed: () async {
                              try {
                                await ref('suggest/${r[0]}').remove();
                                setState(() => rows.removeAt(i));
                              } catch (e) {
                                err(e);
                              }
                            },
                            icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFFF6B6B)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(r[2] as String, style: const TextStyle(height: 1.6)),
                      ]),
                    );
                  },
                ),
    );
  }
}
