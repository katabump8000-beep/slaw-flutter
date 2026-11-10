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
import 'kingdoms.dart';
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

String _aiErr(String e, [String d = '']) {
  switch (e) {
    case 'limit':
      return 'وصلت للحد اليومي (257 رسالة). عد غداً 🌙';
    case 'nokey':
      return 'لا يوجد مفتاح للذكاء الاصطناعي في السيرفر. (الإمبراطور: افتح الإعدادات ← حالة Ai)';
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
    case 'fail':
    case 'server':
      final why = d == 'http401'
          ? 'مفتاح OpenRouter مرفوض (401): أنشئ مفتاحاً جديداً من openrouter.ai/keys والصقه في الإعدادات ← حالة Ai'
          : d == 'http402'
              ? 'رصيد OpenRouter منتهٍ (402)'
              : d == 'http429'
                  ? 'ضغط كبير على النموذج (429)، حاول بعد قليل'
                  : (d == 'http400' || d == 'http404')
                      ? 'اسم النموذج غير صحيح (${d.substring(4)})'
                      : d.isEmpty
                          ? ''
                          : d;
      return why.isEmpty ? 'تعذر الرد الآن، حاول مجدداً.' : 'تعذر الرد: $why';
    default:
      return 'تعذر الرد الآن، حاول مجدداً.';
  }
}

