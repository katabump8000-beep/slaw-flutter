import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'bell.dart';
import 'data.dart';
import 'firebase_options.dart';
import 'profile.dart';
import 'settings.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // إذا حدث خطأ أثناء رسم أي شاشة يظهر نصه بدل شاشة فارغة
  ErrorWidget.builder = (details) => Material(
        color: kBg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'خطأ: ${details.exceptionAsString()}',
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      );
  try {
    await Firebase.initializeApp(options: firebaseOptions);
  } catch (e) {
    runApp(InitErrorApp('Firebase: $e'));
    return;
  }
  await prefs.init();
  final ac = prefs.getString('ac');
  accentHex.value = hexOk(ac) ? ac! : kDefaultAccentHex;
  runApp(const SlawApp());
}

/// شاشة تظهر عند فشل تشغيل التطبيق وفيها نص الخطأ لتصويره
class InitErrorApp extends StatelessWidget {
  final String message;
  const InitErrorApp(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: SelectableText(
                'تعذر تشغيل التطبيق\n\n$message',
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SlawApp extends StatelessWidget {
  const SlawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: accentHex,
      builder: (context, ac, _) => MaterialApp(
        title: 'SLAW',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        theme: buildTheme(ac),
        // الواجهة من اليمين لليسار
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const AuthGate(),
      ),
    );
  }
}

/// يقرر: شاشة الدخول أو الشاشة الرئيسية
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final u = snap.data;
        if (u != null && !u.isAnonymous) return HomeLoader(key: ValueKey(u.uid));
        return const LoginScreen();
      },
    );
  }
}

/// يحمّل بيانات الحساب (الملف، الرتبة، الحظر) قبل فتح الشاشة الرئيسية
class HomeLoader extends StatefulWidget {
  const HomeLoader({super.key});

  @override
  State<HomeLoader> createState() => _HomeLoaderState();
}

class _HomeLoaderState extends State<HomeLoader> {
  late final Future<String> f = Session.load();

  @override
  void dispose() {
    BellService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final r = s.data ?? 'error';
        if (r == 'ok') return const ChatsScreen();
        return BlockedScreen(reason: r);
      },
    );
  }
}

class BlockedScreen extends StatelessWidget {
  final String reason;
  const BlockedScreen({super.key, required this.reason});

  @override
  Widget build(BuildContext context) {
    final msg = reason == 'banned'
        ? 'أنت محظور من استعمال التطبيق'
        : reason == 'noprofile'
            ? 'لا يوجد ملف لهذا الحساب'
            : 'تعذر الاتصال، تأكد من الإنترنت ثم أعد فتح التطبيق';
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              SizedBox(
                width: 200,
                child: AppButton('تسجيل خروج', kind: 'r', onPressed: () => FirebaseAuth.instance.signOut()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// تسجيل الدخول بكلمة السر (نفس كلمة السر في إعدادات التطبيق القديم)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final pw = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> _login() async {
    final p = pw.text.trim();
    if (p.length < 8) {
      setState(() => error = 'كلمة السر غير صحيحة');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) await auth.signInAnonymously();
      final h = sha256.convert(utf8.encode(p)).toString();
      final snap = await FirebaseDatabase.instance.ref('passmap/$h').get();
      if (!snap.exists) throw 'كلمة السر غير صحيحة';
      final m = Map<String, dynamic>.from(snap.value as Map);
      await auth.signInWithEmailAndPassword(email: m['e'] as String, password: p);
    } catch (e) {
      if (mounted) setState(() => error = e is String ? e : 'تعذر تسجيل الدخول، تأكد من الاتصال');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('SLAW', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: context.accent)),
                const SizedBox(height: 8),
                const Text('سجّل الدخول بكلمة السر الخاصة بحسابك'),
                const SizedBox(height: 24),
                TextField(
                  controller: pw,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'كلمة السر'),
                  onSubmitted: (_) => _login(),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy ? null : _login,
                    child: busy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('دخول'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GroupItem {
  final String id, name, kind;
  GroupItem(this.id, this.name, this.kind);
}

const Map<String, String> kKindName = {
  'main': 'نقابة',
  'ads': 'إعلانات',
  'shop': 'المتجر',
  'news': 'الصحيفة',
};

/// صورة القروب (groupPhotos/{id}) أو أول حرف من اسمه
class GroupAvatar extends StatefulWidget {
  final String gid;
  final String name;
  final double size;
  const GroupAvatar({super.key, required this.gid, required this.name, this.size = 42});

  @override
  State<GroupAvatar> createState() => _GroupAvatarState();
}

class _GroupAvatarState extends State<GroupAvatar> {
  MemoryImage? image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref('groupPhotos/${widget.gid}').get();
      final d = s.value?.toString() ?? '';
      if (d.isEmpty) return;
      final img = MemoryImage(base64Decode(d.substring(d.indexOf(',') + 1)));
      if (mounted) setState(() => image = img);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final img = image;
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF3A1A0D),
        image: img == null ? null : DecorationImage(image: img, fit: BoxFit.cover),
      ),
      child: img == null
          ? Text(firstChar(widget.name), style: TextStyle(fontSize: widget.size * .39, fontWeight: FontWeight.w800))
          : null,
    );
  }
}

