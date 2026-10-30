import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
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
  static bool _isAlways(String n) => _always.contains(n) || n.startsWith('fx') || n.startsWith('kool');
  static int get bgVolPct => prefs.getInt('bgm_vol') ?? 15;

  /// يمنع النقر وغيره من إيقاف الموسيقى (لا يطلب تركيز الصوت من النظام)
  static Future<void> init() async {
    WidgetsBinding.instance.addObserver(_LifeObs());
    try {
      await AudioPlayer.global.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
    } catch (_) {}
    try {
      await _ck.setPlayerMode(PlayerMode.lowLatency);
    } catch (_) {}
  }

  static Future<void> setBgVol(int pct) async {
    prefs.setInt('bgm_vol', pct);
    try {
      await _bg.setVolume(pct / 100);
    } catch (_) {}
  }
  static final AudioPlayer _ck = AudioPlayer();
  static int _lastCk = 0;

  /// صوت النقر
  static void click() {
    if (fxOff || _block.isNotEmpty) return;
    final n = DateTime.now().millisecondsSinceEpoch;
    if (n - _lastCk < 120) return;
    _lastCk = n;
    _ck.stop().then((_) => _ck.setVolume(.5)).then((_) => _ck.play(AssetSource('audio/click.mp3'))).catchError((_) {});
  }

  /// تشغيل مؤثر وانتظار نهايته
  static Future<void> playWait(String name, {double volume = 1}) async {
    if (fxOff && !_isAlways(name)) return;
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
    if (fxOff && !_isAlways(name)) return p;
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
        await _bg.play(DeviceFileSource(f), volume: bgVolPct / 100);
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


/// يوقف موسيقى الخلفية فور مغادرة التطبيق ويعيدها عند الرجوع
class _LifeObs with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Sfx.unblock('app');
    } else {
      Sfx.block('app');
    }
  }
}
