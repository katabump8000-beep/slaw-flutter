import 'aichat.dart';
import 'uiprefs.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'auth.dart' show deviceHash;
import 'notif.dart';
import 'bell.dart';
import 'crop.dart';
import 'data.dart';
import 'ai.dart';
import 'emp.dart';
import 'security.dart';
import 'pwchange.dart';
import 'privacy.dart';
import 'extras.dart';
import 'sfx.dart';
import 'support.dart';
import 'tools.dart';
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
      if (!Session.isDev && await imageDataUnsafe(d) == true) {
        toast('هذه الصورة غير لائقة ولن تُقبل', bad: true);
        return;
      }
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
    await dropPushToken();
    Session.reset();
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// للمطورين والإمبراطور فقط: يسمح بإنشاء حساب عضو جديد على هذا الجهاز (للتجربة وكشف الثغرات)
  Future<void> _newAccount() async {
    final ok = await showAppSheet<bool>(context, (sc) => [
          const Text('إنشاء حساب آخر', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Text('سيتم تسجيل خروجك من هذا الحساب وفتح شاشة التسجيل لإنشاء حساب عضو جديد على نفس الجهاز. يمكنك الرجوع لحسابك بكلمة سرك.', style: TextStyle(color: kMu, height: 1.6)),
          AppButton('متابعة', onPressed: () => Navigator.of(sc).pop(true)),
          AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(sc).pop(false)),
        ]);
    if (ok != true) return;
    try {
      final h = await deviceHash();
      await ref('deviceAllow/$h').set(<String, Object?>{'by': myUid, 'ts': ServerValue.timestamp});
    } catch (e) {
      toast('تعذر منح التصريح (حدّث قواعد قاعدة البيانات: deviceAllow)', bad: true);
      return;
    }
    BellService.stop();
    await dropPushToken();
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
            subtitle: const Text('عند الإيقاف تتوقف كل إشعارات البرنامج', style: TextStyle(color: kMu, fontSize: 12)),
            onChanged: (v) async {
              await setAllNotifs(v);
              if (mounted) setState(() {});
              toast(v ? 'تم تفعيل الإشعارات 🔔' : 'تم إيقاف كل الإشعارات 🔕');
            },
          ),
          SwitchListTile(
            value: !Sfx.bgDisabled,
            title: const Text('موسيقى الخلفية'),
            subtitle: const Text('إيقاف أو تشغيل الموسيقى', style: TextStyle(color: kMu, fontSize: 12)),
            onChanged: (v) {
              Sfx.setBgmEnabled(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            value: !Sfx.fxOff,
            title: const Text('أصوات التطبيق'),
            subtitle: const Text('النقر والمؤثرات (ما عدا مؤثرات الدخول الخاصة)', style: TextStyle(color: kMu, fontSize: 12)),
            onChanged: (v) {
              prefs.setBool('fx_off', !v);
              setState(() {});
            },
          ),
          const ProfilePrivacyTiles(),
          const ExtraSettingsTiles(),
          _title('الحساب'),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('درجة الفخر'),
            onTap: () async {
              final p = await prideOf(myUid);
              if (!context.mounted) return;
              showAppSheet<void>(context, (sc) => [
                    Center(child: Stack(alignment: Alignment.center, children: [Icon(Icons.shield, size: 130, color: p >= 70 ? const Color(0xFF2EA84F) : (p >= 40 ? const Color(0xFFE0A100) : kRed)), Text('$p%', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white))])),
                    const Center(child: Text('ملفك نظيف يعني 100%. كل حظر أو سبام ينقص درجتك.', textAlign: TextAlign.center, style: TextStyle(color: kMu, height: 1.8))),
                  ]);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('تأمين الحساب'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SecurityScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.text_fields_rounded),
            title: const Text('مقاس الخط'),
            subtitle: const Text('12 مقاساً للنص في كل التطبيق', style: TextStyle(color: kMu, fontSize: 12)),
            onTap: () => showFontSheet(context),
          ),
          StatefulBuilder(
            builder: (c, set) => SwitchListTile(
              secondary: const Icon(Icons.schedule_rounded),
              title: const Text('نظام 24 ساعة'),
              subtitle: const Text('الافتراضي 12 ساعة (ص / م)', style: TextStyle(color: kMu, fontSize: 12)),
              value: prefs.getBool('h24') ?? false,
              onChanged: (v) {
                prefs.setBool('h24', v);
                set(() {});
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key_rounded),
            title: const Text('تغيير كلمة السر'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen())),
          ),
          const SupportTile(),
          if (Session.isDev)
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('AI'),
              subtitle: const Text('مساعد الإدارة', style: TextStyle(color: kMu, fontSize: 12)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AiChatScreen(staff: true))),
            ),
          if (Session.isEmp)
            ListTile(
              leading: const Icon(Icons.power_settings_new_rounded),
              title: const Text('حالة Ai'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AiStatusScreen())),
            ),
          if (Session.isDev)
            ListTile(
              leading: const Icon(Icons.build_circle_outlined),
              title: Text(Session.isEmp ? 'أدوات الإمبراطور' : 'أدوات المطورين'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ToolsScreen())),
            ),
          if (Session.isEmp) ...[
            _title('الإمبراطور'),
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('إدارة المستخدمين'),
              subtitle: const Text('بحث بالـID وتعيين المطورين', style: TextStyle(color: kMu, fontSize: 12)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmpScreen())),
            ),
          ],
          const SizedBox(height: 16),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: AppButton('تسجيل الخروج', kind: 'r', onPressed: _logout)),
          if (Session.isDev)
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: AppButton('إنشاء حساب آخر', kind: 'g', onPressed: _newAccount)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
