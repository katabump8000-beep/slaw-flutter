import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

const Color _gold = Color(0xFFD4AF37);
const Color _goldLight = Color(0xFFF6D77A);

/// يفتح بطاقة الملف التعريفي لعضو
Future<void> viewProfile(BuildContext context, String u) async {
  if (u.isEmpty) return;
  final own = u == myUid;
  final p = await prof(u);
  final r = await roleOf(u);
  var pub = true;
  try {
    pub = (await ref('ppub/$u').get()).value != false;
  } catch (_) {}
  if (!context.mounted) return;
  if (!own && !pub && !Session.isDev) {
    _openPage(context, _PrivateCardPage());
    return;
  }
  var pd = <String, dynamic>{};
  try {
    final s = await ref('pdata/$u').get();
    if (s.value is Map) pd = Map<String, dynamic>.from(s.value as Map);
  } catch (_) {}
  var rk = '';
  try {
    rk = (await ref('rankt/$u').get()).value?.toString() ?? '';
  } catch (_) {}
  var fr = false;
  try {
    fr = (await ref('friends/$myUid/$u').get()).exists;
  } catch (_) {}
  if (!context.mounted) return;
  _openPage(
    context,
    _ProfileCardPage(u: u, p: p, role: r, pd: pd, rk: rk, isFriend: fr, own: own),
  );
}

void _openPage(BuildContext context, Widget page) {
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    pageBuilder: (ctx, a1, a2) => page,
    transitionsBuilder: (ctx, a, b, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _PrivateCardPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.6),
            radius: 1.2,
            colors: [Color(0xFF3A1608), Color(0xFF0C0502)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentA(context, .12),
                      boxShadow: [BoxShadow(color: accentA(context, .4), blurRadius: 30)],
                    ),
                    child: Icon(Icons.lock, size: 54, color: context.accent2),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'هذا الملف التعريفي خاص',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'اختار صاحبه إخفاءه عن الأعضاء',
                    style: TextStyle(color: kMu),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: 200,
                    child: AppButton('إغلاق', onPressed: () => Navigator.of(context).pop()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCardPage extends StatelessWidget {
  final String u;
  final Prof p;
  final String? role;
  final Map<String, dynamic> pd;
  final String rk;
  final bool isFriend;
  final bool own;

  const _ProfileCardPage({
    required this.u,
    required this.p,
    required this.role,
    required this.pd,
    required this.rk,
    required this.isFriend,
    required this.own,
  });

  @override
  Widget build(BuildContext context) {
    final royal = role == 'emp';
    final pid = pd['pid']?.toString() ?? '';
    final note = pd['note']?.toString() ?? '';
    final tags = <Widget>[];
    if (rk.isNotEmpty) {
      tags.add(Tag(rk, king: true));
    } else {
      final t = rankTag(role);
      if (t != null) tags.add(t);
    }
    tags.add(ageTag(p));
    tags.add(Tag(p.gender == 'f' ? 'أنثى' : 'ذكر'));

    final ringColor = royal ? _gold : context.accent;
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: royal
              ? const [Color(0xFF3A0714), Color(0xFF0A0204)]
              : const [kCard, Color(0xFF0C0502)],
        ),
        border: Border.all(
          color: royal ? const Color(0xFFB8923A) : context.accent,
          width: royal ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: royal ? const Color.fromRGBO(184, 146, 58, .5) : accentA(context, .35),
            blurRadius: royal ? 40 : 30,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (royal) const Icon(Icons.workspace_premium, size: 44, color: _gold),
          UserAvatar(u, size: royal ? 110 : 88, ring: true, ringColor: ringColor),
          const SizedBox(height: 10),
          Text(
            p.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: royal ? 28 : 22,
              fontWeight: FontWeight.w800,
              color: royal ? _goldLight : null,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: tags),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(0, 0, 0, .35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: royal ? _gold : context.accent2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ID', style: TextStyle(color: kMu, fontSize: 12)),
                const SizedBox(width: 10),
                Text(
                  pid.isEmpty ? '—' : pid,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: royal ? 22 : 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: royal ? _goldLight : null,
                  ),
                ),
                if (pid.isNotEmpty)
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: pid));
                      toast('تم النسخ');
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.copy, size: 16),
                    ),
                  ),
              ],
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, .06),
                borderRadius: BorderRadius.circular(12),
                border: royal ? Border.all(color: const Color.fromRGBO(212, 175, 55, .4)) : null,
              ),
              child: Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(color: royal ? _goldLight : context.accent2, height: 1.7),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'عضو منذ ${daysSince(p.ts)} يوم',
            style: const TextStyle(color: kMu, fontSize: 13),
          ),
          const SizedBox(height: 14),
          if (!own)
            Row(
              children: [
                Expanded(
                  child: isFriend
                      ? AppButton(
                          'حذف الصديق',
                          kind: 'r',
                          onPressed: () => confirmUnfriend(
                            context,
                            u,
                            p,
                            () {
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          ),
                        )
                      : AppButton('إرسال طلب صداقة', onPressed: () => sendFriendReq(u)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton('إبلاغ', kind: 'g', onPressed: () => reportSheet(context, u)),
                ),
              ],
            ),
          if (!own) const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: AppButton('إغلاق', kind: 'g', onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.6),
            radius: 1.2,
            colors: royal
                ? const [Color(0xFF4A0A1A), Color(0xFF0A0105)]
                : const [Color(0xFF3A1608), Color(0xFF0C0502)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: card),
            ),
          ),
        ),
      ),
    );
  }
}

