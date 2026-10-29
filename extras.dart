import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data.dart';
import 'entrancefx.dart';
import 'sfx.dart';
import 'widgets.dart';

final ValueNotifier<int> wallTick = ValueNotifier<int>(0);

Future<File> _wallFile() async => File('${(await getApplicationDocumentsDirectory()).path}/chat_bg.png');

/// خلفية المحادثة التي يحددها العضو
class ChatWallpaper extends StatefulWidget {
  final Widget child;
  const ChatWallpaper({super.key, required this.child});
  @override
  State<ChatWallpaper> createState() => _ChatWallpaperState();
}

class _ChatWallpaperState extends State<ChatWallpaper> {
  File? f;

  @override
  void initState() {
    super.initState();
    wallTick.addListener(_load);
    _load();
  }

  Future<void> _load() async {
    try {
      final x = await _wallFile();
      imageCache.clear();
      if (mounted) setState(() => f = x.existsSync() ? x : null);
    } catch (_) {}
  }

  @override
  void dispose() {
    wallTick.removeListener(_load);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final x = f;
    if (x == null) return widget.child;
    return Stack(fit: StackFit.expand, children: [
      Positioned.fill(child: Image.file(x, fit: BoxFit.cover, gaplessPlayback: true)),
      widget.child,
    ]);
  }
}

class WallpaperEditor extends StatefulWidget {
  const WallpaperEditor({super.key});
  @override
  State<WallpaperEditor> createState() => _WallpaperEditorState();
}

class _WallpaperEditorState extends State<WallpaperEditor> {
  final key = GlobalKey();
  Uint8List? bytes;
  double dim = .35;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (x == null) return;
    final b = await x.readAsBytes();
    if (mounted) setState(() => bytes = b);
  }

  Future<void> _save() async {
    try {
      final bd = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final im = await bd.toImage(pixelRatio: 2);
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      final f = await _wallFile();
      await f.writeAsBytes(d!.buffer.asUint8List());
      wallTick.value++;
      toast('تم تعيين الخلفية ✅');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      toast('تعذر الحفظ', bad: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خلفية المحادثة')),
      body: Column(children: [
        Expanded(
          child: Center(
            child: bytes == null
                ? const Text('اختر صورة ثم حرّكها وكبّرها بإصبعيك', style: TextStyle(color: kMu))
                : AspectRatio(
                    aspectRatio: 9 / 16,
                    child: RepaintBoundary(
                      key: key,
                      child: Stack(fit: StackFit.expand, children: [
                        ClipRect(child: InteractiveViewer(minScale: 1, maxScale: 5, child: Image.memory(bytes!, fit: BoxFit.cover))),
                        IgnorePointer(child: Container(color: Color.fromRGBO(0, 0, 0, dim))),
                      ]),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(children: [
            const Text('التعتيم'),
            Expanded(child: Slider(value: dim, min: 0, max: .85, onChanged: (v) => setState(() => dim = v))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(children: [
            Expanded(child: AppButton('اختيار صورة', kind: 'g', onPressed: _pick)),
            const SizedBox(width: 10),
            Expanded(child: AppButton('حفظ وتعيين', onPressed: bytes == null ? null : _save)),
          ]),
        ),
      ]),
    );
  }
}

/// إعدادات إضافية: مستوى الموسيقى، خلفية المحادثة، مؤثر الدخول
class ExtraSettingsTiles extends StatefulWidget {
  const ExtraSettingsTiles({super.key});
  @override
  State<ExtraSettingsTiles> createState() => _ExtraState();
}

class _ExtraState extends State<ExtraSettingsTiles> {
  double vol = Sfx.bgVolPct.toDouble();
  int fx = 0;

  @override
  void initState() {
    super.initState();
    if (Session.isDev) _loadFx();
  }

  Future<void> _loadFx() async {
    try {
      final v = (await ref('pdata/$myUid/fx').get()).value;
      if (mounted) setState(() => fx = v is num ? v.toInt() : 0);
    } catch (_) {}
  }

  Future<void> _setFx(int k) async {
    try {
      await ref('pdata/$myUid/fx').set(k == 0 ? null : k);
      if (mounted) setState(() => fx = k);
      toast(k == 0 ? 'تم إلغاء المؤثر' : 'تم تعيين المؤثر ✅');
    } catch (e) {
      err(e);
    }
  }

  void _pickFx() {
    showAppSheet<void>(context, (sc) => [
          const Text('مؤثر دخول ملفك التعريفي', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const Text('يظهر لكل من يزور ملفك. الثلاثة الأولى ذكورية والاثنان الأخيران أنثويان.', style: TextStyle(color: kMu, fontSize: 12, height: 1.6)),
          for (var k = 1; k <= 5; k++)
            ListTile(
              leading: Icon(fx == k ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(kFxNames[k]),
              trailing: IconButton(
                icon: const Icon(Icons.play_circle_outline),
                onPressed: () => Navigator.of(context).push(PageRouteBuilder<void>(opaque: true, pageBuilder: (_, __, ___) => FxScreen(kind: k, name: Session.me.name))),
              ),
              onTap: () {
                Navigator.of(sc).pop();
                _setFx(k);
              },
            ),
          AppButton('بدون مؤثر', kind: 'g', onPressed: () {
            Navigator.of(sc).pop();
            _setFx(0);
          }),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ListTile(
        leading: const Icon(Icons.volume_up_outlined),
        title: const Text('مستوى موسيقى الخلفية'),
        subtitle: Slider(
          value: vol,
          min: 0,
          max: 100,
          divisions: 20,
          label: '${vol.round()}%',
          onChanged: (v) {
            setState(() => vol = v);
            Sfx.setBgVol(v.round());
          },
        ),
      ),
      ListTile(
        leading: const Icon(Icons.wallpaper_outlined),
        title: const Text('خلفية المحادثة'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WallpaperEditor())),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            try {
              final f = await _wallFile();
              if (f.existsSync()) await f.delete();
              wallTick.value++;
              toast('تمت إزالة الخلفية');
            } catch (_) {}
          },
        ),
      ),
      if (Session.isDev)
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome),
          value: Session.isEmp ? fx == 9 : fx > 0,
          title: Text(Session.isEmp ? 'تسجيل دخول الإمبراطور' : 'مؤثر دخول الملف التعريفي'),
          subtitle: Session.isEmp ? const Text('يظهر لكل من يزور ملفك', style: TextStyle(color: kMu, fontSize: 12)) : Text(fx > 0 ? kFxNames[fx] : 'اختر من 5 مؤثرات', style: const TextStyle(color: kMu, fontSize: 12)),
          onChanged: (v) => Session.isEmp ? _setFx(v ? 9 : 0) : _pickFx(),
        ),
      if (Session.isEmp)
        ListTile(leading: const Icon(Icons.play_circle_outline), title: const Text('معاينة دخول الإمبراطور'), onTap: () => Navigator.of(context).push(PageRouteBuilder<void>(opaque: true, pageBuilder: (_, __, ___) => FxScreen(kind: 9, name: Session.me.name)))),
    ]);
  }
}
