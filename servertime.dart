import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

/// ساعة الخادم: كل الوقت في التطبيق يمر من هنا بدل ساعة الجهاز.
/// تعتمد على Firebase (.info/serverTimeOffset) + Stopwatch (ساعة داخلية لا تتأثر بتغيير وقت الجهاز).
class ServerClock {
  static final Stopwatch _sw = Stopwatch()..start();
  static int _anchorServer = DateTime.now().millisecondsSinceEpoch;
  static int _anchorSw = 0;
  static bool synced = false;
  static StreamSubscription<DatabaseEvent>? _sub;
  static Completer<void>? _first;

  static int now() => _anchorServer + (_sw.elapsedMilliseconds - _anchorSw);

  /// يُستدعى مرة واحدة بعد Firebase.initializeApp. ينتظر أول مزامنة (حد أقصى 5 ثوانٍ).
  static Future<void> init() async {
    if (_sub != null) return;
    _first = Completer<void>();
    _sub = FirebaseDatabase.instance.ref('.info/serverTimeOffset').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is num) {
        _anchorServer = DateTime.now().millisecondsSinceEpoch + v.toInt();
        _anchorSw = _sw.elapsedMilliseconds;
        synced = true;
        if (_first != null && !_first!.isCompleted) _first!.complete();
      }
    }, onError: (_) {});
    try {
      await _first!.future.timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

/// الوقت الحالي بالميلي ثانية حسب الخادم
int nowMs() => ServerClock.now();

/// الوقت الحالي (محلي) محسوب من وقت الخادم
DateTime nowDt() => DateTime.fromMillisecondsSinceEpoch(nowMs());
