import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'core.dart';
import 'data.dart';
import 'home.dart';
import 'widgets.dart';

/// بطاقة متصدري النقابة (تنزل في الإعلانات عند الحسبة)
class RankCard extends StatelessWidget {
  final Map<String, dynamic> o;
  const RankCard({super.key, required this.o});

  @override
  Widget build(BuildContext context) {
    final c = hexOk(o['c']?.toString()) ? o['c'].toString() : '#2a6cff';
    final l = (o['l'] is List) ? (o['l'] as List) : <dynamic>[];
    const ring = [Color(0xFFFFD54A), Color(0xFFCFD8DC), Color(0xFFCD7F32)];
    Widget top(int i) {
      if (i >= l.length) return const SizedBox(width: 80);
      final r = l[i] as List;
      return SizedBox(
        width: 92,
        child: Column(children: [
          if (i == 0) const Text('👑', style: TextStyle(fontSize: 22)),
          Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring[i], width: 4), boxShadow: [BoxShadow(color: ring[i].withAlpha(160), blurRadius: 14)]),
            child: UserAvatar(r[0].toString(), size: i == 0 ? 74 : 62),
          ),
          Text('${i + 1}', style: TextStyle(color: ring[i], fontWeight: FontWeight.w900, fontSize: 18)),
          Text(r[1].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Text('${r[2]} رسالة', style: const TextStyle(fontSize: 11, color: kMu)),
        ]),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x22FFFFFF)),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [hexColor(darkHex(c)), const Color(0xFF07101F)]),
      ),
      child: Column(children: [
        Text('🏆 ${o['n']}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: hexColor(c))),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, crossAxisAlignment: CrossAxisAlignment.end, textDirection: TextDirection.ltr, children: [top(1), top(0), top(2)]),
        const SizedBox(height: 8),
        for (var i = 3; i < l.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x14FFFFFF)))),
            child: Row(children: [
              SizedBox(width: 24, child: Text('${i + 1}')),
              Expanded(child: Text((l[i] as List)[1].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Text((l[i] as List)[3] == 'f' ? '👩' : '👨'),
              const SizedBox(width: 10),
              Text('${(l[i] as List)[2]}', style: const TextStyle(color: Color(0xFFFFD54A))),
            ]),
          ),
      ]),
    );
  }
}

bool _ticking = false;

/// الحسبة اليومية (تنفّذها أجهزة المطورين عند الساعة التي يحددها الإمبراطور)
Future<void> runTally() async {
  if (_ticking) return;
  _ticking = true;
  try {
    final hh = (await ref('meta/tallyHour').get()).value;
    final hour = hh is num ? hh.toInt() : 23;
    final n = DateTime.now();
    if (n.hour < hour) return;
    final key = 'tally_${n.year}_${n.month}_${n.day}';
    try {
      await ref('locks/$key').set(true);
    } catch (_) {
      return;
    }
    final ms = groupsCache.keys.where((g) => groupKind(g) == 'main').toList();
    final ads = feedGid('ads') ?? feedGid('news');
    final res = <MapEntry<String, int>>[];
    for (final g in ms) {
      final st = (await ref('stats/$g').get()).value;
      final ents = <MapEntry<String, int>>[];
      if (st is Map) st.forEach((k, v) => v is num && v > 0 ? ents.add(MapEntry(k.toString(), v.toInt())) : null);
      ents.sort((a, b) => b.value.compareTo(a.value));
      final total = ents.fold<int>(0, (s, e) => s + e.value);
      if (total == 0) continue;
      res.add(MapEntry(g, total));
      final l = <List<Object>>[];
      for (final e in ents.take(10)) {
        final p = await prof(e.key);
        l.add([e.key, p.name, e.value, p.gender]);
      }
      if (ads != null) {
        await ref('messages/$ads').push().set(<String, Object?>{
          'from': myUid, 'type': 'sys', 'k': 'rank', 'text': '🏆 متصدرو ${groupName(g)}', 'ts': ServerValue.timestamp,
          'd': jsonEncode({'n': groupName(g), 'c': groupColor(g), 'l': l}),
        });
      }
    }
    if (ads != null && res.isNotEmpty) {
      res.sort((a, b) => b.value.compareTo(a.value));
      const names = ['المركز الأول', 'المركز الثاني', 'المركز الثالث'];
      final lines = <String>['⌬━─⟐─ ⊱•💭•⊰ ─⟐─━⌬'];
      for (var i = 0; i < res.length; i++) {
        lines.add('${i < 3 ? names[i] : '${i + 1}'}:\n${groupName(res[i].key)} (${fmtN(res[i].value)} رسالة)');
      }
      await ref('messages/$ads').push().set(<String, Object?>{'from': myUid, 'type': 'sys', 'k': 'note', 'text': lines.join('\n'), 'ts': ServerValue.timestamp});
    }
    for (final g in ms) {
      try {
        await ref('messages/$g').remove();
        await ref('stats/$g').remove();
      } catch (_) {}
    }
    final bo = (await ref('boost').get()).value;
    if (bo is Map) {
      for (final u in bo.keys) {
        try {
          await ref('boost/$u').remove();
        } catch (_) {}
      }
    }
  } catch (_) {
  } finally {
    _ticking = false;
  }
}

/// تصفير المتصدرين (للإمبراطور فقط)
Future<void> resetLeaderboard() async {
  try {
    for (final g in groupsCache.keys.where((g) => groupKind(g) == 'main')) {
      await ref('stats/$g').remove();
    }
    await feedNote('ads', '♻️ تم تصفير المتصدرين بواسطة الإمبراطور');
    toast('تم تصفير المتصدرين ✅');
  } catch (e) {
    err(e);
  }
}

/// من انخفضت درجة فخره عن 40: يُصفَّر رصيده وتُسحب رتبته (ينفذه المطورون)
Future<void> prideSweep() async {
  try {
    final p = (await ref('pride').get()).value;
    if (p is! Map) return;
    for (final e in p.entries) {
      final u = e.key.toString();
      final v = e.value is num ? (e.value as num).toInt() : 100;
      if (v >= 40 || prefs.getBool('pd_$u') == true) continue;
      if (u == Session.emp) continue;
      prefs.setBool('pd_$u', true);
      final up = <String, Object?>{'wallets/$u/bal': 0, 'roles/$u': null, 'devs/$u': null};
      for (final g in groupsCache.keys) {
        up['groupAdmins/$g/$u'] = null;
      }
      await db.ref().update(up);
    }
  } catch (_) {}
}
