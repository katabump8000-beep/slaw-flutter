import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'media.dart';
import 'security.dart';
import 'support.dart';
import 'widgets.dart';

/// يمنع AuthGate من فتح الشاشة الرئيسية أثناء إنشاء الحساب
final ValueNotifier<bool> registering = ValueNotifier<bool>(false);

/// يزيد رقمه لإعادة تحميل الشاشة الرئيسية بعد إنشاء الحساب
final ValueNotifier<int> reloadN = ValueNotifier<int>(0);

String _hex(String s) => sha256.convert(utf8.encode(s)).toString();

/// كلمة السر هي مفتاح الحساب: منها يُشتق البريد الداخلي وكلمة سر Firebase
String derivedEmail(String pw) => 'p${_hex('fir-e|$pw').substring(0, 40)}@fir-app.com';
String derivedPass(String pw) => _hex('fir-p|$pw');

// ---- تغيير كلمة السر: كلمة جديدة تفتح نفس الحساب عبر "بديل" مشفّر ----
String aliasKey(String pw) => _hex('fir-a|$pw').substring(0, 40);

List<int> _aliasStream(String pw, int n) {
  final out = <int>[];
  var seed = sha256.convert(utf8.encode('fir-ak|$pw')).bytes;
  while (out.length < n) {
    out.addAll(seed);
    seed = sha256.convert(seed).bytes;
  }
  return out.sublist(0, n);
}

String aliasEnc(String pw, String plain) {
  final b = utf8.encode(plain);
  final k = _aliasStream(pw, b.length);
  return base64Encode([for (var i = 0; i < b.length; i++) b[i] ^ k[i]]);
}

String aliasDec(String pw, String blob) {
  final b = base64Decode(blob);
  final k = _aliasStream(pw, b.length);
  return utf8.decode([for (var i = 0; i < b.length; i++) b[i] ^ k[i]]);
}

/// يرجع [البريد الفعلي, كلمة سر Firebase] إن كانت [pw] كلمة سر بديلة مسجّلة
Future<List<String>?> aliasCreds(String pw) async {
  try {
    final s = await ref('pwAlias/${aliasKey(pw)}').get();
    final v = s.value;
    if (v is Map) {
      final t = aliasDec(pw, (v['c'] ?? '').toString());
      final i = t.indexOf('|');
      if (i > 0) return [t.substring(0, i), t.substring(i + 1)];
    }
  } catch (_) {}
  return null;
}

/// يتحقق من كلمة السر الحالية للمستخدم المسجَّل (أصلية أو بديلة) ويرجع بياناته الفعلية
Future<List<String>?> currentCreds(String pw) async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null || u.email == null) return null;
  try {
    await u.reauthenticateWithCredential(EmailAuthProvider.credential(email: u.email!, password: derivedPass(pw)));
    final sw = await ref('pwSwap/${u.uid}').get();
    if (sw.exists) return null;
    return [u.email!, derivedPass(pw)];
  } on FirebaseAuthException catch (_) {}
  final a = await aliasCreds(pw);
  if (a == null || a[0] != u.email) return null;
  try {
    await u.reauthenticateWithCredential(EmailAuthProvider.credential(email: a[0], password: a[1]));
    return a;
  } catch (_) {
    return null;
  }
}

// ---------- فلتر اللقب: عربي فقط بلا زخرفة ----------
final RegExp _nameRe = RegExp(r'^[\u0621-\u063F\u0641-\u064A ]{2,20}$');
const List<String> _bad = [
  'كلب', 'حمار', 'خرا', 'عاهر', 'شرموط', 'قحب', 'منيك', 'زب', 'كس', 'طيز', 'لعن', 'حقير', 'قذر', 'وسخ',
];

/// يرجع نص الخطأ أو '' إذا كان اللقب سليماً
String nameError(String raw) {
  final v = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (v.length < 2) return 'اللقب قصير جداً';
  if (!_nameRe.hasMatch(v)) return 'اللقب بالعربية فقط، بدون أرقام أو زخرفة أو تشكيل';
  final words = v.split(' ');
  final flat = words.join();
  for (final b in _bad) {
    final hit = b.length <= 3 ? words.contains(b) : flat.contains(b);
    if (hit) return 'هذا اللقب غير لائق';
  }
  return '';
}

/// بصمة الجهاز (حساب واحد لكل جهاز)
Future<String> deviceHash() async {
  var id = '';
  try {
    id = await AndroidId().getId() ?? '';
  } catch (_) {}
  if (id.isEmpty) {
    id = prefs.getString('did') ?? '';
    if (id.isEmpty) {
      id = '${DateTime.now().microsecondsSinceEpoch}${Random.secure().nextInt(1 << 30)}';
      prefs.setString('did', id);
    }
  }
  return _hex('fir|$id');
}

