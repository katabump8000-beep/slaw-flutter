import 'servertime.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';

/// نص «منذ ...» بالعربية (لا يرجع أبداً «غير معروف»)
String agoArabic(int ts) {
  final d = nowMs() - ts;
  if (d < 60000) return 'منذ لحظات';
  final m = d ~/ 60000;
  if (m < 60) return m == 1 ? 'منذ دقيقة' : (m == 2 ? 'منذ دقيقتين' : (m <= 10 ? 'منذ $m دقائق' : 'منذ $m دقيقة'));
  final h = m ~/ 60;
  if (h < 24) return h == 1 ? 'منذ ساعة' : (h == 2 ? 'منذ ساعتين' : (h <= 10 ? 'منذ $h ساعات' : 'منذ $h ساعة'));
  final dd = h ~/ 24;
  if (dd == 1) return 'أمس';
  if (dd == 2) return 'منذ يومين';
  if (dd <= 10) return 'منذ $dd أيام';
  if (dd < 30) return 'منذ $dd يوماً';
  final mo = dd ~/ 30;
  if (mo < 12) return mo == 1 ? 'منذ شهر' : (mo == 2 ? 'منذ شهرين' : (mo <= 10 ? 'منذ $mo أشهر' : 'منذ $mo شهراً'));
  return 'منذ أكثر من سنة';
}

/// يحسب نص آخر ظهور: متصل الآن / آخر ظهور منذ ...
/// إن لم يوجد سجل ظهور يُستعمل وقت إنشاء الحساب بدل كلمة «غير معروف»
String lastSeenText({required bool online, required int seenTs, required int joinTs}) {
  if (online) return 'متصل الآن';
  final t = seenTs > 0 ? seenTs : joinTs;
  if (t <= 0) return 'آخر ظهور: منذ مدة';
  return 'آخر ظهور: ${agoArabic(t)}';
}

Future<String> lastSeenLabel(String uid) async {
  var online = false;
  var seenTs = 0;
  var joinTs = 0;
  try {
    online = (await ref('presence/$uid').get()).value == true;
  } catch (_) {}
  try {
    final v = (await ref('seen/$uid/t').get()).value;
    if (v is num) seenTs = v.toInt();
  } catch (_) {}
  if (seenTs <= 0) {
    try {
      joinTs = (await prof(uid)).ts;
    } catch (_) {}
  }
  return lastSeenText(online: online, seenTs: seenTs, joinTs: joinTs);
}

/// سطر «آخر ظهور» الصغير (للملف التعريفي وقوائم الأصدقاء)
class LastSeenLine extends StatelessWidget {
  final String uid;
  final double size;
  const LastSeenLine(this.uid, {super.key, this.size = 11.5});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('presence/$uid').onValue,
      builder: (c, p) {
        final on = p.data?.snapshot.value == true;
        return StreamBuilder<DatabaseEvent>(
          stream: ref('seen/$uid/t').onValue,
          builder: (c2, s) {
            final v = s.data?.snapshot.value;
            final t = v is num ? v.toInt() : 0;
            return FutureBuilder<Prof>(
              future: prof(uid),
              builder: (c3, pr) {
                final txt = lastSeenText(online: on, seenTs: t, joinTs: pr.data?.ts ?? 0);
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: on ? const Color(0xFF2EE07A) : kMu)),
                  const SizedBox(width: 5),
                  Text(txt, style: TextStyle(fontSize: size, color: on ? const Color(0xFF2EE07A) : kMu, fontWeight: FontWeight.w700)),
                ]);
              },
            );
          },
        );
      },
    );
  }
}
