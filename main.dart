import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth.dart';
import 'bell.dart';
import 'data.dart';
import 'firebase_options.dart';
import 'home.dart';
import 'tools.dart';
import 'war.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await prefs.init();
    accentHex.value = prefs.getString('accent') ?? kDefaultAccentHex;
    await Firebase.initializeApp(options: firebaseOptions);
  } catch (e) {
    runApp(InitErrorApp(error: e.toString()));
    return;
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
      valueListenable: accentHex,
      builder: (c, ac, _) => MaterialApp(
        title: 'FIR',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        navigatorKey: WarWatcher.navKey,
        theme: buildTheme(ac),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(children: [child ?? const SizedBox(), const EdgeGlow()]),
        ),
        home: const AuthGate(),
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
  late Future<String> f = Session.load();

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
          default:
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('تعذر الاتصال'),
                    const SizedBox(height: 12),
                    AppButton('إعادة المحاولة', onPressed: () => setState(() => f = Session.load())),
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
              const Text('تم حظرك من التطبيق', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kRed)),
              const SizedBox(height: 18),
              TextButton(onPressed: onOut, child: const Text('تسجيل الخروج')),
            ],
          ),
        ),
      ),
    );
  }
}