/// الشاشة الرئيسية: الهيدر + المجموعات + الأصدقاء
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  late Future<List<GroupItem>> future = _load();
  List<String> favs = [];

  @override
  void initState() {
    super.initState();
    try {
      favs = (jsonDecode(prefs.getString('favs') ?? '[]') as List).map((e) => e.toString()).toList();
    } catch (_) {
      favs = [];
    }
    BellService.start();
    Session.ensurePid();
  }

  Future<List<GroupItem>> _load() async {
    final database = FirebaseDatabase.instance;
    final me = FirebaseAuth.instance.currentUser!.uid;
    final gs = await database.ref('groups').get();
    if (!gs.exists) return [];
    final map = Map<String, dynamic>.from(gs.value as Map);
    final out = <GroupItem>[];
    await Future.wait(map.entries.map((e) async {
      final m = await database.ref('members/${e.key}/$me').get();
      if (m.exists) {
        final v = Map<String, dynamic>.from(e.value as Map);
        out.add(GroupItem(e.key, (v['name'] ?? '').toString(), (v['kind'] ?? '').toString()));
      }
    }));
    out.sort((a, b) => (a.kind == 'main' ? 0 : 1).compareTo(b.kind == 'main' ? 0 : 1));
    return out;
  }

  void _toggleFav(String u) {
    setState(() {
      if (favs.contains(u)) {
        favs.remove(u);
      } else {
        favs.add(u);
      }
    });
    prefs.setString('favs', jsonEncode(favs));
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color.fromRGBO(255, 255, 255, .06)),
        child: Icon(icon, size: 22),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: kBg2,
        border: Border(bottom: BorderSide(color: kLine)),
      ),
      child: Row(
        children: [
          UserAvatar(
            myUid,
            size: 42,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: avatarTick,
              builder: (context, _, __) => Text(
                Session.me.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          _iconBtn(Icons.person_add_alt, () => addFriendSheet(context)),
          const SizedBox(width: 8),
          BellButton(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BellScreen()))),
          const SizedBox(width: 8),
          _iconBtn(Icons.settings_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
      ),
    );
  }

  Widget _secard(BuildContext context, String title, Widget child) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentA(context, .55)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color.fromRGBO(0, 0, 0, .35), accentA(context, .06)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: accentA(context, .12),
            child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.accent2)),
          ),
          child,
        ],
      ),
    );
  }

  Widget _row({required Widget leading, required String title, String? sub, Widget? trailing, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color.fromRGBO(255, 190, 140, .08))),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (sub != null) Text(sub, style: const TextStyle(fontSize: 12, color: kMu)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _groups(BuildContext context) {
    return FutureBuilder<List<GroupItem>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('لا توجد مجموعات', style: TextStyle(color: kMu))));
        }
        return Column(
          children: [
            for (final g in list)
              _row(
                leading: GroupAvatar(gid: g.id, name: g.name),
                title: g.name,
                sub: kKindName[g.kind],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChatScreen(gid: g.id, name: g.name)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _friends(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('friends/$myUid').onValue,
      builder: (context, snap) {
        final v = snap.data?.snapshot.value;
        final ids = v is Map ? v.keys.map((k) => k.toString()).toList() : <String>[];
        ids.sort((a, b) => (favs.contains(a) ? 0 : 1).compareTo(favs.contains(b) ? 0 : 1));
        if (ids.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('أضف أصدقاء وسيظهرون هنا للمراسلة', style: TextStyle(color: kMu))),
          );
        }
        return Column(
          children: [
            for (final u in ids)
              FutureBuilder<Prof>(
                future: prof(u),
                builder: (context, ps) {
                  final fav = favs.contains(u);
                  return _row(
                    leading: UserAvatar(u, size: 42),
                    title: ps.data?.name ?? '…',
                    sub: fav ? 'مفضّل' : 'صديق',
                    trailing: InkWell(
                      onTap: () => _toggleFav(u),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(fav ? Icons.star : Icons.star_border, color: fav ? context.accent2 : kMu),
                      ),
                    ),
                    // مؤقتاً يفتح الملف التعريفي. المراسلة الخاصة في المرحلة 2
                    onTap: () => viewProfile(context, u),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  _secard(context, 'المجموعات', _groups(context)),
                  _secard(context, 'الدردشات', _friends(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final Map<String, Future<String>> _names = {};
Future<String> nameOf(String uid) => _names.putIfAbsent(
      uid,
      () => FirebaseDatabase.instance
          .ref('profiles/$uid/name')
          .get()
          .then((s) => s.exists ? s.value.toString() : 'عضو')
          .catchError((_) => 'عضو'),
    );

/// شاشة الدردشة: رسائل مباشرة + إرسال نص
class ChatScreen extends StatefulWidget {
  final String gid, name;
  const ChatScreen({super.key, required this.gid, required this.name});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ctrl = TextEditingController();
  final uid = FirebaseAuth.instance.currentUser!.uid;
  String myColor = '#ff7a1a';

  @override
  void initState() {
    super.initState();
    FirebaseDatabase.instance.ref('profiles/$uid/color').get().then((s) {
      if (s.exists) myColor = s.value.toString();
    });
  }

  Future<void> _send() async {
    final t = ctrl.text.trim();
    if (t.isEmpty) return;
    ctrl.clear();
    try {
      await FirebaseDatabase.instance.ref('messages/${widget.gid}').push().set({
        'from': uid,
        'type': 'text',
        'text': t,
        'ts': ServerValue.timestamp,
        'color': myColor,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر الإرسال')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseDatabase.instance.ref('messages/${widget.gid}').orderByKey().limitToLast(60);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: q.onValue,
              builder: (context, snap) {
                final v = snap.data?.snapshot.value;
                if (v == null) return const Center(child: Text('لا توجد رسائل بعد'));
                final m = Map<String, dynamic>.from(v as Map);
                final keys = m.keys.toList()..sort();
                final rows = keys.reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(10),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final d = Map<String, dynamic>.from(m[rows[i]] as Map);
                    return Bubble(msg: d, mine: d['from'] == uid);
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                        hintText: 'اكتب رسالة…',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Bubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool mine;
  const Bubble({super.key, required this.msg, required this.mine});

  Color _color() {
    final c = (msg['color'] ?? '').toString();
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(c)) {
      return Color(int.parse('FF${c.substring(1)}', radix: 16));
    }
    return const Color(0xFF5B5BE0);
  }

  @override
  Widget build(BuildContext context) {
    final type = (msg['type'] ?? 'text').toString();
    if (type == 'sys') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text((msg['text'] ?? '').toString(), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
      );
    }
    final text = type == 'text' ? (msg['text'] ?? '').toString() : '[وسائط — ستُدعم لاحقاً]';
    return Align(
      alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        decoration: BoxDecoration(color: _color(), borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              FutureBuilder<String>(
                future: nameOf((msg['from'] ?? '').toString()),
                builder: (c, s) => Text(s.data ?? '…', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            Text(text, style: const TextStyle(fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
