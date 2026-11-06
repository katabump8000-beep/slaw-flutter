import 'servertime.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'core.dart';
import 'crop.dart';
import 'data.dart';
import 'profile.dart';
import 'widgets.dart';

/// بطاقة «التواصل مع المطورين» في الإعدادات: تتحول إلى عدّاد 12 ساعة ثم إلى الرد
class SupportTile extends StatelessWidget {
  const SupportTile({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('supportOpen/$myUid').onValue,
      builder: (c, s) {
        final tid = s.data?.snapshot.value?.toString() ?? '';
        return ListTile(
          leading: const Icon(Icons.support_agent),
          title: tid.isEmpty ? const Text('التواصل مع المطورين') : _Status(tid: tid),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SupportScreen())),
        );
      },
    );
  }
}

class _Status extends StatefulWidget {
  final String tid;
  const _Status({required this.tid});
  @override
  State<_Status> createState() => _StatusState();
}

class _StatusState extends State<_Status> {
  Map<String, dynamic>? t;
  Timer? tm;

  @override
  void initState() {
    super.initState();
    ref('support/${widget.tid}').get().then((s) {
      if (s.value is Map && mounted) setState(() => t = Map<String, dynamic>.from(s.value as Map));
    });
    tm = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    tm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = t;
    if (d == null) return const Text('...');
    if (d['st'] == 'a') return const Text('📩 وصل ردّ المطور — عرض');
    final left = ((d['ts'] as num?)?.toInt() ?? 0) + 12 * 3600000 - nowMs();
    if (left <= 0) return const Text('انتهت مهلة الرد — يمكنك إرسال بلاغ جديد');
    final s = left ~/ 1000;
    String p(int x) => x.toString().padLeft(2, '0');
    return Row(children: [const Icon(Icons.access_time, size: 18), const SizedBox(width: 6), Text('بانتظار الرد  ${p(s ~/ 3600)}:${p((s % 3600) ~/ 60)}:${p(s % 60)}')]);
  }
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final tx = TextEditingController();
  String? img;
  bool busy = false;
  String tid = '';
  Map<String, dynamic>? t;
  String handlerName = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) await FirebaseAuth.instance.signInAnonymously();
      tid = (await ref('supportOpen/$myUid').get()).value?.toString() ?? '';
      if (tid.isNotEmpty) {
        final s = await ref('support/$tid').get();
        t = s.value is Map ? Map<String, dynamic>.from(s.value as Map) : null;
      }
      final h = (await ref('config/support').get()).value?.toString() ?? '';
      if (h.isNotEmpty) handlerName = (await prof(h)).name;
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pickImg() async {
    await showAppSheet<void>(context, (sc) => [
          const Text('رجاءً أرسل صورة للشيء الذي تتكلم عنه', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.8)),
          AppButton('اختيار صورة', onPressed: () => Navigator.of(sc).pop()),
        ]);
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null || !mounted) return;
      final d = await cropImage(context, await x.readAsBytes(), out: const [900, 720, 560, 420], limit: 55000, round: false, title: 'قص الصورة', ratio: 4 / 3);
      if (d != null && mounted) setState(() => img = d);
    } catch (e) {
      err(e);
    }
  }

  Future<void> _send() async {
    final text = tx.text.trim();
    if (text.isEmpty) {
      toast('اكتب رسالتك', bad: true);
      return;
    }
    setState(() => busy = true);
    try {
      final id = ref('support').push().key!;
      final m = <String, Object?>{'u': myUid, 'tx': text, 'ts': nowMs(), 'st': 'o'};
      if (img != null) m['img'] = img;
      await ref('support/$id').set(m);
      await ref('supportOpen/$myUid').set(id);
      // الإشعار لكل المطورين يرسله السيرفر تلقائياً (onSupport)
      tx.clear();
      img = null;
      await _load();
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _done() async {
    try {
      await ref('support/$tid').remove();
      await ref('supportOpen/$myUid').remove();
      tid = '';
      t = null;
      if (mounted) setState(() {});
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = Session.me.name;
    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (tid.isNotEmpty && t != null) {
      final answered = t!['st'] == 'a';
      final expired = !answered && ((t!['ts'] as num?)?.toInt() ?? 0) + 12 * 3600000 <= nowMs();
      body = ListView(padding: const EdgeInsets.all(18), children: [
        if (expired) ...[
          const Text('مضت 12 ساعة دون رد من المطورين. نعتذر عن التأخير، يمكنك الآن إرسال بلاغ جديد.', style: TextStyle(height: 1.9, fontSize: 15)),
          const SizedBox(height: 14),
          AppButton('إرسال بلاغ جديد', onPressed: _done),
        ] else if (!answered)
          Text('عزيزي $name، تم إرسال رسالتك وسيرد عليك أحد المطورين في أقرب وقت، في مدة لا تتجاوز 12 ساعة.\n${handlerName.isNotEmpty ? 'انتظر رداً من $handlerName.' : ''}', style: const TextStyle(height: 1.9, fontSize: 15))
        else ...[
          Text('رد ${t!['ansby'] != null ? '' : 'المطور'}:', style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: accentA(context, .1), borderRadius: BorderRadius.circular(14)), child: Text((t!['ans'] ?? '').toString(), style: const TextStyle(height: 1.8))),
          const SizedBox(height: 14),
          AppButton('تم', onPressed: _done),
        ],
      ]);
    } else {
      body = ListView(padding: const EdgeInsets.all(18), children: [
        const Text('إرسال بلاغ إلى المطورين', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(controller: tx, maxLength: 500, minLines: 6, maxLines: 8, decoration: const InputDecoration(hintText: 'اكتب رسالتك هنا (500 حرف)')),
        const Text('ملاحظة: التطاول على أحد المطورين لأسباب تافهة قد يؤدي إلى عقوبات.', style: TextStyle(color: kMu, fontSize: 12, height: 1.7)),
        const SizedBox(height: 10),
        Row(children: [
          GestureDetector(
            onTap: _pickImg,
            child: Container(width: 54, height: 54, decoration: BoxDecoration(border: Border.all(color: kLine), borderRadius: BorderRadius.circular(12)), child: Icon(img == null ? Icons.add_photo_alternate_outlined : Icons.check_circle, color: img == null ? kMu : context.accent)),
          ),
          const SizedBox(width: 10),
          const Text('صورة (اختياري)', style: TextStyle(color: kMu)),
        ]),
        const SizedBox(height: 14),
        AppButton(busy ? '...' : 'إرسال', onPressed: busy ? null : _send),
      ]);
    }
    return Scaffold(appBar: AppBar(title: const Text('التواصل مع المطورين')), body: body);
  }
}

/// شاشة البلاغ عند المسؤول (من يعيّنه الإمبراطور)
class SupportTicketScreen extends StatefulWidget {
  final String tid;
  const SupportTicketScreen({super.key, required this.tid});
  @override
  State<SupportTicketScreen> createState() => _SupportTicketState();
}

class _SupportTicketState extends State<SupportTicketScreen> {
  Map<String, dynamic>? t;
  final rep = TextEditingController();
  bool anon = false;
  bool showImg = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref('support/${widget.tid}').get();
      if (s.value is Map) t = Map<String, dynamic>.from(s.value as Map);
      if (t != null) anon = !(await ref('profiles/${t!['u']}').get()).exists;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _ignore() async {
    try {
      final u = t?['u']?.toString() ?? '';
      await ref('support/${widget.tid}').remove();
      if (u.isNotEmpty) await ref('supportOpen/$u').remove();
      toast('تم التجاهل');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      err(e);
    }
  }

  Future<void> _send() async {
    final a = rep.text.trim();
    if (a.isEmpty || t == null) return;
    try {
      await ref('support/${widget.tid}').update(<String, Object?>{'ans': a, 'ansby': myUid, 'st': 'a', 'at': nowMs()});
      // السيرفر يرسل للعضو إشعار «لقد تلقيت ردا من المطور!» (القواعد لا تسمح بكتابة إشعار مباشر للعضو من هنا)
      await ref('supportAns').push().set(<String, Object?>{'to': t!['u'].toString(), 'by': myUid, 'ts': ServerValue.timestamp});
      toast('تم إرسال الرد ✅');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = t;
    return Scaffold(
      appBar: AppBar(title: const Text('بلاغ من عضو')),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              ListTile(
                leading: anon ? const CircleAvatar(child: Icon(Icons.person_off_outlined)) : UserAvatar(d['u'].toString(), size: 44),
                title: anon
                    ? const Text('مستخدم مجهول قام بإرسال بلاغ من واجهة الدخول وليس لديه حساب!', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, height: 1.6))
                    : FutureBuilder<Prof>(future: prof(d['u'].toString()), builder: (c, s) => Text(s.data?.name ?? '...', style: const TextStyle(fontWeight: FontWeight.w800))),
                trailing: Wrap(children: [
                  if (!anon) IconButton(tooltip: 'الملف التعريفي', icon: const Icon(Icons.person_outline), onPressed: () => viewProfile(context, d['u'].toString())),
                  if (Session.isDev)
                    IconButton(tooltip: 'حظر من التطبيق', icon: const Icon(Icons.block, color: kRed), onPressed: () async {
                      try {
                        await ref('banned/${d['u']}').set(true);
                        toast('تم حظر المستخدم');
                      } catch (e) {
                        err(e);
                      }
                    }),
                ]),
              ),
              Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .3), borderRadius: BorderRadius.circular(14)), child: Text((d['tx'] ?? '').toString(), style: const TextStyle(height: 1.8))),
              if (d['img'] != null && !showImg) Padding(padding: const EdgeInsets.only(top: 10), child: AppButton('عرض صورة', kind: 'g', onPressed: () => setState(() => showImg = true))),
              if (d['img'] != null && showImg) Padding(padding: const EdgeInsets.only(top: 10), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: _img(d['img'].toString()))),
              const SizedBox(height: 14),
              if (d['st'] == 'a') Text('تم الرد: ${d['ans']}', style: const TextStyle(color: kMu)) else ...[
                TextField(controller: rep, minLines: 3, maxLines: 6, maxLength: 500, decoration: const InputDecoration(hintText: 'اكتب الرد')),
                Row(children: [
                  Expanded(child: AppButton('رد', onPressed: _send)),
                  const SizedBox(width: 10),
                  Expanded(child: AppButton('تجاهل', kind: 'g', onPressed: _ignore)),
                ]),
              ],
            ]),
    );
  }

  Widget _img(String d) {
    final i = d.indexOf(',');
    return Image.memory(UriData.parse(d).contentAsBytes());
  }
}


/// عند دخول العضو: إن ردّ المطور على بلاغه تظهر له بطاقة بالرد، وبعد إغلاقها يتجدد زر «التواصل مع المطورين»
Future<void> checkSupportReply(BuildContext context) async {
  try {
    final tid = (await ref('supportOpen/$myUid').get()).value?.toString() ?? '';
    if (tid.isEmpty) return;
    final v = (await ref('support/$tid').get()).value;
    if (v is! Map || v['st'] != 'a') return;
    if (prefs.getString('sup_shown') == tid) return;
    prefs.setString('sup_shown', tid);
    final by = v['ansby']?.toString() ?? '';
    final nm = by.isNotEmpty ? (await prof(by)).name : 'المطور';
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dc) => AlertDialog(
        title: const Text('📩 ردّ على رسالتك', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text('قام المطور $nm بالرد على رسالتك:\n\n${v['ans'] ?? ''}', style: const TextStyle(height: 1.8)),
        actions: [TextButton(onPressed: () => Navigator.of(dc).pop(), child: const Text('حسناً'))],
      ),
    );
    await ref('support/$tid').remove();
    await ref('supportOpen/$myUid').remove();
  } catch (_) {}
}
