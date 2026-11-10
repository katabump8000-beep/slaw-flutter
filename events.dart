import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'aljesi.dart';
import 'app_state.dart';
import 'core.dart';
import 'data.dart';
import 'servertime.dart';
import 'widgets.dart';

const List<String> _names = [
  'ناروتو', 'ناروتو أوزوماكي', 'ساسكي', 'ساكورا', 'كاكاشي', 'ايتاتشي', 'مادارا', 'هيناتا', 'جيرايا',
  'لوفي', 'زورو', 'سانجي', 'اس', 'غوكو', 'فيجيتا', 'جوهان', 'ايرين', 'ميكاسا', 'ليفاي',
  'ناتسو', 'غراي', 'ايتشيغو', 'روكيا', 'غون', 'كيلوا', 'تانجيرو', 'نيزوكو', 'ساتورو غوجو', 'يوجي', 'ميغومي',
  'لايت', 'ريوك', 'ديكو', 'باكوغو', 'اينوسكي', 'ساسكي اوتشيها',
];

const List<List<Object>> _evColors = [
  ['أحمر', '#FF3B3B', '🔴'],
  ['أزرق', '#3B7BFF', '🔵'],
  ['أخضر', '#2EE07A', '🟢'],
  ['أصفر', '#FFD83B', '🟡'],
  ['بنفسجي', '#A64BFF', '🟣'],
  ['برتقالي', '#FF8A1F', '🟠'],
];

/// بطاقة فعالية سوداء (تُعرض لرسائل ALJESI التي فيها d={"ev":1,"col":"#RRGGBB"})
class EvCard extends StatefulWidget {
  final String text;
  final String col;
  final Map<String, dynamic>? o; // بطاقة الجيل الجديد (v:2) يرسلها السيرفر
  final int at;
  final bool canCancel;
  final bool cancelLocked;
  final VoidCallback? onCancel;
  final void Function(String act, Map<String, Object?> extra)? onAct;
  const EvCard({super.key, required this.text, this.col = '', this.o, this.at = 0, this.canCancel = false, this.cancelLocked = false, this.onCancel, this.onAct});

  @override
  State<EvCard> createState() => _EvCardState();
}

