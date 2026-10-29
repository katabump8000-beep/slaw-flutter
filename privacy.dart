import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

/// إعدادات الخصوصية: ملف خاص/عام + الملاحظة
class ProfilePrivacyTiles extends StatefulWidget {
  const ProfilePrivacyTiles({super.key});
  @override
  State<ProfilePrivacyTiles> createState() => _PrivacyState();
}

class _PrivacyState extends State<ProfilePrivacyTiles> {
  bool priv = false;
  String note = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = (await ref('pdata/$myUid/priv').get()).value;
      final b = (await ref('pdata/$myUid/note').get()).value;
      if (mounted) setState(() {
        priv = a == true;
        note = b?.toString() ?? '';
      });
    } catch (_) {}
  }

  Future<void> _editNote() async {
    final c = TextEditingController(text: note);
    await showAppSheet<void>(context, (sc) => [
          const Text('ملاحظتي', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Text('تظهر عند فتح ملفك التعريفي', style: TextStyle(color: kMu, fontSize: 12)),
          TextField(controller: c, maxLength: 200, maxLines: 3, decoration: const InputDecoration(hintText: 'اكتب ملاحظتك')),
          AppButton('حفظ', onPressed: () async {
            final t = c.text.trim();
            try {
              await ref('pdata/$myUid/note').set(t.isEmpty ? null : t);
              if (mounted) setState(() => note = t);
              if (sc.mounted) Navigator.of(sc).pop();
              toast('تم الحفظ ✅');
            } catch (e) {
              err(e);
            }
          }),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SwitchListTile(
        value: priv,
        title: const Text('ملفي التعريفي خاص'),
        subtitle: const Text('لا يرى الأعضاء إحصائياتك، ويراها المشرفون فقط', style: TextStyle(color: kMu, fontSize: 12)),
        onChanged: (v) async {
          setState(() => priv = v);
          try {
            await ref('pdata/$myUid/priv').set(v ? true : null);
          } catch (e) {
            err(e);
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.sticky_note_2_outlined),
        title: const Text('ملاحظتي'),
        subtitle: note.isEmpty ? null : Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMu, fontSize: 12)),
        onTap: _editNote,
      ),
    ]);
  }
}
