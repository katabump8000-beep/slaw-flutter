import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth.dart';
import 'data.dart';
import 'widgets.dart';

String _recHash(String email) => sha256.convert(utf8.encode('rec|${email.trim().toLowerCase()}')).toString();

List<int> _stream(String email, int n) {
  final out = <int>[];
  var seed = sha256.convert(utf8.encode('k|${email.trim().toLowerCase()}')).bytes;
  while (out.length < n) {
    out.addAll(seed);
    seed = sha256.convert(seed).bytes;
  }
  return out.sublist(0, n);
}

String _enc(String email, String plain) {
  final b = utf8.encode(plain);
  final k = _stream(email, b.length);
  return base64Encode([for (var i = 0; i < b.length; i++) b[i] ^ k[i]]);
}

String _dec(String email, String blob) {
  final b = base64Decode(blob);
  final k = _stream(email, b.length);
  return utf8.decode([for (var i = 0; i < b.length; i++) b[i] ^ k[i]]);
}

/// تأمين الحساب: ربط بريد استعادة
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityState();
}

class _SecurityState extends State<SecurityScreen> {
  final em = TextEditingController();
  final pw = TextEditingController();
  String msg = '';
  bool busy = false;

  Future<void> _save() async {
    final e = em.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
      setState(() => msg = 'بريد غير صالح');
      return;
    }
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      final u = FirebaseAuth.instance.currentUser!;
      if (u.email == null) throw 'noemail';
      await u.reauthenticateWithCredential(EmailAuthProvider.credential(email: u.email!, password: derivedPass(pw.text)));
      final blob = _enc(e, '${u.email}|${derivedPass(pw.text)}');
      await ref('rec/${_recHash(e)}').set(<String, Object?>{'u': myUid, 'b': blob});
      if (mounted) setState(() => msg = 'تم تأمين حسابك ✅');
    } on FirebaseAuthException {
      if (mounted) setState(() => msg = 'كلمة السر غير صحيحة');
    } catch (_) {
      if (mounted) setState(() => msg = 'تعذر الحفظ (قد يكون البريد مستخدماً لحساب آخر)');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تأمين الحساب')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('أضف بريداً إلكترونياً للاستعادة في حال نسيت كلمة السر.', style: TextStyle(height: 1.8)),
        const SizedBox(height: 12),
        TextField(controller: em, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: 'بريد الاستعادة')),
        const SizedBox(height: 10),
        TextField(controller: pw, obscureText: true, decoration: const InputDecoration(hintText: 'كلمة السر الحالية (للتأكيد)')),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg, style: TextStyle(color: msg.contains('✅') ? context.accent2 : kRed))),
        const SizedBox(height: 14),
        AppButton(busy ? '...' : 'حفظ', onPressed: busy ? null : _save),
      ]),
    );
  }
}

/// نسيت كلمة المرور
class ForgotScreen extends StatefulWidget {
  const ForgotScreen({super.key});
  @override
  State<ForgotScreen> createState() => _ForgotState();
}

class _ForgotState extends State<ForgotScreen> {
  final em = TextEditingController();
  String msg = '';
  String found = '';
  bool busy = false;

  Future<void> _find() async {
    final e = em.text.trim().toLowerCase();
    setState(() {
      busy = true;
      msg = '';
      found = '';
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) await FirebaseAuth.instance.signInAnonymously();
      final s = await ref('rec/${_recHash(e)}').get();
      final v = s.value;
      if (v is Map) {
        found = _dec(e, (v['b'] ?? '').toString());
      } else {
        msg = 'لم نجد حساباً مرتبطاً بهذا البريد';
      }
    } catch (_) {
      msg = 'تعذر البحث، تأكد من الاتصال';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _enter() async {
    try {
      final p = found.split('|');
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: p[0], password: p[1]);
      prefs.setBool('seen_login', true);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted) setState(() => msg = 'تعذر الدخول');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FirShell(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (found.isEmpty) ...[
            const Text('أدخل بريد الاستعادة المرتبط بحسابك', textAlign: TextAlign.center, style: TextStyle(color: kTx)),
            const SizedBox(height: 10),
            TextField(controller: em, textDirection: TextDirection.ltr, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: 'name@example.com')),
            if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFD0C0)))),
            const SizedBox(height: 12),
            AppButton(busy ? '...' : 'بحث', glow: true, onPressed: busy ? null : _find),
          ] else ...[
            const Text('اكتشفنا أن هذا الحساب يخصك ولا يحتاج الأمر إلى رمز تحقق.', textAlign: TextAlign.center, style: TextStyle(color: kTx, height: 1.8)),
            const SizedBox(height: 14),
            AppButton('دخول', glow: true, onPressed: _enter),
          ],
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('رجوع', style: TextStyle(color: kMu))),
        ]),
      ),
    );
  }
}