class _EvCardState extends State<EvCard> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  Timer? _tk;
  final TextEditingController _betC = TextEditingController();

  @override
  void initState() {
    super.initState();
    final o = widget.o;
    final k0 = (o?['k'] ?? '').toString();
    final ex0 = o?['ex'];
    if (o != null && (o['big'] == 'ball' || k0 == 'hs_play' || (ex0 is Map && ex0['ball'] != null))) c.repeat(reverse: true);
    if ((o == null || o['v'] != 2) && hexOk(widget.col)) c.repeat(reverse: true);
    if (o != null && o['cd'] is num) {
      _tk = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tk?.cancel();
    _betC.dispose();
    c.dispose();
    super.dispose();
  }

  static String _ago(int at) {
    if (at <= 0) return 'الآن';
    final s = ((nowMs() - at) / 1000).floor();
    if (s < 60) return 'منذ لحظات';
    if (s < 3600) return 'منذ ${s ~/ 60} دقيقة';
    if (s < 86400) return 'منذ ${s ~/ 3600} ساعة';
    return 'منذ ${s ~/ 86400} يوم';
  }

  Widget _ball(Color col, double size) => AnimatedBuilder(
        animation: c,
        builder: (_, __) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: col,
            boxShadow: [BoxShadow(color: col.withAlpha(200), blurRadius: 18 + 36 * c.value, spreadRadius: 4 + 14 * c.value)],
          ),
        ),
      );

  Widget _decor(String s, Color col) => Text(s, textAlign: TextAlign.center, style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 12.5, height: 1.25));

  Widget _row(String k, String v, Color col, {double size = 14.5}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$k  ', style: TextStyle(color: col, fontWeight: FontWeight.w900)),
            TextSpan(text: v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: size),
        ),
      );

  Widget _cancel(Map<String, dynamic> o) {
    if (!widget.canCancel) return const SizedBox.shrink();
    if (widget.cancelLocked) {
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0x33888888), borderRadius: BorderRadius.circular(12)),
        child: const Text('لم يعد بإمكانك الغاء الفعالية لأنها اصبحت مثيرة لدى الاعضاء!', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 12.5, fontWeight: FontWeight.w700)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        child: GestureDetector(
          onTap: widget.onCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(color: const Color(0x33FF3B3B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFF3B3B))),
            child: const Text('الغاء الفعالية', style: TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w900, fontSize: 13.5)),
          ),
        ),
      ),
    );
  }

  Widget _v2(BuildContext context, Map<String, dynamic> o) {
    final k = (o['k'] ?? '').toString();
    final base = hexOk(o['col']?.toString()) ? hexColor(o['col'].toString()) : const Color(0xFF39FF88);
    final accent = context.accent;
    final edge = (k == 'hs_result' && hexOk(o['hc']?.toString())) ? hexColor(o['hc'].toString()) : ((k == 'result' || k == 'ann') ? accent : base);
    final left = o['cd'] is num ? max(0, (((o['cd'] as num).toInt() - nowMs()) / 1000).ceil()) : 0;
    final kids = <Widget>[];
    if (k == 'intro') {
      kids.add(_decor('❆━━━━━═⏣⊰🎮⊱⏣═━━━━━❆', base));
      kids.add(const SizedBox(height: 8));
      kids.add(ShaderMask(
        shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFF3B3B), Color(0xFFFFD83B), Color(0xFF2EE07A), Color(0xFF3B7BFF), Color(0xFFA64BFF), Color(0xFFFF6FB5)]).createShader(r),
        child: Text((o['title'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white)),
      ));
      kids.add(const SizedBox(height: 6));
      kids.add(Text('الشرح: ${o['how'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, height: 1.55, fontWeight: FontWeight.w700, color: Colors.white)));
      final ex = o['ex'];
      if (ex is Map) {
        kids.add(const SizedBox(height: 6));
        kids.add(Text('مثال عن الفعالية:', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: base)));
        kids.add(Text((ex['a'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, height: 1.5, color: Colors.white70)));
        if (hexOk(ex['ball']?.toString())) kids.add(Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(child: _ball(hexColor(ex['ball'].toString()), 34))));
        if ((ex['big'] ?? '').toString().isNotEmpty) kids.add(Text(ex['big'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 36)));
        kids.add(Text((ex['b'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, height: 1.5, color: Colors.white70)));
      }
      kids.add(const SizedBox(height: 8));
      kids.add(Text('ستبدأ الفعالية بعد:  $left', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Color(0xFF39FF14))));
      kids.add(const SizedBox(height: 4));
      kids.add(_decor('❆━━━━━═⏣⊰🎮⊱⏣═━━━━━❆', base));
    } else if (k == 'round') {
      kids.add(_decor('╗══════════════════╔', base));
      kids.add(const SizedBox(height: 8));
      kids.add(Text((o['q'] ?? '').toString(), textAlign: TextAlign.center, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: base)));
      kids.add(const SizedBox(height: 6));
      final big = (o['big'] ?? '').toString();
      if (big == 'ball') {
        kids.add(Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Center(child: _ball(base, 84))));
      } else if (big == 'img' && (o['img'] ?? '').toString().isNotEmpty) {
        Uint8List? bytes;
        try {
          final raw = o['img'].toString();
          bytes = base64Decode(raw.contains(',') ? raw.split(',').last : raw);
        } catch (_) {}
        kids.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ClipRRect(borderRadius: BorderRadius.circular(14), child: bytes == null ? const SizedBox(height: 60) : Image.memory(bytes, height: 190, fit: BoxFit.contain, gaplessPlayback: true)),
        ));
      } else if (big == 'emoji') {
        kids.add(Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text((o['e'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 80))));
      } else {
        kids.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text((o['w'] ?? '').toString(), textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.4, color: accent, shadows: [Shadow(color: accent.withAlpha(180), blurRadius: 16)])),
        ));
      }
      kids.add(Text('المدة:  ${left.toString().padLeft(2, '0')}', textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: left <= 5 ? const Color(0xFFFF6B6B) : base, fontFeatures: const [FontFeature.tabularFigures()])));
      final first = (o['first'] ?? '').toString();
      // السطر محجوز دائماً حتى لا يتغير ارتفاع البطاقة عند ظهور اسم أول من أجاب (بطاقة ثابتة كأي رسالة)
      kids.add(const SizedBox(height: 4));
      kids.add(SizedBox(height: 22, child: Text(first.isEmpty ? ' ' : 'أول من أجاب:  $first', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFF4CE07A)))));
      kids.add(const SizedBox(height: 4));
      kids.add(_decor('╝══════════════════╚', base));
    } else if (k == 'result' || k == 'ann') {
      kids.add(_decor('╗══════════════════╔', accent));
      if (k == 'ann') kids.add(Text('إنتهت!', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: accent)));
      kids.add(const SizedBox(height: 4));
      final w = (o['winner'] ?? '').toString();
      if (w.isNotEmpty) {
        kids.add(Center(
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent, width: 3), boxShadow: [BoxShadow(color: accent.withAlpha(150), blurRadius: 18)]),
            child: UserAvatar(w, size: 64),
          ),
        ));
        kids.add(const SizedBox(height: 8));
      }
      kids.add(_row('الفائز:', (o['wn'] ?? '').toString(), accent, size: 17));
      kids.add(_row('الجائزة:', '${o['prize'] ?? ''} رصيد', accent));
      if (k == 'ann') {
        kids.add(_row('كمية الفوز:', '${o['wins'] ?? 0}', accent));
        kids.add(_row('كمية الخسارة:', '${o['loss'] ?? 0}', accent));
        kids.add(_row('النقابة:', (o['g'] ?? '').toString(), accent));
      }
      kids.add(_row('الفعالية:', (o['kn'] ?? '').toString(), accent));
      kids.add(_row(k == 'ann' ? 'التوقيت:' : 'الوقت:', _ago(widget.at > 0 ? widget.at : ((o['at'] as num?)?.toInt() ?? 0)), accent));
      if (k == 'result') kids.add(_row('منشأ الفعالية:', (o['bn'] ?? '').toString(), accent));
      kids.add(const SizedBox(height: 6));
      kids.add(_decor('╝══════════════════╚', accent));
    } else if (k == 'hs_lobby') {
      final parts = (o['parts'] is List) ? (o['parts'] as List) : <dynamic>[];
      final joined = parts.any((p) => p is Map && p['u'] == myUid);
      final bet = (o['mb'] as num?)?.toInt() ?? 0;
      kids.add(_decor('╗══════════════════╔', base));
      kids.add(const SizedBox(height: 6));
      kids.add(Text('💛 الحدس', textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: base)));
      kids.add(const SizedBox(height: 4));
      kids.add(const Text('بكل بساطة النظام يرسل لكم 5 قلوب وانتم يجب عليكم تحديد لون القلب الذي تظنون أنه القلب الفائز.. الفعالية تعتمد على حدسك', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.55, color: Colors.white, fontWeight: FontWeight.w700)));
      kids.add(const SizedBox(height: 6));
      kids.add(Text('العدد:  ${parts.length}   •   أقل رهان:  $bet', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: base)));
      kids.add(const SizedBox(height: 6));
      for (final p in parts) {
        if (p is! Map) continue;
        kids.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            UserAvatar(p['u'].toString(), size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text((p['n'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))),
            Text('${p['b']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: base)),
          ]),
        ));
      }
      if (!joined) {
        kids.add(const SizedBox(height: 8));
        kids.add(Row(children: [
          Expanded(
            child: TextField(
              controller: _betC,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              decoration: InputDecoration(isDense: true, hintText: 'رهانك (لا يقل عن $bet)', hintStyle: const TextStyle(fontSize: 12, color: Colors.white54)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => widget.onAct?.call('hsjoin', {'bet': int.tryParse(normDigits(_betC.text.trim())) ?? bet}),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9), decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(10)), child: const Text('مشاركة', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 13))),
          ),
        ]));
      }
      if (widget.canCancel && parts.length >= ((o['min'] as num?)?.toInt() ?? 3)) {
        kids.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Center(
            child: GestureDetector(
              onTap: () => widget.onAct?.call('hsstart', {}),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 9), decoration: BoxDecoration(color: const Color(0xFF2EE07A), borderRadius: BorderRadius.circular(12)), child: const Text('بدأ', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 14))),
            ),
          ),
        ));
      }
      kids.add(_cancel(o));
      kids.add(const SizedBox(height: 4));
      kids.add(_decor('╝══════════════════╚', base));
    } else if (k == 'hs_play') {
      const hearts = <List<Object>>[
        ['💛', 0xFFFFD83B],
        ['💙', 0xFF3B7BFF],
        ['❤️', 0xFFFF3B3B],
        ['💚', 0xFF2EE07A],
        ['💜', 0xFFA64BFF],
      ];
      final order = (o['order'] is List) ? (o['order'] as List).map((x) => (x as num).toInt()).toList() : <int>[0, 1, 2, 3, 4];
      final fade = (o['fade'] is List) ? (o['fade'] as List).map((x) => (x as num).toInt()).toList() : <int>[];
      final picks = (o['picks'] is List) ? (o['picks'] as List) : <dynamic>[];
      final parts = (o['parts'] is List) ? (o['parts'] as List) : <dynamic>[];
      final iAmIn = parts.any((p) => p is Map && p['u'] == myUid);
      final iPicked = picks.any((p) => p is Map && p['u'] == myUid);
      final closed = o['closed'] == true || fade.isNotEmpty;
      Widget heart(int pos) {
        final h = hearts[order[pos]];
        final col = Color(h[1] as int);
        final gone = fade.contains(pos);
        return GestureDetector(
          onTap: (iAmIn && !iPicked && !closed) ? () => widget.onAct?.call('hspick', {'i': pos}) : null,
          child: AnimatedOpacity(
            opacity: gone ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 900),
            child: AnimatedBuilder(
              animation: c,
              builder: (_, __) => Container(
                width: 70,
                height: 70,
                margin: const EdgeInsets.all(4),
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: col.withAlpha(120 + (90 * c.value).toInt()), blurRadius: 14 + 14 * c.value, spreadRadius: 1)]),
                child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(6), child: Text(h[0] as String, style: const TextStyle(fontSize: 44, height: 1.2)))),
              ),
            ),
          ),
        );
      }

      kids.add(_decor('╗══════════════════╔', base));
      kids.add(const SizedBox(height: 6));
      kids.add(const Text('رجاءا من كل مشارك تحديد القلب الذي يحس بأنه القلب الصحيح وليس المزيف (اتبع حدسك!):', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.55, color: Colors.white, fontWeight: FontWeight.w800)));
      kids.add(const SizedBox(height: 8));
      const line = BorderSide(color: Color(0x40FFFFFF), width: 1);
      Widget cell(Widget ch, {bool right = false, bool bottom = false}) => Container(
            height: 92,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border(right: right ? line : BorderSide.none, bottom: bottom ? line : BorderSide.none)),
            child: ch,
          );
      kids.add(Container(
        decoration: BoxDecoration(border: Border.all(color: const Color(0x40FFFFFF)), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Row(children: [Expanded(child: cell(heart(0), right: true, bottom: true)), Expanded(child: cell(heart(1), bottom: true))]),
          cell(heart(2), bottom: true),
          Row(children: [Expanded(child: cell(heart(3), right: true)), Expanded(child: cell(heart(4)))]),
        ]),
      ));
      kids.add(const SizedBox(height: 4));
      kids.add(Text(closed ? 'جاري الكشف عن النتيجة...' : (iAmIn ? (iPicked ? 'تم تسجيل اختيارك ✅' : 'المدة:  $left') : 'المدة:  $left'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: base)));
      if (picks.isNotEmpty) {
        kids.add(const SizedBox(height: 6));
        kids.add(Text('الاختيارات:', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: base)));
        for (final p in picks) {
          if (p is! Map) continue;
          final hi = (p['h'] as num?)?.toInt() ?? 0;
          final pos = order.indexOf(hi);
          kids.add(AnimatedOpacity(
            opacity: fade.contains(pos) ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 900),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                UserAvatar(p['u'].toString(), size: 22),
                const SizedBox(width: 8),
                Text('${p['n']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(hearts[hi][1] as int))),
                const SizedBox(width: 8),
                Text(hearts[hi][0] as String, style: const TextStyle(fontSize: 16)),
              ]),
            ),
          ));
        }
      }
      kids.add(const SizedBox(height: 4));
      kids.add(_decor('╝══════════════════╚', base));
    } else if (k == 'hs_result') {
      final hc = hexOk(o['hc']?.toString()) ? hexColor(o['hc'].toString()) : base;
      final mode = (o['mode'] ?? 'none').toString();
      final winners = (o['winners'] is List) ? (o['winners'] as List) : <dynamic>[];
      kids.add(_decor('╗═════════════════╔', hc));
      kids.add(const SizedBox(height: 6));
      if (mode == 'win' && winners.isNotEmpty) {
        final w0 = winners.first as Map;
        kids.add(Center(child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: hc, width: 3), boxShadow: [BoxShadow(color: hc.withAlpha(150), blurRadius: 16)]), child: UserAvatar(w0['u'].toString(), size: 60))));
        kids.add(const SizedBox(height: 6));
        for (final w in winners) {
          if (w is! Map) continue;
          kids.add(Text.rich(TextSpan(children: [const TextSpan(text: 'الفائز:  ', style: TextStyle(color: Colors.white)), TextSpan(text: '${w['n']}', style: TextStyle(color: hc, fontWeight: FontWeight.w900))]), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)));
        }
        if (((o['wcount'] as num?)?.toInt() ?? 0) > winners.length) kids.add(Text('و ${(o['wcount'] as num).toInt() - winners.length} آخرين', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: Colors.white70)));
        kids.add(_row('اختياره:', (o['he'] ?? '').toString(), hc, size: 15));
        kids.add(_row('الجائزة:', '${o['prize'] ?? 0} رصيد', hc, size: 15));
      } else if (mode == 'refund') {
        kids.add(Text('اختار الجميع القلب نفسه ${o['he'] ?? ''}\nتم إرجاع رصيد كل مشارك', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w800, color: Colors.white)));
      } else {
        kids.add(const Text('حدسكم من سوق الجمعة 🤣\nلا يوجد فائز او شخص اصاب حدسه.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.6, fontWeight: FontWeight.w800, color: Colors.white)));
      }
      kids.add(_row('الوقت:', _ago((o['at'] as num?)?.toInt() ?? 0), hc, size: 14));
      kids.add(_row('منشئ الفعالية:', (o['bn'] ?? '').toString(), hc, size: 14));
      kids.add(const SizedBox(height: 4));
      kids.add(_decor('╝═════════════════╚', hc));
    } else {
      kids.add(Text(widget.text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: base)));
    }
    if (k == 'intro' || k == 'round') kids.add(_cancel(o));
    final box = Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: edge.withAlpha(200), width: 1.6),
        boxShadow: [BoxShadow(color: edge.withAlpha(95), blurRadius: 22, spreadRadius: 1)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids),
    );
    // حركة التقلّص الناعمة لبطاقات الحدس فقط؛ باقي البطاقات بحجم ثابت
    if (k.startsWith('hs_')) return AnimatedSize(duration: const Duration(milliseconds: 700), curve: Curves.easeInOut, alignment: Alignment.topCenter, clipBehavior: Clip.none, child: box);
    return box;
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    if (o != null && o['v'] == 2) return _v2(context, o);
    final has = hexOk(widget.col);

    final col = has ? hexColor(widget.col) : Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: has ? col.withAlpha(200) : const Color(0x88FFFFFF), width: 1.6),
        boxShadow: [BoxShadow(color: (has ? col : Colors.white).withAlpha(80), blurRadius: 20, spreadRadius: 1)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _decor('╗══════════════════╔', has ? col : Colors.white70),
        const SizedBox(height: 6),
        if (has)
          Center(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: c,
                builder: (_, __) => Container(
                  width: 74,
                  height: 74,
                  margin: const EdgeInsets.only(bottom: 12, top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: col,
                    boxShadow: [BoxShadow(color: col.withAlpha(170), blurRadius: 12 + 28 * c.value, spreadRadius: 2 + 10 * c.value)],
                  ),
                ),
              ),
            ),
          ),
        for (final l in widget.text.split('\n'))
          Text(
            l,
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.7,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: l.startsWith('✅') ? const Color(0xFF4CE07A) : col,
            ),
          ),
        const SizedBox(height: 6),
        _decor('╝══════════════════╚', has ? col : Colors.white70),
      ]),
    );
  }
}

