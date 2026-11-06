import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'home.dart';
import 'sfx.dart';
import 'tools.dart' show uidFromPid;
import 'visuals.dart';
import 'widgets.dart';

/// «سحب / إعطاء»: ابحث بلقب أو ID ثم عدّل رصيد العضو (للمطورين والإمبراطور)
class GiveTakeScreen extends StatefulWidget {
  const GiveTakeScreen({super.key});
  @override
  State<GiveTakeScreen> createState() => _GiveTakeState();
}

class _GiveTakeState extends State<GiveTakeScreen> {
  final q = TextEditingController();
  final amt = TextEditingController();
  List<MapEntry<String, String>> hits = [];
  String? uid;
  String name = '';
  num? bal;
  bool busy = false;

  Future<void> _search() async {
    final s = normDigits(q.text.trim());
    if (s.isEmpty) return;
    setState(() {
      busy = true;
      hits = [];
      uid = null;
      bal = null;
    });
    try {
      final u = s.length >= 20 ? s : await uidFromPid(s);
      if (u != null) {
        await _pick(u);
      } else {
        final v = (await ref('profiles').get()).value;
        final l = <MapEntry<String, String>>[];
        if (v is Map) {
          v.forEach((k, x) {
            final n = x is Map ? (x['name'] ?? '').toString() : '';
            if (n.contains(q.text.trim())) l.add(MapEntry(k.toString(), n));
          });
        }
        hits = l.take(30).toList();
        if (hits.isEmpty) toast('لا يوجد نتائج', bad: true);
      }
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _pick(String u) async {
    final p = await prof(u);
    final b = (await ref('wallets/$u/bal').get()).value;
    if (!mounted) return;
    setState(() {
      uid = u;
      name = p.name;
      bal = b is num ? b : 0;
      hits = [];
    });
  }

  int? get _a {
    final v = int.tryParse(normDigits(amt.text.trim()));
    return (v == null || v <= 0 || v > 99999999) ? null : v;
  }

  Future<void> _apply(int sign) async {
    final a = _a;
    if (uid == null || a == null) {
      toast('اكتب مبلغاً صحيحاً', bad: true);
      return;
    }
    final cur = (bal ?? 0).toInt();
    final next = sign > 0 ? cur + a : (cur - a < 0 ? 0 : cur - a);
    try {
      await ref('wallets/$uid/bal').set(next);
      Sfx.start('coin.wav');
      toast(sign > 0 ? 'تمت إضافة $a ✅' : 'تم سحب $a ✅');
      amt.clear();
      await _pick(uid!);
    } catch (e) {
      err(e);
    }
  }

  Future<void> _setExact() async {
    final a = _a;
    if (uid == null || a == null) {
      toast('اكتب الرصيد الجديد', bad: true);
      return;
    }
    try {
      await ref('wallets/$uid/bal').set(a);
      toast('تم تعيين الرصيد ✅');
      amt.clear();
      await _pick(uid!);
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سحب / إعطاء')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('ابحث عن العضو بلقبه أو بالـID، ثم أضف إلى رصيده أو اسحب منه أو عيّن رصيده مباشرة. كل عملية تُنفَّذ فوراً.', style: TextStyle(color: kMu, fontSize: 12.5, height: 1.7)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: q, onSubmitted: (_) => _search(), decoration: const InputDecoration(hintText: 'لقب أو ID'))),
          const SizedBox(width: 8),
          IconButton(onPressed: busy ? null : _search, icon: const Icon(Icons.search)),
        ]),
        ...hits.map((h) => ListTile(leading: UserAvatar(h.key, size: 38), title: Text(h.value), onTap: () => _pick(h.key))),
        if (uid != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            UserAvatar(uid!, size: 48),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            const CoinIcon(size: 18),
            const SizedBox(width: 5),
            Text(fmtN(bal ?? 0), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: context.accent2)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: amt, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'المبلغ')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: AppButton('إعطاء', onPressed: () => _apply(1))),
            const SizedBox(width: 8),
            Expanded(child: AppButton('سحب', kind: 'r', onPressed: () => _apply(-1))),
          ]),
          AppButton('تعيين الرصيد بهذا المبلغ', kind: 'g', onPressed: _setExact),
        ],
      ]),
    );
  }
}

/// «البنك»: سحب مبلغ لرصيدك. السحب فوق 150,000 يصل إشعاره للإمبراطور
class BankScreen extends StatefulWidget {
  const BankScreen({super.key});
  @override
  State<BankScreen> createState() => _BankState();
}

class _BankState extends State<BankScreen> {
  final amt = TextEditingController();
  bool busy = false;

  Future<void> _get() async {
    final a = int.tryParse(normDigits(amt.text.trim()));
    if (a == null || a <= 0 || a > 99999999) {
      toast('اكتب مبلغاً بين 1 و 99,999,999', bad: true);
      return;
    }
    setState(() => busy = true);
    try {
      await ref('wallets/$myUid/bal').set(ServerValue.increment(a));
      Sfx.start('coin.wav');
      toast('🪙 تم سحب ${fmtN(a)} إلى رصيدك');
      if (a > 150000) {
        await ref('bankLog').push().set(<String, Object?>{'by': myUid, 'a': a, 'ts': ServerValue.timestamp});
      }
      amt.clear();
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البنك')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 10),
        const Center(child: CoinIcon(size: 70)),
        const SizedBox(height: 18),
        const Text('ضع المبلغ الذي تريد سحبه:', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        TextField(controller: amt, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: '0')),
        const SizedBox(height: 12),
        AppButton(busy ? '...' : 'الحصول', glow: true, onPressed: busy ? null : _get),
        const SizedBox(height: 14),
        const Text('تنبيه: أي سحب يتجاوز 150,000 يصل إشعاره للإمبراطور.', textAlign: TextAlign.center, style: TextStyle(color: kMu, fontSize: 12.5, height: 1.7)),
      ]),
    );
  }
}
