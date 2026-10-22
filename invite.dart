import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

/// صفحة الدعوة (تفتح التطبيق إن كان مثبتاً، وإلا تطلب تثبيته)
const String kInviteBase = 'https://katabump8000-beep.github.io/SLAW/join.html';

/// قسم «رابط النشر» داخل معلومات النقابة: لكل عضو رابطه الخاص
class InviteSection extends StatefulWidget {
  final String gid;
  const InviteSection({super.key, required this.gid});

  @override
  State<InviteSection> createState() => _InviteSectionState();
}

class _InviteSectionState extends State<InviteSection> {
  String code = '';
  int count = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = widget.gid;
      final s = await ref('pubPerm/$g/$myUid').get();
      if (s.exists) {
        code = s.value.toString();
      } else {
        final rnd = Random.secure();
        for (var i = 0; i < 8 && code.isEmpty; i++) {
          final c = (10000000 + rnd.nextInt(90000000)).toString();
          if ((await ref('refCodes/$c').get()).exists) continue;
          await ref('refCodes/$c').set(<String, Object?>{'u': myUid, 'g': g});
          await ref('pubPerm/$g/$myUid').set(c);
          code = c;
        }
      }
      final n = await ref('pubCount/$myUid').get();
      count = n.value is num ? (n.value as num).toInt() : 0;
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String get link => '$kInviteBase?c=$code';

  void _more() {
    showAppSheet<void>(context, (sc) => [
          Row(
            children: [
              const Expanded(child: Text('تعرف على المزيد', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.of(sc).pop(), icon: const Icon(Icons.close)),
            ],
          ),
          const Text(
            'عندما تعطي شخصاً تطبيق FIR ويقوم بتحميله، اجعله يدخل رابط النشر الخاص بك ليتمكن من الدخول إلى النقابة وتسجيل لقبه.',
            style: TextStyle(height: 1.9),
          ),
          Text('المكافآت:', style: TextStyle(fontWeight: FontWeight.w800, color: context.accent2)),
          _bullet(const Color(0xFFFFB04A), '200 \$ لكل عضو يدخل من طرفك'),
          _bullet(const Color(0xFF6EE787), 'تتم ترقيتك إلى رتبة عالية في حال كان نشرك يتجاوز 10 أعضاء'),
          _bullet(const Color(0xFF7FB2FF), 'تحصل على مؤثرات خاصة ومكانة خاصة'),
        ]);
  }

  Widget _bullet(Color c, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(t, style: const TextStyle(height: 1.7))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentA(context, .5)),
        color: accentA(context, .07),
      ),
      child: loading
          ? const Center(child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('رابط النشر الخاص بك', style: TextStyle(fontWeight: FontWeight.w800, color: context.accent2)),
                const SizedBox(height: 8),
                if (code.isEmpty)
                  const Text('تعذر إنشاء الرابط، تأكد من الاتصال.', style: TextStyle(color: kMu))
                else ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .35), borderRadius: BorderRadius.circular(10)),
                    child: Text(link, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5)),
                  ),
                  const SizedBox(height: 8),
                  AppButton('نسخ', onPressed: () {
                    Clipboard.setData(ClipboardData(text: link));
                    toast('تم نسخ الرابط');
                  }),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Text('ستحصل على 200 عملة في حال دخل أحد من طرفك.', style: TextStyle(fontSize: 12.5, color: kMu))),
                    GestureDetector(
                      onTap: _more,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.accent2)),
                        child: Text('؟', style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: GestureDetector(
                    onTap: _more,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('تعرف على المزيد', style: TextStyle(fontSize: 11, color: context.accent2)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('النشر: $count', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
    );
  }
}
