import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'crop.dart';
import 'data.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController noteCtrl = TextEditingController();
  bool isPub = true;
  String pid = Session.pid;
  String bubble = Session.me.color;
  bool mute = prefs.getBool('mute') ?? false;

  @override
  void initState() {
    super.initState();
    ref('pdata/$myUid/note').get().then((s) {
      if (mounted) setState(() => noteCtrl.text = s.value?.toString() ?? '');
    }).catchError((_) {});
    ref('ppub/$myUid').get().then((s) {
      if (mounted) setState(() => isPub = s.value != false);
    }).catchError((_) {});
    Session.ensurePid().then((_) {
      if (mounted) setState(() => pid = Session.pid);
    });
  }

  @override
  void dispose() {
    noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePhoto() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      final d = await cropImage(
        context,
        bytes,
        out: const [128, 100, 80],
        limit: 29000,
        title: 'قص الصورة 1:1',
      );
      if (d == null) return;
      await ref('avatars/$myUid').set(d);
      setAvCache(myUid, d);
      avatarTick.value++;
      toast('تم حفظ الصورة', accent: true);
    } catch (e) {
      err(e);
    }
  }

  Future<void> _saveNote() async {
    final t = noteCtrl.text.trim();
    try {
      await ref('pdata/$myUid/note').set(t.isEmpty ? null : t);
      toast('تم حفظ الملاحظة', accent: true);
    } catch (e) {
      err(e);
    }
  }

  Future<void> _setPub(bool v) async {
    try {
      await ref('ppub/$myUid').set(v);
      if (mounted) setState(() => isPub = v);
    } catch (e) {
      err(e);
    }
  }

  Future<void> _setBubble(String c) async {
    try {
      await ref('profiles/$myUid/color').set(c);
      final m = Session.me;
      Session.me = Prof(m.name, c, m.gender, m.ts);
      setProfCache(myUid, Session.me);
      if (mounted) setState(() => bubble = c);
      toast('تم تغيير اللون', accent: true);
    } catch (e) {
      err(e);
    }
  }

  void _setAccent(String c) {
    prefs.setString('ac', c);
    accentHex.value = c;
    toast('تم تغيير لون الواجهة', accent: true);
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: active ? context.accent : const Color.fromRGBO(0, 0, 0, .28),
          border: Border.all(color: active ? context.accent : kLine),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF1A0A00) : kTx,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _colors(List<String> list, String current, void Function(String) onPick) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in list)
          GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hexColor(c),
                border: Border.all(
                  color: c.toLowerCase() == current.toLowerCase() ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          Sec(
            align: CrossAxisAlignment.center,
            children: [
              UserAvatar(myUid, size: 88, ring: true, onTap: _changePhoto),
              const SizedBox(height: 10),
              AppButton('تغيير الصورة', icon: Icons.photo_camera, glow: true, compact: true, onPressed: _changePhoto),
              const SizedBox(height: 8),
              Text(Session.me.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(0, 0, 0, .35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.accent2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('ID', style: TextStyle(color: kMu, fontSize: 12)),
                    const SizedBox(width: 10),
                    Text(
                      pid.isEmpty ? '—' : pid,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 4),
                    ),
                    if (pid.isNotEmpty)
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: pid));
                          toast('تم النسخ');
                        },
                        child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.copy, size: 16)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Sec(
            title: 'ملاحظة تظهر في ملفك التعريفي',
            children: [
              TextField(
                controller: noteCtrl,
                maxLength: 40,
                decoration: const InputDecoration(hintText: 'اكتب ملاحظة قصيرة...', counterText: ''),
              ),
              const SizedBox(height: 8),
              AppButton('حفظ الملاحظة', kind: 'g', compact: true, onPressed: _saveNote),
            ],
          ),
          Sec(
            title: 'خصوصية الملف التعريفي',
            children: [
              Row(
                children: [
                  Expanded(child: _chip('عام', isPub, () => _setPub(true))),
                  const SizedBox(width: 10),
                  Expanded(child: _chip('خاص', !isPub, () => _setPub(false))),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isPub ? 'يستطيع أي عضو رؤية ملفك التعريفي' : 'ملفك التعريفي مخفي عن الأعضاء',
                style: TextStyle(color: context.accent2, fontSize: 13),
              ),
            ],
          ),
          Sec(
            title: 'الصوت',
            children: [
              Row(
                children: [
                  const Expanded(child: Text('كتم أصوات التطبيق')),
                  Switch(
                    value: mute,
                    onChanged: (v) {
                      prefs.setBool('mute', v);
                      setState(() => mute = v);
                    },
                  ),
                ],
              ),
            ],
          ),
          Sec(
            title: 'لون الواجهة',
            children: [_colors(kAccents, accentHex.value, _setAccent)],
          ),
          Sec(
            title: 'لون فقاعات رسائلك',
            children: [_colors(kBubbleColors, bubble, _setBubble)],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: AppButton(
              'تسجيل خروج',
              kind: 'r',
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ),
        ],
      ),
    );
  }
}
