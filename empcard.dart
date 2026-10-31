import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'media.dart';
import 'profile.dart';
import 'widgets.dart';

/// بطاقة المؤسس: الصورة والاسم. حلقة خضراء حول الصورة إن كان رافعاً حالة
class EmperorCard extends StatelessWidget {
  const EmperorCard({super.key});

  @override
  Widget build(BuildContext context) {
    final e = Session.emp;
    if (e.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DatabaseEvent>(
      stream: ref('media/status/ts').onValue,
      builder: (c, s) {
        final has = s.data?.snapshot.value != null;
        if (has) prefetchMedia('status');
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD4AF37)),
            gradient: const LinearGradient(colors: [Color(0xFF3A0F1C), Color(0xFF14070C)]),
          ),
          child: Row(children: [
            GestureDetector(
              onTap: () {
                if (has) {
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VideoScreen(keyName: 'status', title: 'حالة المؤسس')));
                } else {
                  viewProfile(context, e);
                }
              },
              child: Container(
                padding: EdgeInsets.all(has ? 3 : 0),
                decoration: BoxDecoration(shape: BoxShape.circle, border: has ? Border.all(color: const Color(0xFF2EE07A), width: 3) : null),
                child: UserAvatar(e, size: 54),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => viewProfile(context, e),
                child: FutureBuilder<Prof>(
                  future: prof(e),
                  builder: (c, p) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.data?.name ?? '...', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const Text('المؤسس', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