Future<void> _rollback(User? u) async {
  try {
    if (u != null) await u.delete();
  } catch (_) {}
}

/// ينشئ الحساب كاملاً. يرجع '' عند النجاح أو رسالة الخطأ.
/// pw == null يعني حساباً موجوداً (دخول Google للمطورين).
Future<String> registerAccount({
  required String name,
  required String gender,
  String? pw,
  String code = '',
}) async {
  final auth = FirebaseAuth.instance;
  User? created;
  try {
    if (pw != null) {
      final cred = await auth.createUserWithEmailAndPassword(email: derivedEmail(pw), password: derivedPass(pw));
      created = cred.user;
    }
    final u = auth.currentUser;
    if (u == null) return 'تعذر إنشاء الحساب';
    final uid = u.uid;

    var refU = '';
    var refG = '';
    if (code.isNotEmpty) {
      final r = await ref('refCodes/$code').get();
      final v = r.value;
      if (!r.exists || v is! Map) {
        await _rollback(created);
        return 'رابط الدعوة غير صالح';
      }
      refU = (v['u'] ?? '').toString();
      refG = (v['g'] ?? '').toString();
      if (refU == uid) {
        await _rollback(created);
        return 'لا يمكنك استخدام رابطك الخاص';
      }
    }

    final h = await deviceHash();
    final dv = await ref('devices/$h').get();
    if (dv.exists && dv.value.toString() != uid) {
      try {
        await ref('restricted/$uid').set(<String, Object?>{
          'n': name,
          'o': dv.value.toString(),
          'h': h,
          'ts': ServerValue.timestamp,
        });
      } catch (_) {}
      await _rollback(created);
      return 'لا يمكن إنشاء حساب آخر على هذا الجهاز';
    }
    if (!dv.exists) await ref('devices/$h').set(uid);
    if (!(await ref('deviceOf/$uid').get()).exists) await ref('deviceOf/$uid').set(h);

    await ref('profiles/$uid').set(<String, Object?>{
      'name': name,
      'gender': gender,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'color': '#ff7a1a',
    });
    await db.ref().update(<String, Object?>{
      'wallets/$uid/bal': 100,
      'wallets/$uid/ts': ServerValue.timestamp,
    });

    if (refG.isNotEmpty) {
      await ref('refClaims/$uid').set(code);
      await ref('joinLog/$uid').set(<String, Object?>{'i': refU, 'g': refG, 'ts': ServerValue.timestamp});
      await db.ref().update(<String, Object?>{
        'refPaid/$uid': true,
        'wallets/$refU/bal': ServerValue.increment(200),
        'pubCount/$refU': ServerValue.increment(1),
        'members/$refG/$uid': true,
      });
    }
    return '';
  } on FirebaseAuthException catch (e) {
    if (e.code == 'email-already-in-use') return 'كلمة السر هذه مستخدمة، اختر كلمة سر أخرى';
    if (e.code == 'network-request-failed') return 'لا يوجد اتصال بالإنترنت';
    if (e.code == 'operation-not-allowed') return 'فعّل Email/Password في Firebase ← Authentication';
    return 'تعذر إنشاء الحساب (${e.code})';
  } catch (e) {
    await _rollback(created);
    final s = e.toString().toLowerCase();
    if (s.contains('permission')) return 'تعذر التسجيل (صلاحيات). تأكد أن قواعد قاعدة البيانات منشورة';
    return 'تعذر التسجيل، تأكد من الاتصال';
  }
}

String extractCode(String text) {
  final m = RegExp(r'(\d{8})').firstMatch(normDigits(text));
  return m == null ? '' : m.group(1)!;
}

// ---------- الواجهة ----------

/// الغلاف البركاني (برتقالي) مع البطاقة والنقطة الخضراء السرية
class FirShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onDot;
  const FirShell({super.key, required this.child, this.onDot});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF5A00), Color(0xFFD63200), Color(0xFF7A1500)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 34),
                  decoration: BoxDecoration(
                    color: const Color(0x8C3C0A00),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0x59FFC896)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: Text('🌋', style: TextStyle(fontSize: 60))),
                      const Center(
                        child: Text('FIR',
                            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 8, color: kTx)),
                      ),
                      const Center(child: Text('النـ🔥ــا ر', style: TextStyle(fontSize: 20, color: kTx))),
                      const SizedBox(height: 16),
                      child,
                    ],
                  ),
                ),
                if (onDot != null)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onDot,
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF39FF14),
                            boxShadow: [BoxShadow(color: Color(0xFF39FF14), blurRadius: 8)],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// أول شاشة: للجديد (طلب الدخول برابط) وللعائد (زر تسجيل الدخول)
