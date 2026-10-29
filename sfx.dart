import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'data.dart';

/// المؤثرات الصوتية وموسيقى الخلفية
class Sfx {
  static final AudioPlayer _fx = AudioPlayer();
  static final AudioPlayer _bg = AudioPlayer();
  static final Set<String> _block = <String>{};
  static String? _bgFile;
  static bool _bgStarted = false;

  static bool get bgDisabled => prefs.getBool('bgm_off') ?? false;
  static bool get fxOff => prefs.getBool('fx_off') ?? false;
  static const Set<String> _always = {'emp_in.wav', 'dev_in.wav'};
  static final AudioPlayer _ck = AudioPlayer();
  static int _lastCk = 0;

  /// نوع نغمة الضغط: 0 = الأصلية، 1..5 = الأنواع الجديدة
  static int get clickType => (prefs.getInt('ck_t') ?? 0).clamp(0, 5);
  static String _clickFile(int t) => t <= 0 ? 'click.mp3' : 'click$t.wav';

  /// صوت النقر
  static void click() {
    if (fxOff) return;
    final n = DateTime.now().millisecondsSinceEpoch;
    if (n - _lastCk < 120) return;
    _lastCk = n;
    _ck.stop().then((_) => _ck.setVolume(.5)).then((_) => _ck.play(AssetSource('audio/${_clickFile(clickType)}'))).catchError((_) {});
  }

  /// تجربة نغمة ضغط معيّنة
  static void previewClick(int t) {
    _ck.stop().then((_) => _ck.setVolume(.6)).then((_) => _ck.play(AssetSource('audio/${_clickFile(t)}'))).catchError((_) {});
  }

  static final AudioPlayer _er = AudioPlayer();
  static int _lastEr = 0;

  /// صوت الخطأ (كلمة سر خاطئة، رصيد غير كاف، أي خطأ)
  static void error() {
    if (fxOff) return;
    final n = DateTime.now().millisecondsSinceEpoch;
    if (n - _lastEr < 500) return;
    _lastEr = n;
    _er.stop().then((_) => _er.setVolume(.8)).then((_) => _er.play(AssetSource('audio/error.wav'))).catchError((_) {});
  }

  static int _fxN = 0;
  static void _fxBegin() {
    _fxN++;
    block('fx');
  }

  static void _fxEnd() {
    if (_fxN > 0) _fxN--;
    if (_fxN == 0) unblock('fx');
  }

  /// تشغيل مؤثر وانتظار نهايته
  static Future<void> playWait(String name, {double volume = 1}) async {
    if (fxOff && !_always.contains(name)) return;
    _fxBegin();
    final c = Completer<void>();
    final sub = _fx.onPlayerComplete.listen((_) {
      if (!c.isCompleted) c.complete();
    });
    try {
      await _fx.stop();
      await _fx.setVolume(volume);
      await _fx.play(AssetSource('audio/$name'));
      await c.future.timeout(const Duration(seconds: 40));
    } catch (_) {}
    await sub.cancel();
    _fxEnd();
  }

  static Future<void> chain(List<String> names) async {
    _fxBegin();
    try {
      for (final n in names) {
        await playWait(n);
      }
    } finally {
      _fxEnd();
    }
  }

  /// مشغل مستقل (للعروض الطويلة)
  static Future<AudioPlayer> start(String name, {double volume = 1}) async {
    final p = AudioPlayer();
    if (fxOff && !_always.contains(name)) return p;
    try {
      await p.setVolume(volume);
      await p.play(AssetSource('audio/$name'));
    } catch (_) {}
    return p;
  }

  // ---------- موسيقى الخلفية ----------
  static Future<void> syncBgm() async {
    try {
      final m = await ref('bgmMeta').get();
      final v = m.value;
      if (v is! Map) return;
      final ver = (v['v'] as num).toInt();
      final dir = (await getTemporaryDirectory()).path;
      final f = File('$dir/bgm_$ver.bin');
      if (!await f.exists()) {
        final d = await ref('bgmData/$ver').get();
        final s = d.value?.toString() ?? '';
        final i = s.indexOf(',');
        if (i < 0) return;
        await f.writeAsBytes(base64Decode(s.substring(i + 1)));
      }
      _bgFile = f.path;
      await _bg.setReleaseMode(ReleaseMode.loop);
      if (_block.isEmpty && !bgDisabled) await _play();
    } catch (_) {}
  }

  static Future<void> _play() async {
    final f = _bgFile;
    if (f == null) return;
    try {
      if (_bgStarted) {
        await _bg.resume();
      } else {
        await _bg.play(DeviceFileSource(f), volume: .15);
        _bgStarted = true;
      }
      if (_block.isNotEmpty) {
        await _bg.setVolume(0);
        await _bg.pause();
      }
    } catch (_) {}
  }

  /// إيقاف مؤقت للموسيقى لسبب معين (صوت/صورة/عرض/مغادرة التطبيق)
  static int _showN = 0;

  static void block(String reason) {
    if (reason == 'show') {
      _showN++;
      if (_showN > 1) return;
    }
    if (_block.add(reason)) {
      _bg.setVolume(0).catchError((_) {});
      _bg.pause().catchError((_) {});
    }
  }

  static void unblock(String reason) {
    if (reason == 'show') {
      if (_showN > 0) _showN--;
      if (_showN > 0) return;
    }
    if (_block.remove(reason) && _block.isEmpty && !bgDisabled) {
      _bg.setVolume(.15).catchError((_) {});
      _play();
    }
  }

  static Future<void> setBgmEnabled(bool on) async {
    prefs.setBool('bgm_off', !on);
    if (!on) {
      await _bg.pause();
    } else if (_block.isEmpty) {
      await _play();
    }
  }
}