/// تأكيد حذف صديق
void confirmUnfriend(BuildContext context, String u, Prof p, VoidCallback onDone) {
  showAppSheet<void>(context, (sc) => [
        Text(
          'حذف ${p.name} من أصدقائك؟',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        Row(
          children: [
            Expanded(
              child: AppButton(
                'نعم',
                kind: 'r',
                onPressed: () async {
                  Navigator.pop(sc);
                  try {
                    await db.ref().update(<String, Object?>{
                      'friends/$myUid/$u': null,
                      'friends/$u/$myUid': null,
                    });
                    toast('تم حذف الصديق');
                    onDone();
                  } catch (e) {
                    err(e);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: AppButton('لا', kind: 'g', onPressed: () => Navigator.pop(sc))),
          ],
        ),
      ]);
}

const List<String> _reportReasons = ['سبام', 'إساءة', 'انتحال', 'محتوى غير لائق', 'أخرى'];

/// نافذة الإبلاغ عن عضو (تكتب في reports)
void reportSheet(BuildContext context, String u) {
  showAppSheet<void>(context, (sc) => [
        const Text(
          'إبلاغ عن العضو',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        for (final r in _reportReasons)
          AppButton(
            r,
            kind: 'g',
            onPressed: () async {
              Navigator.pop(sc);
              try {
                await ref('reports').push().set(<String, Object?>{
                  'from': myUid,
                  'tg': u,
                  'r': r,
                  'ts': ServerValue.timestamp,
                });
                toast('تم إرسال البلاغ للمشرفين', accent: true);
              } catch (e) {
                err(e);
              }
            },
          ),
        AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.pop(sc)),
      ]);
}

/// إرسال طلب صداقة (freq + notifs)
Future<void> sendFriendReq(String u) async {
  if (u == myUid) {
    toast('هذا ملفك أنت', bad: true);
    return;
  }
  try {
    if ((await ref('friends/$myUid/$u').get()).exists) {
      toast('أنتما صديقان بالفعل', bad: true);
      return;
    }
    if ((await ref('freq/$u/$myUid').get()).exists) {
      toast('أرسلت طلباً سابقاً', bad: true);
      return;
    }
    final k = ref('notifs/$u').push().key;
    await db.ref().update(<String, Object?>{
      'freq/$u/$myUid': <String, Object?>{'ts': ServerValue.timestamp},
      'notifs/$u/$k': <String, Object?>{
        't': 'fr',
        'from': myUid,
        'ts': ServerValue.timestamp,
      },
    });
    toast('تم إرسال طلب الصداقة', accent: true);
  } catch (e) {
    err(e);
  }
}

/// نافذة إضافة صديق بالـ ID
void addFriendSheet(BuildContext context) {
  showAppSheet<void>(context, (sc) => [_AddFriendBody(parent: context, sheetCtx: sc)]);
}

class _AddFriendBody extends StatefulWidget {
  final BuildContext parent;
  final BuildContext sheetCtx;
  const _AddFriendBody({required this.parent, required this.sheetCtx});

  @override
  State<_AddFriendBody> createState() => _AddFriendBodyState();
}

class _AddFriendBodyState extends State<_AddFriendBody> {
  final TextEditingController ctrl = TextEditingController();
  bool notFound = false;
  String? foundUid;
  Prof? foundProf;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final id = normDigits(ctrl.text.trim());
    setState(() {
      notFound = false;
      foundUid = null;
    });
    if (!RegExp(r'^[0-9]{9}$').hasMatch(id)) {
      toast('المعرف 9 أرقام', bad: true);
      return;
    }
    try {
      final t = (await ref('pids/$id').get()).value;
      if (t == null) {
        if (mounted) setState(() => notFound = true);
        return;
      }
      final tu = t.toString();
      final p = await prof(tu);
      if (mounted) {
        setState(() {
          foundUid = tu;
          foundProf = p;
        });
      }
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tu = foundUid;
    final fp = foundProf;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'إضافة صديق',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          maxLength: 9,
          textAlign: TextAlign.center,
          style: const TextStyle(letterSpacing: 3, fontSize: 18),
          decoration: const InputDecoration(hintText: 'ضع المعرف (ID) المكوّن من 9 أرقام', counterText: ''),
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 10),
        AppButton('بحث', onPressed: _search),
        if (notFound)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('لا يوجد عضو بهذا المعرف', style: TextStyle(color: kMu))),
          ),
        if (tu != null && fp != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              children: [
                UserAvatar(tu, size: 88),
                const SizedBox(height: 8),
                Text(fp.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (tu == myUid)
                  const Text('هذا أنت', style: TextStyle(color: kMu))
                else
                  Row(
                    children: [
                      Expanded(child: AppButton('إرسال طلب صداقة', onPressed: () => sendFriendReq(tu))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppButton(
                          'عرض الملف التعريفي',
                          kind: 'g',
                          onPressed: () {
                            Navigator.pop(widget.sheetCtx);
                            viewProfile(widget.parent, tu);
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        AppButton('إغلاق', kind: 'g', onPressed: () => Navigator.pop(widget.sheetCtx)),
      ],
    );
  }
}
