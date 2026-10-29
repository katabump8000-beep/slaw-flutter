import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'config.dart';
import 'data.dart';
import 'widgets.dart';

/// فحص وجود نسخة أحدث (يعمل بعد أن ينشر الإمبراطور رقم النسخة والرابط)
Future<void> checkUpdate(BuildContext context) async {
  try {
    if (kBuild <= 0) return;
    final v = (await ref('config/update').get()).value;
    if (v is! Map) return;
    final b = (v['b'] as num?)?.toInt() ?? 0;
    final u = (v['u'] ?? '').toString();
    if (b <= kBuild || u.isEmpty) return;
    if (!context.mounted) return;
    final note = (v['n'] ?? '').toString();
    await showAppSheet<void>(context, (sc) => [
          const Text('🔔 يوجد تحديث جديد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          if (note.isNotEmpty) Text(note, style: const TextStyle(height: 1.8)),
          const Text('ثبّت النسخة الجديدة فوق القديمة، وستبقى بياناتك كما هي.', style: TextStyle(color: kMu, height: 1.7)),
          AppButton('نسخ رابط التحميل', onPressed: () {
            Clipboard.setData(ClipboardData(text: u));
            toast('تم نسخ الرابط، افتحه في المتصفح');
            Navigator.of(sc).pop();
          }),
          AppButton('لاحقاً', kind: 'g', onPressed: () => Navigator.of(sc).pop()),
        ]);
  } catch (_) {}
}

/// الإمبراطور: نشر تحديث
Future<void> publishUpdateSheet(BuildContext context) async {
  final b = TextEditingController(text: '${kBuild + 1}');
  final u = TextEditingController();
  final n = TextEditingController();
  await showAppSheet<void>(context, (sc) => [
        const Text('نشر تحديث للأعضاء', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Text('رقم نسخة هذا التطبيق: $kBuild', style: const TextStyle(color: kMu)),
        TextField(controller: b, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'رقم النسخة الجديدة (رقم تشغيل البناء)')),
        TextField(controller: u, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: 'رابط التحميل')),
        TextField(controller: n, maxLength: 200, decoration: const InputDecoration(hintText: 'ملاحظة (اختياري)', counterText: '')),
        AppButton('نشر', onPressed: () async {
          final v = int.tryParse(normDigits(b.text));
          if (v == null || u.text.trim().isEmpty) {
            toast('أكمل الحقول', bad: true);
            return;
          }
          try {
            await ref('config/update').set(<String, Object?>{'b': v, 'u': u.text.trim(), 'n': n.text.trim()});
            if (sc.mounted) Navigator.of(sc).pop();
            toast('تم النشر ✅');
          } catch (e) {
            err(e);
          }
        }),
      ]);
}
