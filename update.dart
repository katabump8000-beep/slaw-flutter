import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ota_update/ota_update.dart';
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
          '1. اضغط زر «تحديث» وسيحمّل التطبيق النسخة الجديدة بنفسه من داخل البرنامج.\n'
          '2. عندما تظهر نافذة التثبيت اضغط «تثبيت» أو «تحديث».\n'
          '3. إذا طلب الهاتف السماح بالتثبيت من هذا التطبيق، فعّل الخيار ثم ارجع واضغط «تحديث» مرة أخرى.\n'
          '4. إذا ظهر تحذير Google Play Protect اضغط «مزيد من التفاصيل» ثم «التثبيت على أي حال».\n'
          '5. بعد انتهاء التثبيت افتح التطبيق. حسابك ورصيدك وكل بياناتك تبقى كما هي، ولا تحتاج لحذف النسخة القديمة.\n\n'
          'إن لم ينجح التحميل من داخل البرنامج يوجد زر «فتح الرابط في المتصفح».',
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
    await _showUpdate(context, u, note);
  } catch (_) {}
}

bool _updShowing = false;

/// رابط الـAPK المباشر: من رابط صفحة الإصدار نبني رابط آخر إصدار
String _apkUrl(String u) {
  final l = u.trim();
  if (l.toLowerCase().endsWith('.apk')) return l;
  final i = l.indexOf('/releases');
  if (l.contains('github.com') && i > 0) return '${l.substring(0, i)}/releases/latest/download/SLAW.apk';
  return l;
}

/// نافذة تحديث إجباري لا تُغلق حتى يحدّث العضو
Future<void> _showUpdate(BuildContext context, String u, String note) async {
  if (_updShowing) return;
  _updShowing = true;
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dc) => PopScope(canPop: false, child: _UpdateDialog(link: u, note: note)),
    );
  } finally {
    _updShowing = false;
  }
}

class _UpdateDialog extends StatefulWidget {
  final String link;
  final String note;
  const _UpdateDialog({required this.link, required this.note});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  StreamSubscription<OtaEvent>? sub;
  double? p;
  bool busy = false;
  bool failed = false;
  bool hasVid = false;
  String msg = '';

  @override
  void initState() {
    super.initState();
    hasMedia('upd').then((v) {
      if (mounted) setState(() => hasVid = v);
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  void _fail(String m) {
    if (!mounted) return;
    setState(() {
      busy = false;
      failed = true;
      msg = m;
      p = null;
    });
  }

  void _start() {
    if (busy) return;
    setState(() {
      busy = true;
      failed = false;
      msg = 'جاري تحميل التحديث...';
      p = 0;
    });
    try {
      sub?.cancel();
      sub = OtaUpdate().execute(_apkUrl(widget.link), destinationFilename: 'SLAW.apk').listen((ev) {
        if (!mounted) return;
        final st = ev.status.name;
        if (st == 'DOWNLOADING') {
          final v = int.tryParse((ev.value ?? '').trim()) ?? 0;
          setState(() {
            p = v / 100;
            msg = 'جاري التحميل $v%';
          });
        } else if (st == 'INSTALLING') {
          setState(() {
            p = 1;
            msg = 'اضغط «تثبيت» في النافذة التي ظهرت';
          });
        } else if (st == 'INSTALLATION_DONE') {
          setState(() {
            busy = false;
            msg = 'تم التثبيت';
          });
        } else if (st == 'PERMISSION_NOT_GRANTED_ERROR') {
          _fail('فعّل «السماح بالتثبيت من هذا التطبيق» في الإعدادات ثم اضغط إعادة المحاولة');
        } else if (st == 'ALREADY_RUNNING_ERROR') {
          setState(() => msg = 'التحميل جارٍ...');
        } else {
          _fail('تعذر التحديث ($st). أعد المحاولة أو افتح الرابط في المتصفح');
        }
      }, onError: (Object e) => _fail('تعذر التحميل، تأكد من الإنترنت'));
    } catch (e) {
      _fail('تعذر بدء التحديث');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('🔔 تحديث إجباري', style: TextStyle(fontWeight: FontWeight.w900)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('صدرت نسخة جديدة من التطبيق. لازم تحدّث لتكمل.', style: TextStyle(height: 1.8)),
          if (widget.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(widget.note, style: const TextStyle(height: 1.8, color: kMu))),
          const SizedBox(height: 12),
          if (busy || p != null) LinearProgressIndicator(value: p),
          if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg, style: TextStyle(color: failed ? const Color(0xFFFF6B6B) : kMu))),
          const SizedBox(height: 12),
          AppButton(busy ? 'جاري التحديث...' : (failed ? 'إعادة المحاولة' : 'تحديث الآن'), onPressed: busy ? null : _start),
          if (hasVid) ...[
            const SizedBox(height: 6),
            AppButton('▶ شاهد فيديو الشرح', kind: 'g', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VideoScreen(keyName: 'upd', title: 'كيفية التحديث')))),
          ],
          const SizedBox(height: 6),
          AppButton('كيفية التحديث', kind: 'g', onPressed: () => showHowToUpdate(context)),
          if (failed) ...[
            const SizedBox(height: 6),
            AppButton('فتح الرابط في المتصفح', kind: 'g', onPressed: () => _open(widget.link)),
          ],
        ]),
      ),
    );
  }
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
