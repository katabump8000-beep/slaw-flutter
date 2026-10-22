import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'bell.dart';
import 'crop.dart';
import 'data.dart';
import 'emp.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _changeAvatar() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null || !mounted) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      final d = await cropImage(context, bytes, out: const [256, 192, 128, 96], limit: 29000, round: true, title: 'قص الصورة الشخصية');
      if (d == null) return;
      await ref('avatars/$myUid').set(d);
      setAvCache(myUid, d);
      avatarTick.value++;
      if (mounted) setState(() {});
      toast('تم تغيير صورتك ✅');
    } catch (e) {
      err(e);
    }
  }

  Future<void> _setBubble(String c) async {
    try {
      await ref('profiles/$myUid/color').set(c);
      Session.me = Prof(Session.me.name, c, Session.me.gender, Session.me.ts);
      setProfCache(myUid, Session.me);
      if (mounted) setState(() {});
    } catch (e) {
      err(e);
    }
  }

  void _setAccent(String c) {
    prefs.setString('accent', c);
    accentHex.value = c;
  }

  Future<void> _logout() async {
    final ok = await showAppSheet<bool>(context, (sc) => [
          const Text('تسجيل الخروج؟', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Text('ستحتاج إلى كلمة السر للدخول مرة أخرى.', style: TextStyle(color: kMu)),
          AppButton('تسجيل الخروج', kind: 'r', onPressed: () => Navigator.of(sc).pop(true)),
          AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(sc).pop(false)),
        ]);
    if (ok != true) return;
    BellService.stop();
    Session.reset();
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(t, style: TextStyle(color: context.accent2, fontWeight: FontWeight.w800, fontSize: 13)),
      );

  Widget _dot(String c, bool on, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hexColor(c),
            border: Border.all(color: on ? Colors.white : Colors.transparent, width: 3),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final muted = BellService.muted;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Center(child: UserAvatar(myUid, size: 96, onTap: _changeAvatar)),
          const SizedBox(height: 8),
          const Center(child: Text('اضغط الصورة لتغييرها', style: TextStyle(color: kMu, fontSize: 12))),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(Session.me.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  if (Session.isEmp) ...[const SizedBox(width: 6), const InfinityMark(size: 22)],
                ],
              ),
            ),
          ),
          if (Session.pid.isNotEmpty)
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: Session.pid));
                  toast('تم نسخ الـID');
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text('ID: ${Session.pid}', style: const TextStyle(letterSpacing: 1.5)),
              ),
            ),
          _title('لون فقاعات رسائلك'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 10, runSpacing: 10, children: kBubbleColors.map((c) => _dot(c, c == Session.me.color, () => _setBubble(c))).toList()),
          ),
          _title('لون واجهة التطبيق'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 10, runSpacing: 10, children: kAccents.map((c) => _dot(c, c == accentHex.value, () => _setAccent(c))).toList()),
          ),
          _title('الإشعارات'),
          SwitchListTile(
            value: !muted,
            title: const Text('تفعيل الإشعارات'),
            onChanged: (v) {
              prefs.setBool('mute', !v);
              setState(() {});
            },
          ),
          if (Session.isEmp) ...[
            _title('الإمبراطور'),
            ListTile(
              leading: const InfinityMark(size: 26),
              title: const Text('إدارة المستخدمين'),
              subtitle: const Text('بحث بالـID وتعيين المطورين', style: TextStyle(color: kMu, fontSize: 12)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmpScreen())),
            ),
          ],
          const SizedBox(height: 16),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: AppButton('تسجيل الخروج', kind: 'r', onPressed: _logout)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
