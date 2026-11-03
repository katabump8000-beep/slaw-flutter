import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
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

const AndroidNotificationChannel _chan = AndroidNotificationChannel(
  'fir_main',
  'إشعارات FIR',
  description: 'رسائل، منشن، صداقة، حروب',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);

int _badgeN = 0;

Future<void> showLocal(int id, String title, String body, {String? tag, int? number}) async {
  try {
    await initLocalNotifs();
    _badgeN++;
    final d = NotificationDetails(
      android: AndroidNotificationDetails(
        'fir_main',
        'إشعارات FIR',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        number: number ?? _badgeN,
        ticker: title,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
        enableVibration: true,
        playSound: true,
        fullScreenIntent: false,
        autoCancel: true,
        tag: tag,
      ),
    );
    await _ln.show(id, title, body, d);
  } catch (_) {}
}

/// تصفير العدّاد (عند فتح التطبيق) وإزالة الإشعارات المعلّقة
Future<void> clearBadge() async {
  _badgeN = 0;
  try {
    await _ln.cancelAll();
  } catch (_) {}
  try {
    if (myUid.isNotEmpty) await ref('badge/$myUid').set(0);
  } catch (_) {}
}

String notifTitle(String t) {
  switch (t) {
    case 'men':
      return '📣 هناك من ذكر اسمك';
    case 'all':
      return '📢 نداء للجميع';
    case 'frq':
      return '👥 طلب صداقة جديد';
    case 'fok':
      return '✅ تم قبول صداقتك';
    case 'war':
      return '⚔️ إعلان حرب';
    case 'tr':
      return '💰 وصلك رصيد';
    case 'sup':
      return '🛟 رسالة ابلاغ';
    case 'susp':
      return '⚠️ ايها المطور!';
    case 'guard':
      return '🛡 الحارس';
    default:
      return 'FIR';
  }
}

/// إشعارات الدفع (FCM): تصل فوراً حتى والتطبيق مغلق (تحتاج دالة السحابة في مجلد functions)
@pragma('vm:entry-point')
Future<void> fcmBackground(RemoteMessage m) async {}

Future<void> initPush() async {
  try {
    await initLocalNotifs(ask: true);
    final a = _ln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await a?.createNotificationChannel(_chan);
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onBackgroundMessage(fcmBackground);
    Future<void> save(String? t) async {
      if (t == null || t.isEmpty || myUid.isEmpty) return;
      final k = t.replaceAll(RegExp(r'[.#$\[\]/]'), '_');
      await ref('fcmTokens/$myUid/$k').set(ServerValue.timestamp);
      prefs.setString('fcm_key', k);
    }

    await save(await fm.getToken());
    fm.onTokenRefresh.listen(save);
    // والتطبيق مفتوح: مستمع الجرس يتكفل بالإشعار الفوري، فلا نكرر
    await fm.setForegroundNotificationPresentationOptions(alert: false, badge: false, sound: false);
  } catch (_) {}
}

Future<void> dropPushToken() async {
  try {
    final k = prefs.getString('fcm_key');
    if (k != null && myUid.isNotEmpty) await ref('fcmTokens/$myUid/$k').remove();
    await FirebaseMessaging.instance.deleteToken();
  } catch (_) {}
}

bool appInBackground() {
  final s = WidgetsBinding.instance.lifecycleState;
  return s != null && s != AppLifecycleState.resumed;
}

/// تهيئة Firebase بأمان: لا تفشل إذا كان التطبيق الافتراضي مهيّأً مسبقاً (core/duplicate-app)
Future<void> ensureFirebase() async {
  if (Firebase.apps.isNotEmpty) return;
  try {
    await Firebase.initializeApp(options: firebaseOptions);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
}

/// مهمة الخلفية: تفحص الإشعارات وإعلانات الحرب كل ~15 دقيقة عندما يكون التطبيق مغلقاً
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await prefs.init();
      await ensureFirebase();
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
          final title = notifTitle(t);
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

/// تشغيل/إيقاف كل إشعارات التطبيق: محلياً + في قاعدة البيانات (السيرفر يتجاهل المكتومين) + حذف توكن FCM
Future<void> setAllNotifs(bool on) async {
  prefs.setBool('mute', !on);
  try {
    if (myUid.isNotEmpty) {
      if (on) {
        await ref('notifOff/$myUid').remove();
      } else {
        await ref('notifOff/$myUid').set(true);
      }
    }
  } catch (_) {}
  if (on) {
    await initPush();
  } else {
    await dropPushToken();
  }
}

/// هل إشعارات هذه النقابة مكتومة عندي؟
Stream<bool> guildMutedStream(String gid) => ref('notifMute/$myUid/$gid').onValue.map((e) => e.snapshot.value == true);

Future<void> setGuildMuted(String gid, bool mute) async {
  try {
    if (mute) {
      await ref('notifMute/$myUid/$gid').set(true);
    } else {
      await ref('notifMute/$myUid/$gid').remove();
    }
    toast(mute ? 'تم إيقاف إشعارات هذه النقابة 🔕' : 'تم تفعيل إشعارات هذه النقابة 🔔');
  } catch (e) {
    err(e);
  }
}

/// زر بجانب اسم النقابة: كتم إشعارات هذه النقابة فقط
class GuildMuteButton extends StatelessWidget {
  final String gid;
  const GuildMuteButton(this.gid, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: guildMutedStream(gid),
      builder: (c, s) {
        final m = s.data == true;
        return IconButton(
          tooltip: m ? 'تفعيل إشعارات النقابة' : 'إيقاف إشعارات النقابة',
          visualDensity: VisualDensity.compact,
          icon: Icon(m ? Icons.notifications_off_outlined : Icons.notifications_active_outlined, size: 20),
          onPressed: () => setGuildMuted(gid, !m),
        );
      },
    );
  }
}