class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key});

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

String _lastLink = '';

class _AuthFlowState extends State<AuthFlow> {
  final bool returning = prefs.getBool('seen_login') ?? false;
  int taps = 0;
  Timer? tapTimer;
  StreamSubscription<Uri>? sub;

  @override
  void initState() {
    super.initState();
    _initLinks();
    _recordInstall();
  }

  Future<void> _recordInstall() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) await FirebaseAuth.instance.signInAnonymously();
      final h = await deviceHash();
      await ref('installs/$h').set(DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  @override
  void dispose() {
    tapTimer?.cancel();
    sub?.cancel();
    super.dispose();
  }

  Future<void> _initLinks() async {
    try {
      final al = AppLinks();
      final first = await al.getInitialLink();
      _handle(first);
      sub = al.uriLinkStream.listen(_handle, onError: (_) {});
    } catch (_) {}
  }

  void _handle(Uri? u) {
    if (u == null || !mounted) return;
    final s = u.toString();
    if (s == _lastLink) return;
    final c = u.queryParameters['c'] ?? '';
    if (!RegExp(r'^\d{8}$').hasMatch(c)) return;
    _lastLink = s;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RegisterScreen(code: c)));
  }

  void _dot() {
    taps++;
    tapTimer?.cancel();
    tapTimer = Timer(const Duration(seconds: 6), () => taps = 0);
    if (taps >= 17) {
      taps = 0;
      _google();
    }
  }

  Future<void> _google() async {
    try {
      await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
    } catch (e) {
      final s = e.toString();
      if (!s.contains('canceled') && !s.contains('cancelled')) {
        final code = e is FirebaseAuthException ? e.code : s.split('\n').first;
        toast('تعذر دخول المطورين: ${code.length > 90 ? code.substring(0, 90) : code}', bad: true);
      }
    }
  }

  void _pasteLink() {
    final c = TextEditingController();
    showAppSheet<void>(context, (sc) => [
          const Text('الصق رابط الدعوة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          TextField(controller: c, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: 'https://...')),
          AppButton('متابعة', onPressed: () {
            final code = extractCode(c.text);
            if (code.isEmpty) {
              toast('رابط غير صالح', bad: true);
              return;
            }
            Navigator.of(sc).pop();
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RegisterScreen(code: code)));
          }),
        ]);
  }

  void _login() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PasswordLoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
       FirShell(
        onDot: _dot,
        child: returning
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  SizedBox(height: 56, child: AppButton('تسجيل الدخول', glow: true, onPressed: _login)),
                  const SizedBox(height: 10),
                  TextButton(onPressed: _pasteLink, child: const Text('لدي رابط دعوة', style: TextStyle(color: kMu))),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: _login,
                      child: Text('تسجيل دخول', style: TextStyle(color: context.accent2, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const Text(
                    'مرحباً.\nرجاءً قم بالدخول من خلال رابط الشخص الذي دعاك.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, height: 1.9, color: kTx),
                  ),
                  const SizedBox(height: 14),
                  AppButton('لصق رابط الدعوة', kind: 'g', onPressed: _pasteLink),
                ],
              ),
       ),
       Positioned(
         top: MediaQuery.of(context).padding.top + 4,
         right: 6,
         child: Row(children: [
           const GuideButton(),
           IconButton(tooltip: 'خدمة العملاء', icon: const Icon(Icons.person_outline), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SupportScreen()))),
         ]),
       ),
      ]),
    );
  }
}

class PasswordLoginScreen extends StatefulWidget {
  const PasswordLoginScreen({super.key});

