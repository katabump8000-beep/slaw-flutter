import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'accounts.dart';
import 'app_state.dart';
import 'board.dart';
import 'data.dart';
import 'devtools2.dart';
import 'devtools3.dart';
import 'football.dart';
import 'friends.dart';
import 'links.dart';
import 'moneytools.dart';
import 'pwchange.dart';
import 'settings.dart';
import 'shop.dart';
import 'solo.dart';
import 'sorter.dart';
import 'support.dart';
import 'tools.dart';
import 'widgets.dart';

// ======================================================================
// الذكاء الاصطناعي: يعمل عبر السيرفر (لا مفاتيح داخل التطبيق).
// staff=true: مساعد المطورين/الإمبراطور (أوامر محدودة وآمنة) — staff=false: مساعد الأعضاء (257 رسالة يومياً)
// ======================================================================

Future<Map<dynamic, dynamic>> aiCall(String q, String kind) async {
  final rid = ref('aiReq').push().key!;
  final done = Completer<Map<dynamic, dynamic>>();
  final sub = ref('aiRes/$myUid').onValue.listen((e) {
    final v = e.snapshot.value;
    if (v is Map && v['id'] == rid && !done.isCompleted) done.complete(v);
  }, onError: (_) {});
  String why = '';
  try {
    await ref('aiReq/$rid').set(<String, Object?>{'u': myUid, 'ts': ServerValue.timestamp, 'q': q, 'k': kind}).timeout(const Duration(seconds: 8));
  } catch (e) {
    why = e.toString().toLowerCase().contains('permission') ? 'rules' : 'net';
  }
  Map<dynamic, dynamic>? r;
  if (why.isEmpty) {
    try {
      r = await done.future.timeout(const Duration(seconds: 40));
    } catch (_) {
      r = null;
    }
  }
  await sub.cancel();
  return r ?? <dynamic, dynamic>{'err': why.isNotEmpty ? why : 'timeout'};
}

String _aiErr(String e) {
  switch (e) {
    case 'limit':
      return 'وصلت للحد اليومي (257 رسالة). عد غداً 🌙';
    case 'nokey':
      return 'الذكاء الاصطناعي غير مفعّل بعد (لم يوضع مفتاحه في السيرفر).';
    case 'off':
      return 'عذرا قام أحد المطورين بإيقاف هذه!';
    case 'perm':
      return 'هذا المساعد للمطورين فقط.';
    case 'rules':
      return 'قواعد قاعدة البيانات لم تُحدَّث بعد (aiReq).';
    case 'net':
      return 'لا يوجد اتصال بالإنترنت.';
    case 'timeout':
      return 'السيرفر لا يستجيب الآن، حاول بعد دقيقة.';
    default:
      return 'تعذر الرد الآن، حاول مجدداً.';
  }
}

class _Msg {
  final bool me;
  String text;
  String go;
  bool card;
  _Msg(this.me, this.text, {this.go = '', this.card = false});
}

class AiChatScreen extends StatefulWidget {
  final bool staff;
  const AiChatScreen({super.key, required this.staff});

  @override
  State<AiChatScreen> createState() => _AiChatState();
}

class _AiChatState extends State<AiChatScreen> {
  final TextEditingController input = TextEditingController();
  final ScrollController sc = ScrollController();
  final List<_Msg> msgs = [];
  String mode = 'talk'; // talk | cards | move (للمطورين)
  bool busy = false;
  bool typing = false;
  bool stopped = false;
  int used = 0;
  Timer? tt;

