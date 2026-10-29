import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'auth.dart';
import 'data.dart';
import 'widgets.dart';

/// تعيين كلمة سر جديدة بدون طلب الحالية + عرض الكلمة الحالية
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<ChangePasswordScreen> {
  final nw = TextEditingController();
  final nw2 = TextEditingController();
  bool busy = false, show = false, loaded = false;
  String msg = '', current = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = (await ref('pw/$myUid').get()).value;
      if (mounted) setState(() => current = v?.toString() ?? '');
    } catch (_) {}
    if (mounted) setState(() => loaded = true);
  }

  Future<void> _save() async {
    final n = nw.text;
    if (n.length < 8) {
      setState(() => msg = 'كلمة السر الجديدة يجب ألا تقل عن 8 أحرف');
      return;
    }
    if (n != nw2.text) {
      setState(() => msg = 'تأكيد كلمة السر غير مطابق');
      return;
    }
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      final u = FirebaseAuth.instance.currentUser!;
      List<String>? creds;
      if (current.isNotEmpty) creds = await currentCreds(current);
      if (creds == null) {
        try {
          await u.updatePassword(derivedPass(n));
          creds = [u.email!, derivedPass(n)];
        } on FirebaseAuthException catch (_) {}
      }
      if (creds == null) {
        if (mounted) {
          setState(() => msg = 'لأمان الحساب يلزم تسجيل دخول حديث. سجّل الخروج ثم ادخل بكلمة السر وجرّب مجدداً، وبعدها لن تحتاج ذلك.');
        }
      } else {
        final k = aliasKey(n);
        final ex = (await ref('pwAlias/$k').get()).value;
        if (ex is Map && ex['u'] != myUid) {
          if (mounted) setState(() => msg = 'كلمة السر هذه مستخدمة، اختر غيرها');
        } else {
          if (ex == null) await ref('pwAlias/$k').set(<String, Object?>{'u': myUid, 'c': aliasEnc(n, '${creds[0]}|${creds[1]}')});
          if (current.isNotEmpty && current != n) {
            try {
              final o = (await ref('pwAlias/${aliasKey(current)}').get()).value;
              if (o is Map && o['u'] == myUid) await ref('pwAlias/${aliasKey(current)}').remove();
            } catch (_) {}
          }
          await ref('pwSwap/$myUid').set(true);
          await ref('pw/$myUid').set(n);
          nw.clear();
          nw2.clear();
          if (mounted) setState(() {
            current = n;
            msg = 'تم تعيين كلمة السر ✅';
          });
          toast('تم تعيين كلمة السر');
        }
      }
    } catch (e) {
      if (mounted) setState(() => msg = 'تعذر التغيير، تأكد من الاتصال');
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _f(TextEditingController c, String h) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(controller: c, obscureText: true, decoration: InputDecoration(hintText: h)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كلمة السر')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .28), borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
          child: Row(children: [
            const Icon(Icons.key_rounded),
            const SizedBox(width: 10),
            Expanded(
              child: !loaded
                  ? const Text('...')
                  : current.isEmpty
                      ? const Text('كلمة السر الحالية غير محفوظة بعد. عيّن كلمة جديدة وستظهر هنا.', style: TextStyle(color: kMu, height: 1.6))
                      : SelectableText(show ? current : '••••••••••', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            if (current.isNotEmpty) ...[
              IconButton(onPressed: () => setState(() => show = !show), icon: Icon(show ? Icons.visibility_off : Icons.visibility)),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: current));
                  toast('تم النسخ');
                },
                icon: const Icon(Icons.copy),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 18),
        _f(nw, 'كلمة السر الجديدة'),
        _f(nw2, 'تأكيد كلمة السر الجديدة'),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(msg, style: TextStyle(height: 1.6, color: msg.contains('✅') ? context.accent2 : kRed))),
        AppButton(busy ? '...' : 'تعيين كلمة السر', onPressed: busy ? null : _save),
      ]),
    );
  }
}