  @override
  State<PasswordLoginScreen> createState() => _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends State<PasswordLoginScreen> {
  final pw = TextEditingController();
  bool busy = false;
  bool hide = true;
  String error = '';

  Future<void> _login() async {
    final p = pw.text;
    if (p.length < 8) {
      setState(() => error = 'كلمة السر غير صحيحة');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      try {
        final cr = await FirebaseAuth.instance.signInWithEmailAndPassword(email: derivedEmail(p), password: derivedPass(p));
        final sw = await ref('pwSwap/${cr.user!.uid}').get();
        if (sw.exists) {
          await FirebaseAuth.instance.signOut();
          if (mounted) setState(() {
            error = 'تم تغيير كلمة السر لهذا الحساب، استخدم كلمة السر الجديدة';
            busy = false;
          });
          return;
        }
      } on FirebaseAuthException catch (e) {
        final wrong0 = e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential';
        if (!wrong0) rethrow;
        final a = await aliasCreds(p);
        if (a == null) rethrow;
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: a[0], password: a[1]);
      }
      prefs.setBool('seen_login', true);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (e) {
      final wrong = e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential';
      if (mounted) {
        setState(() => error = wrong ? 'كلمة السر غير صحيحة' : (e.code == 'network-request-failed' ? 'لا يوجد اتصال بالإنترنت' : 'تعذر تسجيل الدخول (${e.code})'));
      }
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر تسجيل الدخول، تأكد من الاتصال');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FirShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('أدخل كلمة السر الخاصة بحسابك', textAlign: TextAlign.center, style: TextStyle(color: kTx)),
                const SizedBox(height: 12),
                TextField(
                  controller: pw,
                  obscureText: hide,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'كلمة السر',
                    prefixIcon: IconButton(
                      icon: Icon(hide ? Icons.visibility_off : Icons.visibility, size: 20),
                      onPressed: () => setState(() => hide = !hide),
                    ),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFD0C0))),
                  ),
                const SizedBox(height: 14),
                AppButton(busy ? '...' : 'دخول', glow: true, onPressed: busy ? null : _login),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ForgotScreen())),
                  child: const Text('هل نسيت كلمة المرور؟', style: TextStyle(color: kMu)),
                ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            right: 6,
            child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }
}

/// إنشاء الحساب: اللقب + الجنس + كلمة السر (من رابط الدعوة)
class RegisterScreen extends StatefulWidget {
  final String code;
  final bool google;
  const RegisterScreen({super.key, this.code = '', this.google = false});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final name = TextEditingController();
  final pw = TextEditingController();
  final pw2 = TextEditingController();
  String gender = '';
  bool busy = false;
  String error = '';

  Future<void> _go() async {
    final ne = nameError(name.text);
    if (ne.isNotEmpty) {
      setState(() => error = ne);
      return;
    }
    if (gender.isEmpty) {
      setState(() => error = 'اختر الجنس');
      return;
    }
    if (!widget.google) {
      if (pw.text.length < 8) {
        setState(() => error = 'كلمة السر 8 أحرف على الأقل');
        return;
      }
      if (pw.text != pw2.text) {
        setState(() => error = 'كلمتا السر غير متطابقتين');
        return;
      }
    }
    setState(() {
      busy = true;
      error = '';
    });
    registering.value = true;
    final r = await registerAccount(
      name: name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
      gender: gender,
      pw: widget.google ? null : pw.text,
      code: widget.code,
    );
    if (r.isEmpty) {
      prefs.setBool('seen_login', true);
      reloadN.value++;
      registering.value = false;
      if (mounted && !widget.google) Navigator.of(context).popUntil((x) => x.isFirst);
      return;
    }
    registering.value = false;
    if (mounted) {
      setState(() {
        busy = false;
        error = r;
      });
    }
  }

  Widget _g(String v, String label, Color c) {
    final on = gender == v;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => gender = v),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c : const Color.fromRGBO(0, 0, 0, .3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? c : kLine),
          ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: on ? Colors.white : kTx)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FirShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('إنشاء حساب', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kTx)),
            const SizedBox(height: 12),
            const Text('اللقب (عربي فقط وبدون زخرفة)', style: TextStyle(fontSize: 12, color: kMu)),
            const SizedBox(height: 4),
            TextField(controller: name, maxLength: 20, textAlign: TextAlign.center, decoration: const InputDecoration(counterText: '', hintText: 'مثال: كاكاشي')),
            const SizedBox(height: 8),
            const Text('الجنس', style: TextStyle(fontSize: 12, color: kMu)),
            const SizedBox(height: 4),
            Row(children: [
              _g('m', 'ذكر', const Color(0xFF1E88E5)),
              const SizedBox(width: 10),
              _g('f', 'أنثى', const Color(0xFFFF4FA0)),
            ]),
            if (!widget.google) ...[
              const SizedBox(height: 10),
              const Text('كلمة السر (تدخل بها لاحقاً)', style: TextStyle(fontSize: 12, color: kMu)),
              const SizedBox(height: 4),
              TextField(controller: pw, obscureText: true, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: '8 أحرف على الأقل')),
              const SizedBox(height: 8),
              TextField(controller: pw2, obscureText: true, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: 'أعد كتابة كلمة السر')),
            ],
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFD0C0))),
              ),
            const SizedBox(height: 14),
            AppButton(busy ? '...' : 'تسجيل', glow: true, onPressed: busy ? null : _go),
          ],
        ),
      ),
    );
  }
}
