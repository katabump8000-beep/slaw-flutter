import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'app_state.dart';
import 'data.dart';
import 'firebase_options.dart';

final FlutterLocalNotificationsPlugin _ln = FlutterLocalNotificationsPlugin();
bool _lnReady = false;

Future<void> initLocalNotifs({bool ask = false}) async {
  try {
    if (!_lnReady) {
      const init = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
      await _ln.initialize(init);
      _lnReady = true;
    }
    if (ask) {
      final a = _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await a?.requestNotificationsPermission();
    }
  } catch (_) {}
}

Future<void> showLocal(int id, String title, String body) async {
  try {
    await initLocalNotifs();
    const d = NotificationDetails(
      android: AndroidNotificationDetails('fir_main', 'إشعارات FIR', importance: Importance.high, priority: Priority.high),
    );
    await _ln.show(id, title, body, d);
  } catch (_) {}
}

bool appInBackground() {
  final s = WidgetsBinding.instance.lifecycleState;
  return s != null && s != AppLifecycleState.resumed;
}

/// مهمة الخلفية: تفحص الإشعارات وإعلانات الحرب كل ~15 دقيقة عندما يكون التطبيق مغلقاً
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await prefs.init();
      await Firebase.initializeApp(options: firebaseOptions);
      final auth = FirebaseAuth.instance;
      final u = auth.currentUser ?? await auth.authStateChanges().first.timeout(const Duration(seconds: 8));
      if (u == null || u.isAnonymous) return true;
      if (prefs.getBool('mute') ?? false) return true;
      var seen = prefs.getInt('bg_seen') ?? 0;
      var mx = seen;
      final s = await ref('notifs/${u.uid}').get();
      final v = s.value;
      if (v is Map) {
        var id = 100;
        v.forEach((k, x) {
          if (x is! Map) return;
          final ts = x['ts'] is num ? (x['ts'] as num).toInt() : 0;
          if (ts <= seen) return;
          if (ts > mx) mx = ts;
          final t = (x['t'] ?? '').toString();
          final tx = (x['tx'] ?? '').toString();
          final title = t == 'men' ? 'هناك من ذكر اسمك' : (t == 'sup' ? 'رسالة ابلاغ من احد الاعضاء' : 'FIR');
          showLocal(id++, title, tx.isNotEmpty ? tx : 'لديك إشعار جديد');
        });
      }
      prefs.setInt('bg_seen', mx);
      final wf = await ref('warFeed').orderByKey().limitToLast(3).get();
      final w = wf.value;
      var seenW = prefs.getInt('bg_war') ?? 0;
      var mw = seenW;
      if (w is Map) {
        w.forEach((k, x) {
          if (x is! Map) return;
          final ts = x['ts'] is num ? (x['ts'] as num).toInt() : 0;
          if (ts <= seenW) return;
          if (ts > mw) mw = ts;
          showLocal(900 + (ts % 50), '⚔️ إعلان حرب', 'نقابة ${x['an']} تعلن الحرب على نقابة ${x['dn']}');
        });
      }
      prefs.setInt('bg_war', mw);
    } catch (_) {}
    return true;
  });
}

Future<void> startBackgroundPolling() async {
  try {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask('fir_poll', 'fir_poll', frequency: const Duration(minutes: 15));
  } catch (_) {}
}
