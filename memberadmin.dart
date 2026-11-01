import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

/// حظر العضو أو حذفه نهائياً بواسطة الـID (للمطورين والإمبراطور)
class MemberAdminScreen extends StatefulWidget {
  const MemberAdminScreen({super.key});

  @override
  State<MemberAdminScreen> createState() => _MemberAdminState();
}

class _MemberAdminState extends State<MemberAdminScreen> {
  final TextEditingController id = TextEditingController();
  String uid = '';
  Prof? p;
  bool banned = false;
  bool busy = false;
  String msg = '';

  @override
  void dispose() {
    id.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final t = normDigits(id.text.trim());
    if (t.isEmpty) {
      setState(() => msg = 'اكتب الـID أولاً');
      return;
    }
    setState(() {
      busy = true;
      msg = '';
      uid = '';
      p = null;
    });
    try {
      final s = await ref('pids/$t').get();
      if (!s.exists) {
        if (mounted) {
          setState(() {
            msg = 'لا يوجد عضو بهذا الـID';
            busy = false;
          });
        }
        return;
      }
      final u = s.value.toString();
      final pr = await prof(u);
      final b = (await ref('banned/$u').get()).exists;
      if (mounted) {
        setState(() {
          uid = u;
          p = pr;
          banned = b;
          busy = false;
        });
      }
    } catch (e) {
      err(e);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _allowed() async {
    if (uid.isEmpty) return false;
    if (uid == myUid) {
      toast('لا يمكنك تنفيذ هذا على نفسك', bad: true);
      return false;
    }
    if (uid == Session.emp) {
      toast('لا يمكن التصرف مع الإمبراطور', bad: true);
      return false;
    }
    final r = await roleOf(uid);
    if (r != null && !Session.isEmp) {
      toast('لا يمكنك التصرف مع مطوّر', bad: true);
      return false;
    }
    return true;
  }

  Future<void> _ban(bool on) async {
    if (!await _allowed()) return;
    try {
      if (on) {
        await ref('banned/$uid').set(true);
      } else {
        await ref('banned/$uid').remove();
      }
      if (mounted) setState(() => banned = on);
      toast(on ? 'تم حظر ${p?.name ?? ''} ⛔' : 'تم رفع الحظر ✅');
    } catch (e) {
      err(e);
    }
  }

  Future<void> _delete() async {
    if (!await _allowed()) return;
    if (!mounted) return;
    final ok = await showAppSheet<bool>(context, (sc) => [
          Text('حذف «${p?.name ?? ''}» نهائياً؟', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const Text('يُحذف الحساب وكل بياناته من التطبيق ولا يبقى له أثر، ولا يمكن التراجع.', textAlign: TextAlign.center, style: TextStyle(color: kMu, height: 1.7, fontSize: 13)),
          AppButton('نعم، احذف نهائياً', kind: 'r', onPressed: () => Navigator.of(sc).pop(true)),
          AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(sc).pop(false)),
        ]);
    if (ok != true) return;
    try {
      // يُحظر فوراً ثم تتولى دالة السيرفر مسح الحساب وكل بياناته
      try {
        await ref('banned/$uid').set(true);
      } catch (_) {}
      await ref('delQueue/$uid').set(<String, Object?>{'by': myUid, 'ts': ServerValue.timestamp});
      toast('تم إرسال الحذف ✅');
      if (mounted) {
        setState(() {
          uid = '';
          p = null;
          id.clear();
        });
      }
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حظر / حذف عضو')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: id,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'اكتب ID العضو (9 أرقام)'),
          onSubmitted: (_) => _find(),
        ),
        const SizedBox(height: 10),
        AppButton(busy ? '...' : 'بحث', onPressed: busy ? null : _find),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(msg, style: const TextStyle(color: kRed))),
        if (p != null) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .28), borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(p!.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(banned ? '⛔ محظور حالياً' : 'الحساب نشط', textAlign: TextAlign.center, style: TextStyle(color: banned ? kRed : kMu)),
              const SizedBox(height: 12),
              if (banned) AppButton('رفع الحظر', onPressed: () => _ban(false)) else AppButton('⛔ حظر العضو', kind: 'r', onPressed: () => _ban(true)),
              const SizedBox(height: 8),
              AppButton('🗑 حذف العضو نهائياً', kind: 'r', onPressed: _delete),
            ]),
          ),
        ],
      ]),
    );
  }
}
