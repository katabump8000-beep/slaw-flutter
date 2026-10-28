import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'core.dart';
import 'crop.dart';
import 'data.dart';
import 'home.dart';
import 'invite.dart';
import 'profile.dart';
import 'war.dart';
import 'widgets.dart';

class GroupInfoScreen extends StatefulWidget {
  final String gid;
  const GroupInfoScreen({super.key, required this.gid});
  @override
  State<GroupInfoScreen> createState() => _InfoState();
}

class _InfoState extends State<GroupInfoScreen> {
  String get gid => widget.gid;
  Map<String, dynamic> g = {};
  Map<String, dynamic> admins = {};
  Map<String, dynamic> members = {};
  Map<String, dynamic> bios = {};
  String status = '';
  bool loading = true;

  bool get staff => Session.isDev || admins[myUid] == true;
  bool get full => memCache[gid] == true;
  String get kind => groupKind(gid);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _m(String p) async {
    try {
      final v = (await ref(p).get()).value;
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _load() async {
    g = await _m('groups/$gid');
    groupsCache[gid] = g;
    admins = await _m('groupAdmins/$gid');
    if (full || staff) {
      members = await _m('members/$gid');
      bios = await _m('groupBios/$gid');
    }
    try {
      final s = (await ref('groupStatus/$gid/t').get()).value;
      status = s?.toString() ?? '';
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _photo() async {
    if (!staff) return;
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null || !mounted) return;
      final d = await cropImage(context, await x.readAsBytes(), out: const [200, 160, 120], limit: 29000, round: true, title: 'صورة القروب');
      if (d == null) return;
      await ref('groupPhotos/$gid').set(d);
      dropGroupPhoto(gid);
      if (mounted) setState(() {});
    } catch (e) {
      err(e);
    }
  }

  void _editText() {
    final nm = TextEditingController(text: (g['name'] ?? '').toString());
    final ds = TextEditingController(text: (g['desc'] ?? '').toString());
    showAppSheet<void>(context, (sc) => [
          const Text('تعديل القروب', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          TextField(controller: nm, maxLength: 40, decoration: const InputDecoration(hintText: 'الاسم', counterText: '')),
          TextField(controller: ds, maxLength: 300, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: 'الوصف')),
          AppButton('حفظ', onPressed: () async {
            try {
              await ref('groups/$gid').update(<String, Object?>{'name': nm.text.trim().isEmpty ? g['name'] : nm.text.trim(), 'desc': ds.text.trim()});
              if (sc.mounted) Navigator.of(sc).pop();
              await _load();
            } catch (e) {
              err(e);
            }
          }),
        ]);
  }

  void _editStatus() {
    final c = TextEditingController(text: status);
    showAppSheet<void>(context, (sc) => [
          const Text('حالة القروب', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          TextField(controller: c, maxLength: 200, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'اكتب حالة تظهر أعلى الدردشة (فارغ للحذف)')),
          AppButton('حفظ', onPressed: () async {
            try {
              final t = c.text.trim();
              if (t.isEmpty) {
                await ref('groupStatus/$gid').remove();
              } else {
                await ref('groupStatus/$gid').set(<String, Object?>{'t': t, 'by': myUid, 'ts': DateTime.now().millisecondsSinceEpoch});
              }
              if (sc.mounted) Navigator.of(sc).pop();
              await _load();
            } catch (e) {
              err(e);
            }
          }),
        ]);
  }

  Future<void> _addMember() async {
    Map<String, dynamic> all = await _m('profiles');
    if (!mounted) return;
    final q = TextEditingController();
    showAppSheet<void>(context, (sc) => [
          const Text('إضافة عضو', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          StatefulBuilder(builder: (c, set) {
            final f = q.text.trim();
            final list = all.entries.where((e) => e.value is Map && (f.isEmpty || (e.value['name'] ?? '').toString().contains(f))).take(40).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: q, onChanged: (_) => set(() {}), decoration: const InputDecoration(hintText: 'ابحث بالاسم')),
              ...list.map((e) => ListTile(
                    dense: true,
                    leading: UserAvatar(e.key, size: 34),
                    title: Text((e.value['name'] ?? '').toString()),
                    onTap: () async {
                      try {
                        await ref('members/$gid/${e.key}').set(true);
                        if (kind == 'main') {
                          var n = 0;
                          for (final x in groupsCache.keys.where((x) => groupKind(x) == 'main')) {
                            if ((await ref('members/$x/${e.key}').get()).value == true) n++;
                          }
                          if (n >= 2) await ref('multi/${e.key}').set(true);
                        }
                        await sendNotif(e.key, {'t': 'add', 'g': gid, 'm': groupName(gid)});
                        if (sc.mounted) Navigator.of(sc).pop();
                        toast('تمت الإضافة ✅');
                        await _load();
                      } catch (x) {
                        err(x);
                      }
                    },
                  )),
            ]);
          }),
        ]);
  }

