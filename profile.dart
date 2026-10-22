import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

/// بطاقة الملف التعريفي لأي عضو
Future<void> viewProfile(BuildContext context, String uid) async {
  final p = await prof(uid);
  final r = await roleOf(uid);
  String pid = '';
  try {
    pid = (await ref('pdata/$uid/pid').get()).value?.toString() ?? '';
  } catch (_) {}
  if (!context.mounted) return;
  final tag = rankTag(r);
  showAppSheet<void>(context, (sc) => [
        Center(child: UserAvatar(uid, size: 92)),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if (r == 'emp') ...[const SizedBox(width: 6), const InfinityMark(size: 22)],
            ],
          ),
        ),
        Center(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (r == 'dev' || r == 'emp') const DevBadge(),
              if (tag != null) tag,
              ageTag(p),
              Tag(p.gender == 'f' ? 'أنثى' : 'ذكر'),
            ],
          ),
        ),
        if (pid.isNotEmpty) Center(child: Text('ID: $pid', style: const TextStyle(color: kMu, letterSpacing: 1.5))),
      ]);
}
