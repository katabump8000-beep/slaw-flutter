import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'app_state.dart';
import 'data.dart';
import 'sfx.dart';
import 'widgets.dart';

Future<bool> hasMedia(String key) async {
  try {
    return (await ref('media/$key/ts').get()).exists;
  } catch (_) {
    return false;
  }
}

/// يرجع ملف الفيديو من الكاش فوراً إن كان محمّلاً مسبقاً (باسم يتضمن وقت الرفع) وإلا ينزّله مرة واحدة
Future<File?> mediaFile(String key, {String base = 'media'}) async {
  try {
    final ts = (await ref('$base/$key/ts').get()).value?.toString() ?? '';
    if (ts.isEmpty) return null;
    final dir = (await getTemporaryDirectory()).path;
    final f = File('$dir/media_${key}_$ts.mp4');
    if (await f.exists() && await f.length() > 1000) return f;
    final d = (await ref('$base/$key/d').get()).value?.toString() ?? '';
    final i = d.indexOf(',');
    if (i < 0) return null;
    await f.writeAsBytes(base64Decode(d.substring(i + 1)));
    // تنظيف النسخ القديمة
    try {
      for (final e in Directory(dir).listSync()) {
        final n = e.path.split('/').last;
        if (e is File && n.startsWith('media_${key}_') && e.path != f.path) e.deleteSync();
      }
    } catch (_) {}
    return f;
  } catch (_) {
    return null;
  }
}

/// تحميل مسبق في الخلفية حتى تفتح الحالة بلحظة
Future<void> prefetchMedia(String key) async {
  await mediaFile(key);
}

/// تشغيل فيديو (التعليمات أو حالة الإمبراطور)
class VideoScreen extends StatefulWidget {
  final String keyName;
  final String title;
  final String base;
  const VideoScreen({super.key, required this.keyName, required this.title, this.base = 'media'});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? c;
  String err0 = '';

  @override
  void initState() {
    super.initState();
    Sfx.block('video');
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await mediaFile(widget.keyName, base: widget.base);
      if (f == null) throw 'none';
      final vc = VideoPlayerController.file(f);
      await vc.initialize();
      await vc.play();
      if (!mounted) {
        await vc.dispose();
        return;
      }
      setState(() => c = vc);
    } catch (_) {
      if (mounted) setState(() => err0 = 'الفيديو غير متوفر (قد يكون حُذف)');
    }
  }

  @override
  void dispose() {
    c?.dispose();
    Sfx.unblock('video');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.title)),
      body: Center(
        child: err0.isNotEmpty
            ? Text(err0)
            : v == null
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: () => setState(() => v.value.isPlaying ? v.pause() : v.play()),
                    child: AspectRatio(aspectRatio: v.value.aspectRatio, child: Stack(alignment: Alignment.bottomCenter, children: [VideoPlayer(v), VideoProgressIndicator(v, allowScrubbing: true)])),
                  ),
      ),
    );
  }
}

/// رفع فيديو (للإمبراطور): ≤ 5 ميجابايت لأنه يُخزَّن داخل قاعدة البيانات
Future<void> uploadVideo(String key) async {
  try {
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    final b = await x.readAsBytes();
    if (b.length > 5000000) {
      toast('الفيديو كبير (${(b.length / 1048576).toStringAsFixed(1)} ميجابايت). الحد 5 ميجابايت — اختر مقطعاً أقصر', bad: true);
      return;
    }
    await ref('media/$key').set(<String, Object?>{'d': 'data:video/mp4;base64,${base64Encode(b)}', 'ts': ServerValue.timestamp});
    toast('تم الرفع ✅');
  } catch (e) {
    err(e);
  }
}

/// موسيقى الخلفية (للإمبراطور): ≤ 3.3 ميجابايت، تُشغَّل بمستوى 15%
Future<void> uploadBgm() async {
  try {
    final f = await FilePicker.pickFile(type: FileType.audio);
    if (f == null) return;
    final b = await f.readAsBytes();
    if (b.length > 3300000) {
      toast('الملف كبير. الحد 3.3 ميجابايت', bad: true);
      return;
    }
    final v = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await ref('bgmData/$v').set('data:audio/mpeg;base64,${base64Encode(b)}');
    await ref('bgmMeta').set(<String, Object?>{'v': v, 'n': f.name.length > 60 ? f.name.substring(0, 60) : f.name});
    toast('تم تعيين موسيقى الخلفية ✅');
    await Sfx.syncBgm();
  } catch (e) {
    err(e);
  }
}

/// زر التعليمات: رسمة (كتاب مفتوح مع علامة تشغيل) والنص «تعليمات» تحتها
class GuideButton extends StatelessWidget {
  const GuideButton({super.key});

  Future<void> _open(BuildContext context) async {
    try {
      if (FirebaseAuth.instance.currentUser == null) await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {}
    if (!await hasMedia('guide')) {
      toast('لا يوجد فيديو تعليمات بعد');
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VideoScreen(keyName: 'guide', title: 'التعليمات')));
  }

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: () => _open(context),
      radius: 26,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CustomPaint(size: const Size(26, 22), painter: _GuidePainter(context.accent2)),
          const SizedBox(height: 2),
          const Text('تعليمات', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, height: 1.1)),
        ]),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  final Color c;
  _GuidePainter(this.c);

  @override
  void paint(Canvas cv, Size s) {
    final w = s.width, h = s.height;
    final line = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    // كتاب مفتوح
    final book = Path()
      ..moveTo(w * .5, h * .22)
      ..quadraticBezierTo(w * .25, h * .02, 0, h * .12)
      ..lineTo(0, h * .88)
      ..quadraticBezierTo(w * .25, h * .78, w * .5, h * .98)
      ..quadraticBezierTo(w * .75, h * .78, w, h * .88)
      ..lineTo(w, h * .12)
      ..quadraticBezierTo(w * .75, h * .02, w * .5, h * .22)
      ..close();
    cv.drawPath(book, line);
    cv.drawLine(Offset(w * .5, h * .22), Offset(w * .5, h * .98), line);
    // علامة تشغيل
    final play = Path()
      ..moveTo(w * .66, h * .38)
      ..lineTo(w * .66, h * .7)
      ..lineTo(w * .88, h * .54)
      ..close();
    cv.drawPath(play, Paint()..color = c);
    // أسطر نص
    final tx = Paint()
      ..color = c.withAlpha(150)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    cv.drawLine(Offset(w * .12, h * .38), Offset(w * .38, h * .38), tx);
    cv.drawLine(Offset(w * .12, h * .54), Offset(w * .38, h * .54), tx);
    cv.drawLine(Offset(w * .12, h * .7), Offset(w * .32, h * .7), tx);
  }

  @override
  bool shouldRepaint(covariant _GuidePainter o) => o.c != c;
}
