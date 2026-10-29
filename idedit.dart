import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

/// تعديل معرّف (ID) أي مستخدم — للإمبراطور والمطورين
Future<void> editPidDialog(BuildContext context, String uid) async {
  String old = '';
  try {
    old = (await ref('pdata/$uid/pid').get()).value?.toString() ?? '';
  } catch (_) {}
  final c = TextEditingController(text: old);
  if (!context.mounted) return;
  await showAppSheet<void>(context, (sc) => [
        const Text('تعديل المعرّف', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        if (old.isNotEmpty) Center(child: Text('الحالي: $old', style: const TextStyle(color: kMu))),
        TextField(controller: c, keyboardType: TextInputType.number, maxLength: 12, decoration: const InputDecoration(hintText: 'المعرّف الجديد (4 إلى 12 رقماً)', counterText: '')),
        AppButton('حفظ', onPressed: () async {
          final n = normDigits(c.text.trim());
          if (!RegExp(r'^[0-9]{4,12}$').hasMatch(n)) {
            toast('أرقام فقط، من 4 إلى 12', bad: true);
            return;
          }
          if (n == old) {
            if (sc.mounted) Navigator.of(sc).pop();
            return;
          }
          try {
            final ex = await ref('pids/$n').get();
            if (ex.exists) {
              toast('هذا المعرّف مستخدم', bad: true);
              return;
            }
            final up = <String, Object?>{'pids/$n': uid, 'pdata/$uid/pid': n};
            if (old.isNotEmpty) up['pids/$old'] = null;
            await db.ref().update(up);
            if (uid == myUid) Session.pid = n;
            if (sc.mounted) Navigator.of(sc).pop();
            toast('تم تعديل المعرّف ✅');
          } catch (e) {
            err(e);
          }
        }),
      ]);
}