  Future<void> _memberMenu(String u) async {
    final role = await roleOf(u);
    final high = role == 'dev' || role == 'emp';
    if (role == 'emp' && !Session.isEmp) {
      toast('لا يمكن التحكم بهذه الرتبة', bad: true);
      return;
    }
    if (high && !Session.isDev) {
      toast('لا يمكن التحكم بالرتب العليا', bad: true);
      return;
    }
    final p = await prof(u);
    bool gp = false;
    try {
      gp = (await ref('gamePerm/$gid/$u').get()).exists;
    } catch (_) {}
    if (!mounted) return;
    Future<void> act(Future<void> Function() f, {String? note}) async {
      try {
        await f();
        toast('تم ✅');
        if (note != null) await sendNotif(u, {'t': note, 'g': gid, 'm': groupName(gid)});
        await _load();
      } catch (e) {
        err(e);
      }
    }
    Future<void> mute(int h) => act(() => ref('bans/$gid/$u').set(DateTime.now().millisecondsSinceEpoch + h * 3600000), note: 'mute');
    showAppSheet<void>(context, (sc) {
      Widget b(String t, Future<void> Function() f, {String kind = 'g', String? note}) => AppButton(t, kind: kind, onPressed: () {
            Navigator.of(sc).pop();
            act(f, note: note);
          });
      return [
        Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        AppButton('📝 نبذة ولون النص', kind: 'g', onPressed: () {
          Navigator.of(sc).pop();
          _bioSheet(u);
        }),
        AppButton('👤 الملف التعريفي', kind: 'g', onPressed: () {
          Navigator.of(sc).pop();
          viewProfile(context, u);
        }),
        b('🔇 كتم ساعة', () => mute(1)),
        b('🔇 كتم يوم', () => mute(24)),
        b('🔇 كتم أسبوع', () => mute(168)),
        b('🔊 إلغاء الكتم', () => ref('bans/$gid/$u').remove()),
        if (kind == 'main') b(gp ? '🎮 سحب صلاحية الألعاب' : '🎮 منح صلاحية الألعاب', () => gp ? ref('gamePerm/$gid/$u').remove() : ref('gamePerm/$gid/$u').set(true)),
        if (Session.isDev) b(admins[u] == true ? '⬇️ إزالة الإشراف' : '⬆️ تعيين مشرف', () => admins[u] == true ? ref('groupAdmins/$gid/$u').remove() : ref('groupAdmins/$gid/$u').set(true), note: 'role'),
        b('🚪 طرد من القروب', () => ref('members/$gid/$u').remove(), kind: 'r', note: 'kick'),
        if (Session.isDev && !high) b('⛔ حظر من التطبيق', () => ref('banned/$u').set(true), kind: 'r'),
        if (Session.isDev) b('✅ رفع الحظر من التطبيق', () => ref('banned/$u').remove()),
      ];
    });
  }

  void _bioSheet(String u) {
    final b = bios[u] is Map ? Map<String, dynamic>.from(bios[u] as Map) : <String, dynamic>{};
    final t = TextEditingController(text: (b['t'] ?? '').toString());
    var col = (b['c'] ?? '#ffb04a').toString();
    const pal = ['#ffb04a', '#ff5a4d', '#ff7eb6', '#c792ff', '#7fb2ff', '#5de0e6', '#6ee787', '#ffe066', '#ffffff'];
    showAppSheet<void>(context, (sc) => [
          StatefulBuilder(builder: (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('نبذة العضو', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                TextField(controller: t, maxLength: 40, decoration: const InputDecoration(hintText: 'النبذة (تظهر تحت اسمه)')),
                Wrap(spacing: 10, runSpacing: 10, children: pal.map((x) => GestureDetector(onTap: () => set(() => col = x), child: Container(width: 34, height: 34, decoration: BoxDecoration(shape: BoxShape.circle, color: hexColor(x), border: Border.all(color: col == x ? Colors.white : Colors.transparent, width: 3))))).toList()),
                const SizedBox(height: 10),
                AppButton('حفظ', onPressed: () async {
                  try {
                    final v = t.text.trim();
                    if (v.isEmpty) {
                      await ref('groupBios/$gid/$u').remove();
                    } else {
                      await ref('groupBios/$gid/$u').set(<String, Object?>{'t': v, 'c': col});
                    }
                    if (sc.mounted) Navigator.of(sc).pop();
                    await _load();
                  } catch (e) {
                    err(e);
                  }
                }),
              ])),
        ]);
  }

  Widget _switch(String t, bool v, Future<void> Function(bool) f) => SwitchListTile(title: Text(t), value: v, onChanged: (x) async {
        try {
          await f(x);
          await _load();
        } catch (e) {
          err(e);
        }
      });

