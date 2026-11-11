import 'dino.dart';
import 'servertime.dart';
import 'vip.dart';
import 'uiprefs.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth.dart';
import 'bell.dart';
import 'data.dart';
import 'firebase_options.dart';
import 'home.dart';
import 'notif.dart';
import 'sfx.dart';
import 'sorter.dart' show envSuspect;
import 'susp.dart';
import 'support.dart';
import 'tapsound.dart';
import 'tools.dart';
import 'war.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await prefs.init();
    accentHex.value = prefs.getString('accent') ?? kDefaultAccentHex;
    await ensureFirebase();
    try {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
      FirebaseDatabase.instance.setPersistenceCacheSizeBytes(60 * 1024 * 1024);
    } catch (_) {}
    await ServerClock.init();
    await Sfx.init();
  } catch (e) {
    runApp(InitErrorApp(error: e.toString()));
    return;
  }
  if (await envSuspect()) {
    final dh = await deviceHash();
    if ((await suspStatus(dh)) != 'allow') {
      await reportSuspect(dh);
      runApp(const InitErrorApp(error: 'هذه نسخة غير رسمية أو مستنسخة من التطبيق.\nحمّل التطبيق الرسمي من الرابط الرسمي.'));
      return;
    }
  }
  runApp(const FirApp());
}

class InitErrorApp extends StatelessWidget {
  final String error;
  const InitErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(kDefaultAccentHex),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('تعذر تشغيل التطبيق\n$error', textAlign: TextAlign.center, textDirection: TextDirection.rtl),
          ),
        ),
      ),
    );
  }
}

class FirApp extends StatelessWidget {
  const FirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: vipKind,
      builder: (cv, vk, __) => ValueListenableBuilder<String>(
      valueListenable: accentHex,
      builder: (c, ac0, _) {
        // الصاعقة: ألوان الواجهة زرقاء دائماً (تتوقف خاصية تغيير اللون) | الملكي: خمري
        final ac = vk == 'thunder' ? '#2F8CFF' : (vk == 'royal' ? '#B3203F' : ac0);
        return MaterialApp(
        title: 'FIR',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        navigatorKey: WarWatcher.navKey,
        theme: buildTheme(ac),
        builder: (context, child) => ValueListenableBuilder<int>(
          valueListenable: fontStep,
          builder: (c2, fs, _) => MediaQuery(
            data: MediaQuery.of(c2).copyWith(textScaler: TextScaler.linear(fontScale(fs))),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: TapSound(
                child: Stack(children: [
                  child ?? const SizedBox(),
                  ValueListenableBuilder<bool>(valueListenable: vipOn, builder: (c3, v, _) => v ? const VipLayers() : const SizedBox.shrink()),
                ]),
              ),
            ),
          ),
        ),
        home: const AuthGate(),
      );
      },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([registering, reloadN]),
      builder: (c, _) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (c, s) {
          final u = s.data;
          if (s.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (u != null && !u.isAnonymous && !registering.value) {
            return HomeLoader(key: ValueKey('${u.uid}-${reloadN.value}'));
          }
          return const AuthFlow();
        },
      ),
    );
  }
}

class HomeLoader extends StatefulWidget {
  const HomeLoader({super.key});

  @override
  State<HomeLoader> createState() => _HomeLoaderState();
}

class _HomeLoaderState extends State<HomeLoader> {
  late Future<String> f = _load();

  Future<String> _load() => Session.load().timeout(const Duration(seconds: 9), onTimeout: () => 'offline').catchError((Object _) => 'offline').then((r) {
        if (r == 'ok') initVip();
        return r;
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: f,
      builder: (c, s) {
        if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        switch (s.data) {
          case 'ok':
            return FutureBuilder<bool>(
              future: integrityOk(),
              builder: (c, g) {
                if (!g.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
                if (g.data == false) {
                  return const Scaffold(
                    body: Center(child: Padding(padding: EdgeInsets.all(28), child: Text('⛔ تم حظرك\nلا تعبث مع الجي سي', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kRed, height: 1.8)))),
                  );
                }
                return const HomeScreen();
              },
            );
          case 'noprofile':
            return const RegisterScreen(google: true);
          case 'banned':
            return _Blocked(onOut: _out);
          case 'offline':
            return OfflineStartScreen(onRetry: () => setState(() => f = _load()), onOut: _out);
          default:
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('تعذر الاتصال'),
                    const SizedBox(height: 12),
                    AppButton('إعادة المحاولة', onPressed: () => setState(() => f = _load())),
                    TextButton(onPressed: _out, child: const Text('تسجيل الخروج')),
                  ],
                ),
              ),
            );
        }
      },
    );
  }

  Future<void> _out() async {
    BellService.stop();
    dropPushToken();
    Session.reset();
    await FirebaseAuth.instance.signOut();
  }
}

class _Blocked extends StatelessWidget {
  final VoidCallback onOut;
  const _Blocked({required this.onOut});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⛔', style: TextStyle(fontSize: 60)),
              const SizedBox(height: 10),
              const Text('تم حظرك من قبل أحد المطورين', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kRed)),
              const SizedBox(height: 10),
              const Text('إن كنت ترى أن الحظر خطأ، تواصل مع المطورين وأرفق ما يثبت ذلك.', textAlign: TextAlign.center, style: TextStyle(color: kMu, height: 1.7)),
              const SizedBox(height: 18),
              AppButton('تواصل مع المطورين', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SupportScreen()))),
              TextButton(onPressed: onOut, child: const Text('تسجيل الخروج')),
            ],
          ),
        ),
      ),
    );
  }
}
