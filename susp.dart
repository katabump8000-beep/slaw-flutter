import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data.dart';
import 'sorter.dart' show kPkg;
import 'widgets.dart';

/// قرار المطورين على الجهاز: allow / ban / '' (لم يُراجع)
Future<String> suspStatus(String h) async {
  try {
    final v = (await ref('susp/$h/st').get()).value;
    return v?.toString() ?? '';
  } catch (_) {
    return '';
  }
}

String _clip(String s, int n) => s.length > n ? s.substring(0, n) : s;
String _short(String s) => s.length > 8 ? s.substring(0, 8) : s;

/// تسجيل جلسة مشبوهة (قبل تسجيل الدخول): بصمة الجهاز + مؤشرات الاشتباه + اسم تطبيق الاستنساخ إن أمكن
Future<void> reportSuspect(String h) async {
  try {
    final d = (await getApplicationSupportDirectory()).path;
    final ind = <String>[];
    var host = '';
    final m = RegExp(r'^/data/(?:user/(\d+)|data)/([^/]+)/').firstMatch(d);
    if (m != null) {
      host = m.group(2) ?? '';
      if (host != kPkg) ind.add('يعمل داخل تطبيق آخر: $host');
      final u = int.tryParse(m.group(1) ?? '0') ?? 0;
      if (u > 0) ind.add('مستخدم أندرويد ثانوي رقم $u');
    } else {
      ind.add('مسار بيانات غير معتاد');
    }
    try {
      final st = await File('/proc/self/status').readAsString();
      final mm = RegExp(r'Uid:\s+(\d+)').firstMatch(st);
      if (mm != null && (int.tryParse(mm.group(1)!) ?? 0) >= 100000) ind.add('معرّف تشغيل ثانوي (نسخة مزدوجة)');
    } catch (_) {}
    try {
      final cl = await File('/proc/self/cmdline').readAsString();
      final proc = cl.split('\u0000').first.trim();
      if (proc.isNotEmpty && !proc.startsWith(kPkg)) ind.add('اسم العملية: $proc');
    } catch (_) {}
    if (d.toLowerCase().contains('virtual') || d.toLowerCase().contains('clone') || d.toLowerCase().contains('parallel')) ind.add('كلمات استنساخ في المسار');
    await ref('susp/$h').update(<String, Object?>{
      'ts': ServerValue.timestamp,
      'n': ServerValue.increment(1),
      'os': _clip(Platform.operatingSystemVersion, 100),
      'p': _clip(d, 160),
      'app': _clip(host, 80),
      'ind': _clip(ind.join(' • '), 200),
    });
  } catch (_) {}
}

/// بند «الجلسات المشبوهة» في أدوات المطورين مع عدّاد ما لم يُراجَع
class SuspTile extends StatelessWidget {
  const SuspTile({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: ref('susp').onValue,
      builder: (c, s) {
        final v = s.data?.snapshot.value;
        var n = 0;
        if (v is Map) {
          v.forEach((k, x) {
            if (x is Map && x['st'] == null) n++;
          });
        }
        return ListTile(
          leading: Icon(Icons.warning_amber_rounded, color: n > 0 ? kRed : null),
          title: const Text('الجلسات المشبوهة'),
          subtitle: const Text('نسخ مستنسخة حاولت الدخول', style: TextStyle(color: kMu, fontSize: 12)),
          trailing: n > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(12)),
                  child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                )
              : null,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SuspScreen())),
        );
      },
    );
  }
}

class SuspScreen extends StatelessWidget {
  const SuspScreen({super.key});

