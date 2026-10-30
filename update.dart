import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'config.dart';
import 'data.dart';
import 'media.dart';
import 'widgets.dart';

Future<void> _open(String u) async {
  try {
    final ok = await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
    if (ok) return;
  } catch (_) {}
  Clipboard.setData(ClipboardData(text: u));
  toast('تم نسخ الرابط، افتحه في المتصفح');
}

/// شرح التحديث للأعضاء (نص مفصل + فيديو يضعه الإمبراطور)
Future<void> showHowToUpdate(BuildContext context) async {
  final hasVid = await hasMedia('upd');
  if (!context.mounted) return;
  await showAppSheet<void>(context, (sc) => [
        const Text('كيفية التحديث', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const Text(
          '1. اضغط زر «تحديث» وسيفتح الرابط في المتصفح.\n'
          '2. نزّل ملف التطبيق (APK).\n'
          '3. إذا ظهرت رسالة «لأمانك، لا يسمح الهاتف بتثبيت تطبيقات من هذا المصدر» اضغط «الإعدادات» ثم فعّل «السماح من هذا المصدر» للمتصفح الذي استخدمته، ثم ارجع.\n'
          '4. افتح الملف الذي نزّلته من الإشعارات أو من «التنزيلات» واضغط «تثبيت» أو «تحديث».\n'
          '5. إذا ظهر تحذير Google Play Protect اضغط «مزيد من التفاصيل» ثم «التثبيت على أي حال».\n'
          '6. بعد انتهاء التثبيت افتح التطبيق. حسابك ورصيدك وكل بياناتك تبقى كما هي، ولا تحتاج لحذف النسخة القديمة.\n\n'
          'إن كان في هاتفك أكثر من تحديث متأخر فلا تقلق، ثبّت هذا الملف فقط وستحصل على أحدث نسخة مباشرة.',
          style: TextStyle(height: 1.9),
        ),
        if (hasVid)
          AppButton('▶ شاهد الفيديو', onPressed: () {
            Navigator.of(sc).pop();
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VideoScreen(keyName: 'upd', title: 'كيفية التحديث')));
          }),
        AppButton('إغلاق', kind: 'g', onPressed: () => Navigator.of(sc).pop()),
      ]);
}

/// فحص وجود نسخة أحدث + (للإمبراطور) فرض نسخته إن كانت أحدث من المنشورة
Future<void> checkUpdate(BuildContext context) async {
  try {
    if (kBuild <= 0) return;
    final v = (await ref('config/update').get()).value;
    final m = v is Map ? v : <dynamic, dynamic>{};
    final b = (m['b'] as num?)?.toInt() ?? 0;
    final u = (m['u'] ?? '').toString();
    final note = (m['n'] ?? '').toString();
    if (!context.mounted) return;
    if (Session.isEmp && kBuild > b) {
      await publishUpdateSheet(context, force: true, link: u, note: note);
      return;
    }
    if (b <= kBuild || u.isEmpty) return;
    await showAppSheet<void>(context, (sc) => [
          const Text('🔔 هناك تحديث جديد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const Text('رجاءً قم بتثبيت أحدث نسخة من التطبيق.', style: TextStyle(height: 1.8)),
          if (note.isNotEmpty) Text(note, style: const TextStyle(height: 1.8, color: kMu)),
          const Text('تُثبَّت فوق النسخة الحالية وتبقى بياناتك.', style: TextStyle(color: kMu, fontSize: 12)),
          AppButton('تحديث', onPressed: () {
            Navigator.of(sc).pop();
            _open(u);
          }),
          AppButton('كيفية التحديث', kind: 'g', onPressed: () => showHowToUpdate(context)),
          AppButton('لاحقاً', kind: 'g', onPressed: () => Navigator.of(sc).pop()),
        ]);
  } catch (_) {}
}

/// الإمبراطور: نشر/فرض تحديث
Future<void> publishUpdateSheet(BuildContext context, {bool force = false, String link = '', String note = ''}) async {
  String l = link, n = note;
  if (!force) {
    try {
      final v = (await ref('config/update').get()).value;
      if (v is Map) {
        l = (v['u'] ?? '').toString();
        n = (v['n'] ?? '').toString();
      }
    } catch (_) {}
  }
  final u = TextEditingController(text: l);
  final nt = TextEditingController(text: n);
  if (!context.mounted) return;
  await showAppSheet<void>(context, (sc) => [
        Text(force ? 'نسختك ($kBuild) أحدث من المنشورة' : 'نشر تحديث للأعضاء', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Text(force ? 'اضغط «فرض التحديث» لتظهر بطاقة التحديث لكل الأعضاء.' : 'رقم نسخة هذا التطبيق: $kBuild', style: const TextStyle(color: kMu, height: 1.6)),
        TextField(controller: u, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: 'رابط التحميل (يفضّل رابط آخر إصدار)')),
        TextField(controller: nt, maxLength: 200, decoration: const InputDecoration(hintText: 'ملاحظة (اختياري)', counterText: '')),
        AppButton(force ? 'فرض التحديث' : 'نشر', onPressed: () async {
          if (u.text.trim().isEmpty) {
            toast('ضع رابط التحميل', bad: true);
            return;
          }
          try {
            await ref('config/update').set(<String, Object?>{'b': kBuild, 'u': u.text.trim(), 'n': nt.text.trim()});
            if (sc.mounted) Navigator.of(sc).pop();
            toast('تم النشر ✅ ستظهر البطاقة للأعضاء');
          } catch (e) {
            err(e);
          }
        }),
        AppButton('رفع فيديو شرح التحديث', kind: 'g', onPressed: () => uploadVideo('upd')),
        if (force) AppButton('لاحقاً', kind: 'g', onPressed: () => Navigator.of(sc).pop()),
      ]);
}
