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

  /// تشغيل مؤثر وانتظار نهايته
  static Future<void> playWait(String name, {double volume = 1}) async {
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
  }

  static Future<void> chain(List<String> names) async {
    for (final n in names) {
      await playWait(n);
    }
  }

  /// مشغل مستقل (للعروض الطويلة)
  static Future<AudioPlayer> start(String name, {double volume = 1}) async {
    final p = AudioPlayer();
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
    } catch (_) {}
  }

  /// إيقاف مؤقت للموسيقى لسبب معين (صوت/صورة/عرض/مغادرة التطبيق)
  static void block(String reason) {
    if (_block.add(reason)) {
      _bg.pause();
    }
  }

  static void unblock(String reason) {
    if (_block.remove(reason) && _block.isEmpty && !bgDisabled) _play();
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
