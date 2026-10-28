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

/// تشغيل فيديو (التعليمات أو حالة الإمبراطور)
class VideoScreen extends StatefulWidget {
  final String keyName;
  final String title;
  const VideoScreen({super.key, required this.keyName, required this.title});

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
      final s = await ref('media/${widget.keyName}/d').get();
      final d = s.value?.toString() ?? '';
      final i = d.indexOf(',');
      if (i < 0) throw 'none';
      final dir = (await getTemporaryDirectory()).path;
      final f = File('$dir/media_${widget.keyName}.mp4');
      await f.writeAsBytes(base64Decode(d.substring(i + 1)));
      final vc = VideoPlayerController.file(f);
      await vc.initialize();
      await vc.play();
      if (!mounted) {
        await vc.dispose();
        return;
      }
      setState(() => c = vc);
    } catch (_) {
      if (mounted) setState(() => err0 = 'تعذر تشغيل الفيديو');
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

/// زر 🔽 الصغير: فيديو التعليمات الذي يحدده الإمبراطور
class GuideButton extends StatelessWidget {
  const GuideButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'التعليمات',
      icon: const Text('🔽', style: TextStyle(fontSize: 18)),
      onPressed: () async {
        try {
          if (FirebaseAuth.instance.currentUser == null) await FirebaseAuth.instance.signInAnonymously();
        } catch (_) {}
        if (!await hasMedia('guide')) {
          toast('لا يوجد فيديو تعليمات بعد');
          return;
        }
        if (!context.mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VideoScreen(keyName: 'guide', title: 'التعليمات')));
      },
    );
  }
}