class _Msg {
  final bool me;
  String text;
  String go;
  bool card;
  String cardTitle = '';
  List<List<String>> rows = [];
  String gu = '';
  String gn = '';
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
      case 'giveTake':
        return const GiveTakeScreen();
      case 'bank':
        return const BankScreen();
      case 'accounts':
        return const AccountsScreen();
      case 'links':
        return const LinksScreen();
      case 'stats':
        return const StatsScreen();
      case 'sorter':
        return const SorterScreen();
      case 'prizes':
        return const EventPrizesScreen();
      case 'switches':
        return const FeatureSwitchScreen();
      case 'football':
        return const FootballAdminScreen();
      case 'suggestions':
        return const SuggestionsScreen();
      case 'shiar':
        return const ShiarScreen();
      case 'tools':
        return const ToolsScreen();
      case 'kingdoms':
        return const KingdomsScreen();
      case 'ledger':
        return null; // يُفتح من _openGo (يحتاج معرّف العضو)
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
    // وضع «نقل»: نطلب من الذكاء الاصطناعي فهم الصفحة المقصودة بأي صياغة
    final ask = (widget.staff && mode == 'move') ? 'انقلني إلى: $q' : q;
    final r = await aiCall(ask, widget.staff ? 'd' : 'm');
    if (!mounted) return;
    final err = (r['err'] ?? '').toString();
    final m = _Msg(false, '', card: false);
    setState(() {
      msgs.add(m);
      busy = false;
    });
    if (err.isNotEmpty) {
      // وضع «نقل»: إن تعذر الذكاء الاصطناعي نحاول بالكلمات المفتاحية
      final t = (widget.staff && mode == 'move') ? _moveTarget(q) : null;
      if (t != null) {
        setState(() {
          m.text = 'هل تريد أن أنقلك للصفحة التي طلبتها؟';
          m.go = q;
        });
        return;
      }
      setState(() => m.text = _aiErr(err, (r['d'] ?? '').toString()));
      return;
    }
    if (r['used'] is num) used = (r['used'] as num).toInt();
    m.go = (r['go'] ?? '').toString();
    m.gu = (r['gu'] ?? '').toString();
    m.gn = (r['gn'] ?? '').toString();
    final cd = r['card'];
    if (widget.staff && cd is Map && mode != 'talk') {
      m.card = true;
      m.cardTitle = (cd['title'] ?? '').toString();
      final rows = cd['rows'];
      if (rows is List) {
        m.rows = rows.map((e) => (e is List ? e.map((x) => x.toString()).toList() : <String>[e.toString()])).toList();
      }
    }
    await _reveal(m, (r['text'] ?? '').toString());
  }

  void _openGo(_Msg m) {
    Widget? t;
    if (m.go == 'ledger' && m.gu.isNotEmpty) {
      t = LedgerScreen(uid: m.gu, name: m.gn.isEmpty ? 'عضو' : m.gn);
    } else if (widget.staff && m.go.length > 1 && _goTarget(m.go) == null) {
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
    final bg = m.me ? context.accent.withAlpha(60) : (m.card ? const Color(0xFF0B0B0B) : kCard);
    return Align(
      alignment: m.me ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: m.card ? context.accent : kLine, width: m.card ? 1.6 : 1),
          boxShadow: m.card ? [BoxShadow(color: context.accent.withAlpha(70), blurRadius: 16)] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (m.card && m.cardTitle.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(m.cardTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: context.accent))),
          if (m.card && m.rows.isNotEmpty)
            for (final r in m.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(r.isNotEmpty ? r[0] : '', style: const TextStyle(fontSize: 13.5, color: Colors.white70))),
                  const SizedBox(width: 10),
                  Text(r.length > 1 ? r[1] : '', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
                ]),
              ),
          if (!(m.card && m.rows.isNotEmpty))
            Text(m.text.isEmpty && !m.me ? '...' : m.text, style: const TextStyle(fontSize: 14.5, height: 1.6)),
          if (m.go.isNotEmpty && !m.me)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(child: AppButton(m.go == 'ledger' ? 'فتح السجل' : 'موافق', compact: true, onPressed: () => _openGo(m))),
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
  final TextEditingController keyC = TextEditingController();
  final TextEditingController modelC = TextEditingController();

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
        final src = {'env': 'متغير البيئة', 'db': 'قاعدة البيانات', 'file': 'ملف ai-key.txt'}[(r['src'] ?? '').toString()] ?? '';
        final last = (r['last'] ?? '').toString();
        line = !hasKey!
            ? '⚠️ لا يوجد مفتاح في السيرفر\nافتح التطبيق بحساب الإمبراطور أو الصق المفتاح بالأسفل\n(نسخة السيرفر ${r['ver'] ?? '?'})'
            : '${off ? '⛔ متوقف بقرار منك' : '✅ شغّال'}\nمصدر المفتاح: $src\nالنموذج: ${r['model'] ?? ''}\nنسخة السيرفر: ${r['ver'] ?? '?'}${last.isEmpty ? '' : '\nآخر خطأ: $last'}';
      }
    });
  }

  @override
  void dispose() {
    keyC.dispose();
    modelC.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final k = keyC.text.trim();
    if (k.length < 10) {
      toast('ألصق المفتاح كاملاً', bad: true);
      return;
    }
    try {
      await ref('secrets/aiKey').set(k);
      await ref('config/aiManual').set(true); // من الآن لا يكتب التطبيق مفتاحه القديم فوق هذا المفتاح
      if (modelC.text.trim().isNotEmpty) await ref('secrets/aiModel').set(modelC.text.trim());
      keyC.clear();
      toast('تم حفظ المفتاح ✅', accent: true);
      await _check();
    } catch (e) {
      err(e);
    }
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
            const SizedBox(height: 22),
            const Text('وضع مفتاح جديد:\n1) افتح openrouter.ai/keys وأنشئ مفتاحاً جديداً (Create Key)\n2) الصقه هنا واضغط «حفظ المفتاح»\nيُحفظ في قاعدة البيانات للسيرفر فقط، ولا يُقرأ من أي جهاز، ولا تضعه في GitHub.', textAlign: TextAlign.center, style: TextStyle(color: kMu, fontSize: 12.5, height: 1.7)),
            const SizedBox(height: 8),
            TextField(controller: keyC, obscureText: true, decoration: const InputDecoration(hintText: 'المفتاح (sk-or-...)')),
            const SizedBox(height: 8),
            TextField(controller: modelC, decoration: const InputDecoration(hintText: 'النموذج (اختياري)')),
            const SizedBox(height: 8),
            AppButton('حفظ المفتاح', compact: true, onPressed: _saveKey),
          ]),
        ),
      ),
    );
  }
}