  @override
  Widget build(BuildContext context) {
    final ids = members.keys.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('معلومات القروب')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.only(bottom: 40), children: [
              const SizedBox(height: 16),
              Center(child: GestureDetector(onTap: _photo, child: GroupPhoto(gid, size: 96))),
              if (staff) const Center(child: Padding(padding: EdgeInsets.only(top: 4), child: Text('اضغط الصورة لتغييرها', style: TextStyle(color: kMu, fontSize: 12)))),
              Center(child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(groupName(gid), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)))),
              Center(child: Tag(kKinds[kind] ?? '')),
              Padding(padding: const EdgeInsets.all(16), child: Text((g['desc'] ?? '').toString().isEmpty ? 'لا يوجد وصف' : g['desc'].toString(), style: const TextStyle(color: kMu, height: 1.8))),
              if (status.isNotEmpty) Container(margin: const EdgeInsets.symmetric(horizontal: 16), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: accentA(context, .1), borderRadius: BorderRadius.circular(12)), child: Text('📌 $status')),
              if (staff) ...[
                ListTile(leading: const Icon(Icons.edit), title: const Text('تعديل الاسم والوصف'), onTap: _editText),
                ListTile(leading: const Icon(Icons.push_pin_outlined), title: const Text('حالة القروب'), onTap: _editStatus),
                _switch('قفل الشات', g['locked'] == true, (v) => ref('groups/$gid/locked').set(v)),
                if (kind == 'main') _switch('الألعاب للجميع', g['gamesAll'] == true, (v) => ref('groups/$gid/gamesAll').set(v)),
                if (kind == 'main')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Wrap(spacing: 10, runSpacing: 10, children: ['#2a6cff', '#e53935', '#8e24aa', '#00897b', '#f9a825', '#d81b60', '#43a047', '#ff7a1a'].map((x) => GestureDetector(onTap: () async {
                          await ref('groups/$gid/c').set(x);
                          await _load();
                        }, child: Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, color: hexColor(x), border: Border.all(color: g['c'] == x ? Colors.white : Colors.transparent, width: 3))))).toList()),
                  ),
              ],
              if (Session.isDev)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 8, children: kKinds.entries.map((e) => ChoiceChip(label: Text(e.value), selected: kind == e.key, onSelected: (_) async {
                        try {
                          await ref('groups/$gid').update(<String, Object?>{'kind': e.key, if (e.key != 'main') 'locked': true});
                          await _load();
                        } catch (x) {
                          err(x);
                        }
                      })).toList()),
                ),
              if (kind == 'main' && full) ...[
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: InviteSection(gid: gid)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: GuildPanel(gid: gid)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: leaderPick(context)),
              ],
              const Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 6), child: Text('الأعضاء', style: TextStyle(fontWeight: FontWeight.w800, color: kMu))),
              if (!full && !staff) const Padding(padding: EdgeInsets.all(16), child: Text('لا يمكن رؤية أعضاء هذا القروب.', style: TextStyle(color: kMu))),
              if (Session.isDev) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: AppButton('➕ إضافة عضو', kind: 'g', onPressed: _addMember)),
              for (final u in ids) _MemberRow(u: u, v: members[u], bio: bios[u], admin: admins[u] == true, staffView: staff && kind == 'main', onTap: staff && u != myUid ? () => _memberMenu(u) : null),
            ]),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final String u;
  final dynamic v;
  final dynamic bio;
  final bool admin;
  final bool staffView;
  final VoidCallback? onTap;
  const _MemberRow({required this.u, required this.v, required this.bio, required this.admin, required this.staffView, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([
        prof(u),
        roleOf(u),
        ref('pubCount/$u').get(),
        if (staffView) ref('multi/$u').get(),
      ]),
      builder: (c, s) {
        final d = s.data;
        final p = d != null ? d[0] as Prof : Prof.fallback;
        final r = d != null ? d[1] as String? : null;
        final n = d != null && (d[2] as DataSnapshot).value is num ? ((d[2] as DataSnapshot).value as num).toInt() : 0;
        final multi = d != null && staffView && d.length > 3 && (d[3] as DataSnapshot).exists;
        final tag = rankTag(r);
        return ListTile(
          onTap: onTap,
          leading: UserAvatar(u, size: 42),
          title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (r == 'emp') const InfinityMark(size: 15),
            if (tag != null) tag,
            if (admin && r == null) const Tag('مشرف'),
            ageTag(p),
            if (v == 'v') const Tag('زائر'),
            if (multi) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: const Color(0x33FF3B3B), borderRadius: BorderRadius.circular(8)), child: const Text('تعدد', style: TextStyle(color: kRed, fontSize: 10, fontWeight: FontWeight.w800))),
          ]),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (bio is Map && (bio['t'] ?? '').toString().isNotEmpty) Text(bio['t'].toString(), style: TextStyle(color: hexOk(bio['c']?.toString()) ? hexColor(bio['c'].toString()) : kMu, fontSize: 12)),
            Text('النشر: $n', style: const TextStyle(fontSize: 11, color: kMu)),
          ]),
        );
      },
    );
  }
}