/// فعاليات الكتابة / التفكيك / الألوان: يديرها جهاز من بدأها، وتعمل داخل الشات
class EventsHost {
  static final Map<String, EventsHost> _active = {};
  final String gid;
  final String kind;
  final String starter;
  final String eid = newEventId();
  bool stopped = false;
  Completer<String>? _cur;
  String _want = '';
  StreamSubscription<DatabaseEvent>? _sub;
  EventsHost(this.gid, this.kind, this.starter);

  static bool isActive(String gid) => _active.containsKey(gid);

  static void cancel(String gid) {
    final h = _active[gid];
    if (h == null) return;
    h.stopped = true;
    final c = h._cur;
    if (c != null && !c.isCompleted) c.complete('');
  }

  static Future<void> start(String gid, String kind) async {
    if (_active.containsKey(gid)) {
      toast('هناك فعالية قيد التشغيل في هذا القروب', bad: true);
      return;
    }
    final h = EventsHost(gid, kind, myUid);
    _active[gid] = h;
    h._run();
  }

  Future<String> _card(String text, {String col = ''}) async {
    final key = ref('messages/$gid').push().key!;
    try {
      await ref('messages/$gid/$key').set(<String, Object?>{
        'from': myUid,
        'type': 'sys',
        'k': 'bot',
        'f': Session.me.name,
        'text': text,
        'd': jsonEncode(<String, Object?>{'ev': 1, 'eid': eid, if (col.isNotEmpty) 'col': col}),
        'ts': ServerValue.timestamp,
      });
    } catch (_) {}
    return key;
  }

