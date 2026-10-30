import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'empchat.dart';
import 'tools.dart';
import 'widgets.dart';

const int kFriendCap = 10;

List<String> _favs() => (prefs.getString('fav_friends') ?? '').split(',').where((e) => e.isNotEmpty).toList();

bool get _unlimited => Session.isDev;

/// قسم «الأصدقاء» في الشاشة الرئيسية
class FriendsSection extends StatelessWidget {
  const FriendsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ref('friends/$myUid').onValue,
      builder: (c, s) {
        final v = s.data?.snapshot.value;
        final ids = v is Map ? v.keys.map((e) => e.toString()).toList() : <String>[];
        final fav = _favs();
        ids.sort((a, b) => (fav.contains(b) ? 1 : 0) - (fav.contains(a) ? 1 : 0));
        return StreamBuilder<DatabaseEvent>(
          stream: ref('friendReq/$myUid').onValue,
          builder: (c2, s2) {
            final rv = s2.data?.snapshot.value;
            final n = rv is Map ? rv.length : 0;
            if (ids.isEmpty && n == 0) return const SizedBox.shrink();
            return SecCard(title: 'الأصدقاء', children: [
              if (n > 0)
                ListTile(
                  leading: Icon(Icons.person_add_alt_1, color: context.accent2),
                  title: Text('$n طلب صداقة'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FriendsScreen())),
                ),
              ...ids.map((u) => _FriendRow(uid: u, fav: fav.contains(u))),
            ]);
          },
        );
      },
    );
  }
}

class _FriendRow extends StatefulWidget {
  final String uid;
  final bool fav;
  const _FriendRow({required this.uid, required this.fav});
  @override
  State<_FriendRow> createState() => _FriendRowState();
}

class _FriendRowState extends State<_FriendRow> {
  late bool fav = widget.fav;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FriendDmScreen(peer: widget.uid))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          UserAvatar(widget.uid, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: FutureBuilder<Prof>(
              future: prof(widget.uid),
              builder: (c, s) => Text(s.data?.name ?? '...', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          IconButton(
            onPressed: () {
              final l = _favs();
              fav ? l.remove(widget.uid) : l.add(widget.uid);
              prefs.setString('fav_friends', l.join(','));
              setState(() => fav = !fav);
            },
            icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded, color: fav ? const Color(0xFFFFD54A) : kMu),
          ),
        ]),
      ),
    );
  }
}

/// البحث عن أصدقاء + الطلبات الواردة
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final q = TextEditingController();
  String? found;
  String msg = '';
  bool busy = false;

  Future<int> _count() async {
    final v = (await ref('friends/$myUid').get()).value;
    return v is Map ? v.length : 0;
  }

  Future<void> _search() async {
    setState(() {
      busy = true;
      msg = '';
      found = null;
    });
    final u = await uidFromPid(q.text);
    if (u == null) {
      msg = 'لا يوجد مستخدم بهذا الـID';
    } else if (u == myUid) {
      msg = 'هذا حسابك';
    } else {
      found = u;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _send(String u) async {
    try {
      final ex = (await ref('friends/$myUid/$u').get()).exists;
      if (ex) {
        toast('هو صديقك بالفعل');
        return;
      }
      if (!_unlimited && await _count() >= kFriendCap) {
        toast('وصلت للحد الأقصى ($kFriendCap أصدقاء)', bad: true);
        return;
      }
      await ref('friendReq/$u/$myUid').set(ServerValue.timestamp);
      toast('تم إرسال الطلب ✅');
    } catch (e) {
      toast('الطلب مرسل مسبقاً أو غير متاح', bad: true);
    }
  }

  Future<void> _accept(String from) async {
    try {
      if (!_unlimited && await _count() >= kFriendCap) {
        toast('وصلت للحد الأقصى ($kFriendCap أصدقاء)', bad: true);
        return;
      }
      await db.ref().update(<String, Object?>{
        'friends/$myUid/$from': true,
        'friends/$from/$myUid': true,
        'friendReq/$myUid/$from': null,
      });
      toast('تمت الإضافة ✅');
    } catch (e) {
      err(e);
    }
  }

  Future<void> _decline(String from) async {
    try {
      await ref('friendReq/$myUid/$from').remove();
    } catch (e) {
      err(e);
    }
  }

  Widget _person(String u, List<Widget> actions) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .25), borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine)),
        child: Row(children: [
          UserAvatar(u, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: FutureBuilder<Prof>(
              future: prof(u),
              builder: (c, s) => Text(s.data?.name ?? '...', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          ...actions,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأصدقاء')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: TextField(controller: q, keyboardType: TextInputType.number, onSubmitted: (_) => _search(), decoration: const InputDecoration(hintText: 'ابحث بالـID'))),
            const SizedBox(width: 8),
            IconButton(onPressed: busy ? null : _search, icon: const Icon(Icons.search)),
          ]),
        ),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.all(14), child: Center(child: Text(msg, style: const TextStyle(color: kMu)))),
        if (found != null) _person(found!, [SizedBox(width: 120, child: AppButton('إرسال طلب', compact: true, onPressed: () => _send(found!)))]),
        const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('الطلبات الواردة', style: TextStyle(color: kMu, fontWeight: FontWeight.w800))),
        StreamBuilder<DatabaseEvent>(
          stream: ref('friendReq/$myUid').onValue,
          builder: (c, s) {
            final v = s.data?.snapshot.value;
            final ids = v is Map ? v.keys.map((e) => e.toString()).toList() : <String>[];
            if (ids.isEmpty) return const Padding(padding: EdgeInsets.all(14), child: Center(child: Text('لا توجد طلبات', style: TextStyle(color: kMu))));
            return Column(children: [
              for (final u in ids)
                _person(u, [
                  IconButton(onPressed: () => _accept(u), icon: const Icon(Icons.check_circle, color: Color(0xFF3DDC84))),
                  IconButton(onPressed: () => _decline(u), icon: const Icon(Icons.cancel, color: Color(0xFFFF5252))),
                ]),
            ]);
          },
        ),
        const SizedBox(height: 30),
      ]),
    );
  }
}
