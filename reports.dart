import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'profile.dart';
import 'widgets.dart';

const List<String> _reasons = ['إساءة أو سب', 'سبام / إزعاج', 'محتوى غير لائق', 'تهديد أو تحرش', 'أخرى'];

/// ابلاغ على دردشة (خاصة أو نقابة أو رسالة): يصل للمطورين مع نسخة من آخر الرسائل كدليل
/// kind: fdm = دردشة صديق، guild = دردشة نقابة، msg = رسالة بعينها، user = ملف عضو
Future<void> reportChat(
  BuildContext context, {
  required String kind,
  String where = '',
  String peer = '',
  String gid = '',
  List<String> lines = const [],
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - (prefs.getInt('rep_last') ?? 0) < 45000) {
    toast('انتظر قليلاً قبل إرسال بلاغ آخر', bad: true);
    return;
  }
  final tx = TextEditingController();
  var reason = _reasons.first;
  final ok = await showAppSheet<bool>(context, (sc) => [
        const Text('🚩 ابلاغ للمطورين', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const Text('يصل البلاغ لكل المطورين مع آخر الرسائل كدليل.', textAlign: TextAlign.center, style: TextStyle(color: kMu, fontSize: 12.5, height: 1.6)),
        StatefulBuilder(
          builder: (c, set) => Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final r in _reasons) ChoiceChip(label: Text(r), selected: reason == r, onSelected: (_) => set(() => reason = r)),
          ]),
        ),
        TextField(controller: tx, maxLength: 200, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'تفاصيل إضافية (اختياري)')),
        AppButton('إرسال البلاغ', kind: 'r', onPressed: () => Navigator.of(sc).pop(true)),
        AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(sc).pop(false)),
      ]);
  if (ok != true) return;
  try {
    final id = ref('reports').push().key!;
    var ex = lines.join('\n');
    if (ex.length > 3500) ex = ex.substring(ex.length - 3500);
    var r = tx.text.trim().isEmpty ? reason : '$reason — ${tx.text.trim()}';
    if (r.length > 300) r = r.substring(0, 300);
    final w = where.length > 80 ? where.substring(0, 80) : where;
    await ref('reports/$id').set(<String, Object?>{
      'u': myUid,
      'ts': ServerValue.timestamp,
      'k': kind,
      'r': r,
      if (peer.isNotEmpty) 'p': peer,
      if (gid.isNotEmpty) 'g': gid,
      if (w.isNotEmpty) 'w': w,
      if (ex.isNotEmpty) 'ex': ex,
    });
    prefs.setInt('rep_last', now);
    toast('تم إرسال البلاغ إلى المطورين ✅');
  } catch (e) {
    err(e);
  }
}

/// بند «البلاغات» في أدوات المطورين مع عدّاد
class ReportsTile extends StatelessWidget {
  const ReportsTile({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('reports').onValue,
      builder: (c, s) {
        final v = s.data?.snapshot.value;
        final n = v is Map ? v.length : 0;
        return ListTile(
          leading: Icon(Icons.flag_outlined, color: n > 0 ? kRed : null),
          title: const Text('البلاغات'),
          subtitle: const Text('بلاغات الأعضاء على الدردشات', style: TextStyle(color: kMu, fontSize: 12)),
          trailing: n > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(12)),
                  child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                )
              : null,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReportsScreen())),
        );
      },
    );
  }
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  String _kindText(String k) {
    switch (k) {
      case 'fdm':
        return 'دردشة صديق';
      case 'guild':
        return 'دردشة نقابة';
      case 'msg':
        return 'رسالة';
      case 'user':
        return 'عضو';
      default:
        return 'دردشة';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البلاغات')),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref('reports').onValue,
        builder: (c, s) {
          final v = s.data?.snapshot.value;
          final rows = <MapEntry<String, Map<String, dynamic>>>[];
          if (v is Map) {
            v.forEach((k, x) {
              if (x is Map) rows.add(MapEntry(k.toString(), Map<String, dynamic>.from(x)));
            });
          }
          rows.sort((a, b) => ((b.value['ts'] as num?) ?? 0).compareTo((a.value['ts'] as num?) ?? 0));
          if (rows.isEmpty) return const Center(child: Text('لا توجد بلاغات', style: TextStyle(color: kMu)));
          return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
            for (final r in rows) _card(context, r.key, r.value),
          ]);
        },
      ),
    );
  }

  Widget _card(BuildContext context, String id, Map<String, dynamic> r) {
    final u = (r['u'] ?? '').toString();
    final p = (r['p'] ?? '').toString();
    final ex = (r['ex'] ?? '').toString();
    final ts = (r['ts'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .28), borderRadius: BorderRadius.circular(14), border: Border.all(color: kRed.withAlpha(120))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.flag_rounded, color: kRed, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text('${_kindText((r['k'] ?? '').toString())}${(r['w'] ?? '').toString().isEmpty ? '' : ' • ${r['w']}'}', style: const TextStyle(fontWeight: FontWeight.w900))),
          Text(ts > 0 ? hhmm(ts) : '', style: const TextStyle(color: kMu, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        FutureBuilder<Prof>(future: prof(u), builder: (c, s) => Text('المبلِّغ: ${s.data?.name ?? '...'}', style: const TextStyle(fontSize: 13))),
        if (p.isNotEmpty) FutureBuilder<Prof>(future: prof(p), builder: (c, s) => Text('المبلَّغ عنه: ${s.data?.name ?? '...'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
        const SizedBox(height: 6),
        Text((r['r'] ?? '').toString(), style: const TextStyle(height: 1.6)),
        if (ex.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('آخر الرسائل (الدليل)', style: TextStyle(fontSize: 13, color: kMu)),
              children: [Align(alignment: AlignmentDirectional.centerStart, child: SelectableText(ex, style: const TextStyle(fontSize: 12.5, height: 1.7)))],
            ),
          ),
        const SizedBox(height: 6),
        Row(children: [
          if (p.isNotEmpty) ...[
            Expanded(child: AppButton('ملف المبلَّغ عنه', kind: 'g', compact: true, onPressed: () => viewProfile(context, p))),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: AppButton('تمت المعالجة ✅', compact: true, onPressed: () async {
              try {
                await ref('reports/$id').remove();
              } catch (e) {
                err(e);
              }
            }),
          ),
        ]),
      ]),
    );
  }
}