  Future<void> _decide(String h, String st) async {
    try {
      await ref('susp/$h').update(<String, Object?>{'st': st, 'by': myUid, 'at': ServerValue.timestamp});
      await ref('suspLog').push().set(<String, Object?>{'h': h, 'st': st, 'by': myUid, 'ts': ServerValue.timestamp});
      toast(st == 'allow' ? 'تم السماح للجلسة ✅' : 'تم حظر الجلسة ⛔');
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الجلسات المشبوهة')),
      body: StreamBuilder(
        stream: ref('susp').onValue,
        builder: (c, s) {
          final v = s.data?.snapshot.value;
          final rows = <MapEntry<String, Map<String, dynamic>>>[];
          if (v is Map) {
            v.forEach((k, x) {
              if (x is Map) rows.add(MapEntry(k.toString(), Map<String, dynamic>.from(x)));
            });
          }
          rows.sort((a, b) {
            final ra = a.value['st'] == null ? 0 : 1, rb = b.value['st'] == null ? 0 : 1;
            if (ra != rb) return ra.compareTo(rb);
            return ((b.value['ts'] as num?) ?? 0).compareTo((a.value['ts'] as num?) ?? 0);
          });
          return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('لا توجد جلسات مشبوهة', style: TextStyle(color: kMu)))),
            for (final r in rows) _card(context, r.key, r.value),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 6),
              child: Text('سجل القرارات', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            const _LogList(),
          ]);
        },
      ),
    );
  }

  Widget _card(BuildContext context, String h, Map<String, dynamic> r) {
    final st = (r['st'] ?? '').toString();
    final ts = (r['ts'] as num?)?.toInt() ?? 0;
    final color = st == 'allow' ? const Color(0xFF2EE07A) : (st == 'ban' ? kRed : const Color(0xFFFFC857));
    Widget line(String k, String v) => v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$k: ', style: const TextStyle(color: kMu, fontSize: 12.5)),
              TextSpan(text: v, style: const TextStyle(fontSize: 12.5)),
            ])),
          );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .28), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withAlpha(140))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text(st == 'allow' ? 'مسموح' : (st == 'ban' ? 'محظور' : 'بانتظار المراجعة'), style: TextStyle(fontWeight: FontWeight.w900, color: color))),
          Text(ts > 0 ? hhmm(ts) : '', style: const TextStyle(color: kMu, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        line('بصمة الجهاز', h.length > 10 ? '${h.substring(0, 10)}…' : h),
        line('نوع التطبيق المستنسخ', (r['app'] ?? '').toString()),
        line('عدد المحاولات', (r['n'] ?? '').toString()),
        line('بيئة التشغيل', (r['os'] ?? '').toString()),
        line('مؤشرات الاشتباه', (r['ind'] ?? '').toString()),
        line('مسار البيانات', (r['p'] ?? '').toString()),
        FutureBuilder<DataSnapshot>(
          future: ref('devices/$h').get(),
          builder: (c, d) {
            final u = d.data?.value?.toString() ?? '';
            if (u.isEmpty) return line('الحساب على هذا الجهاز', 'لا يوجد حساب مسجّل على بصمة هذا الجهاز');
            return FutureBuilder<Prof>(
              future: prof(u),
              builder: (c, p) => line('حساب مرتبط بنفس الجهاز', '${p.data?.name ?? '...'} (قد يكون صاحب التطبيق الأصلي، وليس دليلاً قاطعاً)'),
            );
          },
        ),
        if ((r['by'] ?? '').toString().isNotEmpty)
          FutureBuilder<Prof>(
            future: prof(r['by'].toString()),
            builder: (c, p) => line('القرار بواسطة', '${p.data?.name ?? '...'}${(r['at'] as num?) != null ? ' — ${hhmm((r['at'] as num).toInt())}' : ''}'),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: AppButton('سماح ✅', kind: 'g', compact: true, onPressed: st == 'allow' ? null : () => _decide(h, 'allow'))),
          const SizedBox(width: 8),
          Expanded(child: AppButton('حظر ⛔', kind: 'r', compact: true, onPressed: st == 'ban' ? null : () => _decide(h, 'ban'))),
        ]),
      ]),
    );
  }
}

class _LogList extends StatelessWidget {
  const _LogList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: ref('suspLog').limitToLast(30).onValue,
      builder: (c, s) {
        final v = s.data?.snapshot.value;
        final rows = <Map<String, dynamic>>[];
        if (v is Map) {
          v.forEach((k, x) {
            if (x is Map) rows.add(Map<String, dynamic>.from(x));
          });
        }
        rows.sort((a, b) => ((b['ts'] as num?) ?? 0).compareTo((a['ts'] as num?) ?? 0));
        if (rows.isEmpty) return const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('لا قرارات بعد', style: TextStyle(color: kMu)));
        return Column(children: [
          for (final r in rows)
            FutureBuilder<Prof>(
              future: prof((r['by'] ?? '').toString()),
              builder: (c, p) => ListTile(
                dense: true,
                title: Text('${r['st'] == 'allow' ? 'سماح' : 'حظر'} — ${p.data?.name ?? '...'}', style: const TextStyle(fontSize: 13)),
                subtitle: Text('جهاز ${_short((r['h'] ?? '').toString())}…', style: const TextStyle(color: kMu, fontSize: 11)),
                trailing: Text(((r['ts'] as num?) ?? 0) > 0 ? hhmm((r['ts'] as num).toInt()) : '', style: const TextStyle(color: kMu, fontSize: 11)),
              ),
            ),
        ]);
      },
    );
  }
}
