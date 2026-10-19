import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const SlawApp());
}

const kOrange = Color(0xFFFF7A1A);
const kBg = Color(0xFF120804);

class SlawApp extends StatelessWidget {
  const SlawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SLAW',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(seedColor: kOrange, brightness: Brightness.dark),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1B0A04)),
      ),
      // الواجهة من اليمين لليسار
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const AuthGate(),
    );
  }
}

/// يقرر: شاشة الدخول أو شاشة الدردشات
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final u = snap.data;
        if (u != null && !u.isAnonymous) return const ChatsScreen();
        return const LoginScreen();
      },
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
                const Text('SLAW', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: kOrange)),
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

/// قائمة القروبات التي أنت عضو فيها
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  late Future<List<GroupItem>> future = _load();

  Future<List<GroupItem>> _load() async {
    final db = FirebaseDatabase.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final gs = await db.ref('groups').get();
    if (!gs.exists) return [];
    final map = Map<String, dynamic>.from(gs.value as Map);
    final out = <GroupItem>[];
    await Future.wait(map.entries.map((e) async {
      final m = await db.ref('members/${e.key}/$uid').get();
      if (m.exists) {
        final v = Map<String, dynamic>.from(e.value as Map);
        out.add(GroupItem(e.key, (v['name'] ?? '').toString(), (v['kind'] ?? '').toString()));
      }
    }));
    out.sort((a, b) => (a.kind == 'main' ? 0 : 1).compareTo(b.kind == 'main' ? 0 : 1));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الدردشات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: FutureBuilder<List<GroupItem>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? [];
          if (list.isEmpty) return const Center(child: Text('لا توجد دردشات'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final g = list[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: kOrange.withOpacity(.25),
                  child: Text(g.name.isEmpty ? '?' : g.name[0]),
                ),
                title: Text(g.name),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChatScreen(gid: g.id, name: g.name)),
                ),
              );
            },
          );
        },
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