  Future<bool> _canCancel(String uid) async {
    if (uid == starter) return true;
    try {
      final r = await roleOf(uid);
      if (r == 'emp' || r == 'dev') return true;
      return (await ref('groupAdmins/$gid/$uid').get()).exists;
    } catch (_) {
      return false;
    }
  }

  void _onMsg(Map<dynamic, dynamic> v) {
    if (v['type'] != 'text') return;
    final text = (v['text'] ?? '').toString();
    final from = (v['from'] ?? '').toString();
    if (normAr(text) == '.الغاء') {
      _canCancel(from).then((ok) {
        if (ok && !stopped) {
          stopped = true;
          final c = _cur;
          if (c != null && !c.isCompleted) c.complete('');
        }
      });
      return;
    }
    final c = _cur;
    if (c != null && !c.isCompleted && _want.isNotEmpty && normAr(text) == _want) c.complete(from);
  }

  Future<void> _run() async {
    final title = kind == 'type' ? '⌨️ فعالية الكتابة' : (kind == 'scramble' ? '🧩 فعالية التفكيك' : '🎨 فعالية الألوان');
    final how = kind == 'type'
        ? 'النظام يرسل كلمة وأنت تكتبها نفسها.\nمثال: ناروتو = ناروتو'
        : (kind == 'scramble'
            ? 'النظام يرسل كلمة مفككة وأنت تكتبها مجمّعة.\nمثال: ن ا ر و ت و = ناروتو'
            : 'النظام يعرض دائرة مشعة بلون، واكتب اسم اللون.\nمثال: 🔵 = أزرق');
    final first = await _card('╮─❖『 $title 』❖─╭\n$how\nأول من يصل إلى 10 إجابات صحيحة يفوز بـ 40 رصيد 🏆\nلإلغاء الفعالية اكتب: .الغاء\n╰─❖『 بالتوفيق 🍀 』❖─╯');
    _sub = ref('messages/$gid').orderByKey().startAfter(first).onChildAdded.listen((e) {
      final v = e.snapshot.value;
      if (v is Map) _onMsg(v);
    });
    final scores = <String, int>{};
    final rnd = Random();
    final pool = List<String>.of(_names)..shuffle();
    var idx = 0;
    var idle = 0;
    await Future<void>.delayed(const Duration(seconds: 4));
    while (!stopped) {
      String show;
      String col = '';
      if (kind == 'colors') {
        final c = _evColors[rnd.nextInt(_evColors.length)];
        _want = normAr(c[0] as String);
        col = c[1] as String;
        show = 'ما هو هذا اللون: ${c[2]}';
      } else {
        final nm = pool[idx % pool.length];
        idx++;
        _want = normAr(nm);
        if (kind == 'type') {
          show = 'الكلمة: $nm';
        } else {
          final words = nm.split(' ').map((w) => w.split('').join(' ')).toList();
          show = 'الكلمة: ${words.join('   ')}';
        }
      }
      final done = Completer<String>();
      _cur = done;
      final key = await _card(show, col: col);
      String winner = '';
      try {
        winner = await done.future.timeout(const Duration(seconds: 40));
      } catch (_) {
        winner = '';
      }
      _want = '';
      if (stopped) break;
      if (winner.isNotEmpty) {
        idle = 0;
        scores[winner] = (scores[winner] ?? 0) + 1;
        final n = (await prof(winner)).name;
        final sc = scores[winner]!;
        try {
          await ref('messages/$gid/$key/text').set('$show\n✅ $n هو من أجاب — $sc/10');
        } catch (_) {}
        if (sc >= 10) {
          await botSay(gid, '🎊 فاز $n بـ $title! 🏆\n💰 40 رصيد أُضيفت إلى رصيده', d: jsonEncode(<String, Object?>{'win': winner, 'amt': 40, 'eid': eid}));
          break;
        }
      } else {
        idle++;
        try {
          await ref('messages/$gid/$key/text').set('$show\n⌛ انتهى الوقت');
        } catch (_) {}
        if (idle >= 2) {
          await botSay(gid, '🛑 تم إلغاء الفعالية لعدم التفاعل.', d: jsonEncode(<String, Object?>{'eid': eid}));
          break;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (stopped) await botSay(gid, '🛑 تم إلغاء الفعالية.', d: jsonEncode(<String, Object?>{'eid': eid}));
    await markEventEnd(gid, eid);
    await _sub?.cancel();
    _active.remove(gid);
  }
}