  @override
  void initState() {
    super.initState();
    final nm = Session.me.name;
    msgs.add(_Msg(false, widget.staff ? 'مرحبا يا $nm انا هو الذكاء الاصطناعي المخصص لخدمتك يمكنني فعل كل شيء تريده!' : 'أهلاً $nm! أنا مساعد FIR 🤖 اسألني عن أي شيء في التطبيق وأرشدك.'));
    if (!widget.staff) {
      ref('aiLim/$myUid').get().then((s) {
        final v = s.value;
        final today = DateTime.now().toUtc().add(const Duration(hours: 3)).toIso8601String().substring(0, 10);
        if (v is Map && v['d'] == today && mounted) setState(() => used = (v['n'] as num?)?.toInt() ?? 0);
      }).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    tt?.cancel();
    input.dispose();
    sc.dispose();
    super.dispose();
  }

  void _down() {
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (sc.hasClients) sc.animateTo(sc.position.maxScrollExtent + 120, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  // نقل: توجيه فوري لأدوات المطورين بالكلمات المفتاحية (بدون استدعاء السيرفر)
  Widget? _moveTarget(String q) {
    final m = <String, Widget Function()>{
      'سحب': () => const GiveTakeScreen(),
      'اعطاء': () => const GiveTakeScreen(),
      'إعطاء': () => const GiveTakeScreen(),
      'بنك': () => const BankScreen(),
      'حسابات': () => const AccountsScreen(),
      'حساب': () => const AccountsScreen(),
      'روابط': () => const LinksScreen(),
      'رابط': () => const LinksScreen(),
      'احصائيات': () => const StatsScreen(),
      'إحصائيات': () => const StatsScreen(),
      'فرز': () => const SorterScreen(),
      'جوائز': () => const EventPrizesScreen(),
      'ايقاف': () => const FeatureSwitchScreen(),
      'إيقاف': () => const FeatureSwitchScreen(),
      'كرة': () => const FootballAdminScreen(),
      'اقتراحات': () => const SuggestionsScreen(),
      'شعاري': () => const ShiarScreen(),
      'أدوات': () => const ToolsScreen(),
      'ادوات': () => const ToolsScreen(),
    };
    for (final e in m.entries) {
      if (q.contains(e.key)) return e.value();
    }
    return null;
  }

  Widget? _goTarget(String k) {
    switch (k) {
      case 'password':
        return const ChangePasswordScreen();
      case 'settings':
      case 'sound':
      case 'notifications':
        return const SettingsScreen();
      case 'friends':
        return const FriendsScreen();
      case 'support':
        return const SupportScreen();
      case 'leaderboard':
        return const BoardScreen();
      case 'shop':
        return const ShopScreen();
    }
    return null;
  }

  Future<void> _reveal(_Msg m, String full) async {
    typing = true;
    stopped = false;
    m.text = '';
    final c = Completer<void>();
    var i = 0;
    tt = Timer.periodic(const Duration(milliseconds: 28), (t) {
      if (!mounted || stopped) {
        t.cancel();
        if (!c.isCompleted) c.complete();
        return;
      }
      i = (i + 2).clamp(0, full.length);
      m.text = full.substring(0, i);
      if (mounted) setState(() {});
      _down();
      if (i >= full.length) {
        t.cancel();
        if (!c.isCompleted) c.complete();
      }
    });
    await c.future;
    typing = false;
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final q = input.text.trim();
    if (q.isEmpty || busy || typing) return;
    input.clear();
    setState(() {
      msgs.add(_Msg(true, q));
      busy = true;
    });
    _down();
    // وضع «نقل» للمطورين: توجيه محلي
    if (widget.staff && mode == 'move') {
      final t = _moveTarget(q);
      setState(() {
        busy = false;
        msgs.add(_Msg(false, t == null ? 'لم أفهم أين تريد الذهاب. جرّب: السحب، البنك، الحسابات، الروابط، الإحصائيات، الفرز...' : 'هل تريد أن أنقلك للصفحة التي طلبتها؟', go: t == null ? '' : q));
      });
      _down();
      return;
    }
    final r = await aiCall(q, widget.staff ? 'd' : 'm');
    if (!mounted) return;
    final err = (r['err'] ?? '').toString();
    final m = _Msg(false, '', card: widget.staff && mode == 'cards');
    setState(() {
      msgs.add(m);
      busy = false;
    });
    if (err.isNotEmpty) {
      setState(() => m.text = _aiErr(err));
      return;
    }
    if (r['used'] is num) used = (r['used'] as num).toInt();
    m.go = (r['go'] ?? '').toString();
    await _reveal(m, (r['text'] ?? '').toString());
  }

  void _openGo(_Msg m) {
    Widget? t;
    if (widget.staff && m.go.isNotEmpty && m.go.length > 1 && _goTarget(m.go) == null) {
      t = _moveTarget(m.go);
    } else {
      t = _goTarget(m.go);
    }
    if (t == null) {
      toast('لا أستطيع نقلك لهذه الصفحة', bad: true);
      return;
    }
    final w = t;
    m.go = '';
    setState(() {});
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
  }

  Widget _bubble(_Msg m) {
    final bg = m.me ? context.accent.withAlpha(60) : (m.card ? const Color(0xFF14213D) : kCard);
    return Align(
      alignment: m.me ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: m.card ? context.accent : kLine)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.text.isEmpty && !m.me ? '...' : m.text, style: const TextStyle(fontSize: 14.5, height: 1.6)),
          if (m.go.isNotEmpty && !m.me)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(child: AppButton('موافق', compact: true, onPressed: () => _openGo(m))),
                const SizedBox(width: 8),
                Expanded(child: AppButton('رفض', kind: 'g', compact: true, onPressed: () => setState(() => m.go = ''))),
              ]),
            ),
        ]),
      ),
    );
  }

  Future<void> _plus() async {
    await showAppSheet<void>(context, (s) => [
          AppButton('📷 ارسال صورة', kind: 'g', onPressed: () {
            Navigator.of(s).pop();
            toast('إرسال الصور للمساعد غير متاح بعد');
          }),
          AppButton('📎 ارسال ملف', kind: 'g', onPressed: () {
            Navigator.of(s).pop();
            toast('إرسال الملفات للمساعد غير متاح بعد');
          }),
          AppButton('🗑 حذف الشات', kind: 'r', onPressed: () {
            Navigator.of(s).pop();
            setState(() => msgs.removeRange(1, msgs.length));
          }),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.staff ? 'AI 🤖' : 'مساعد FIR 🤖')),
      body: Column(children: [
        if (!widget.staff)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            color: accentA(context, .08),
            child: Row(children: [
              Text('${257 - used} متبقية', style: const TextStyle(fontSize: 11.5, color: kMu)),
              const SizedBox(width: 10),
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: (257 - used) / 257, minHeight: 5, backgroundColor: Colors.white12, color: context.accent))),
            ]),
          ),
        if (widget.staff)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              for (final it in const [['cards', 'بطاقات'], ['move', 'نقل'], ['talk', 'التحدث']])
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(label: Text(it[1]), selected: mode == it[0], onSelected: (_) => setState(() => mode = it[0])),
                ),
            ]),
          ),
        Expanded(
          child: ListView(controller: sc, padding: const EdgeInsets.all(12), children: [for (final m in msgs) _bubble(m), if (busy) const Padding(padding: EdgeInsets.all(8), child: Align(alignment: Alignment.centerRight, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: Row(children: [
              if (widget.staff) IconButton(onPressed: _plus, icon: const Icon(Icons.add_circle_outline)),
              Expanded(child: TextField(controller: input, minLines: 1, maxLines: 4, maxLength: 400, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'اكتب رسالتك...', counterText: ''))),
              const SizedBox(width: 6),
              typing
                  ? IconButton(onPressed: () => setState(() => stopped = true), icon: const Icon(Icons.stop_circle_outlined, color: Color(0xFFFF4D4D), size: 30))
                  : IconButton(onPressed: busy ? null : _send, icon: Icon(Icons.send_rounded, color: context.accent)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// «حالة Ai» (للإمبراطور): هل المساعد شغّال؟ وهل وُضع مفتاحه في السيرفر؟
class AiStatusScreen extends StatefulWidget {
  const AiStatusScreen({super.key});

  @override
  State<AiStatusScreen> createState() => _AiStatusState();
}

class _AiStatusState extends State<AiStatusScreen> {
  String line = 'جاري الفحص...';
  bool? hasKey;
  bool off = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => line = 'جاري الفحص...');
    final r = await aiCall('ping', 'p');
    if (!mounted) return;
    final err = (r['err'] ?? '').toString();
    setState(() {
      if (err.isNotEmpty) {
        line = _aiErr(err);
        hasKey = null;
      } else {
        hasKey = r['key'] == true;
        off = r['off'] == true;
        line = !hasKey! ? '⚠️ لم يوضع رمز (OPENROUTER_KEY) في السيرفر' : (off ? '⛔ متوقف بقرار منك' : '✅ شغّال');
      }
    });
  }

  Future<void> _toggle() async {
    try {
      await ref('config/off/ai').set(off ? null : true);
      await _check();
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حالة Ai')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(line, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.6)),
            const SizedBox(height: 18),
            if (hasKey == true) AppButton(off ? 'تشغيل الذكاء الاصطناعي' : 'إيقاف الذكاء الاصطناعي', kind: off ? 'p' : 'r', onPressed: _toggle),
            const SizedBox(height: 8),
            AppButton('إعادة الفحص', kind: 'g', compact: true, onPressed: _check),
          ]),
        ),
      ),
    );
  }
}
