import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth.dart';
import 'data.dart';
import 'widgets.dart';

/// تغيير كلمة السر: الكلمة الجديدة تفتح نفس الحساب، والقديمة تتوقف عن العمل
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<ChangePasswordScreen> {
  final cur = TextEditingController();
  final nw = TextEditingController();
  final nw2 = TextEditingController();
  bool busy = false;
  String msg = '';

  Future<void> _save() async {
    final c = cur.text, n = nw.text;
    if (n.length < 8) {
      setState(() => msg = 'كلمة السر الجديدة يجب ألا تقل عن 8 أحرف');
      return;
    }
    if (n != nw2.text) {
      setState(() => msg = 'تأكيد كلمة السر غير مطابق');
      return;
    }
    if (n == c) {
      setState(() => msg = 'الكلمة الجديدة مطابقة للحالية');
      return;
    }
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      final creds = await currentCreds(c);
      if (creds == null) {
        if (mounted) setState(() => msg = 'كلمة السر الحالية غير صحيحة');
      } else {
        // لا نسمح بكلمة سر مستخدمة كبديل لحساب آخر
        final ex = await ref('pwAlias/${aliasKey(n)}').get();
        if (ex.exists) {
          if (mounted) setState(() => msg = 'كلمة السر هذه مستخدمة، اختر غيرها');
        } else {
          final old = await ref('pwAlias/${aliasKey(c)}').get();
          await ref('pwAlias/${aliasKey(n)}').set(<String, Object?>{'u': myUid, 'c': aliasEnc(n, '${creds[0]}|${creds[1]}')});
          await ref('pwSwap/$myUid').set(true);
          if (old.exists) {
            try {
              await ref('pwAlias/${aliasKey(c)}').remove();
            } catch (_) {}
          }
          cur.clear();
          nw.clear();
          nw2.clear();
          if (mounted) setState(() => msg = 'تم تغيير كلمة السر ✅');
          toast('تم تغيير كلمة السر');
        }
      }
    } on FirebaseAuthException {
      if (mounted) setState(() => msg = 'كلمة السر الحالية غير صحيحة');
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
      appBar: AppBar(title: const Text('تغيير كلمة السر')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('بعد التغيير تدخل بالكلمة الجديدة فقط، وتتوقف الكلمة القديمة عن العمل.', style: TextStyle(height: 1.8, color: kMu)),
        const SizedBox(height: 14),
        _f(cur, 'كلمة السر الحالية'),
        _f(nw, 'كلمة السر الجديدة'),
        _f(nw2, 'تأكيد كلمة السر الجديدة'),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(msg, style: TextStyle(color: msg.contains('✅') ? context.accent2 : kRed))),
        AppButton(busy ? '...' : 'حفظ', onPressed: busy ? null : _save),
      ]),
    );
  }
}
