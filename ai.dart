import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

import 'app_state.dart';
import 'config.dart';
import 'data.dart';

Future<String?> _gemini(List<Map<String, Object?>> parts, {int maxTokens = 20}) async {
  try {
    final content = <Map<String, Object?>>[];
    for (final p in parts) {
      if (p['text'] != null) {
        content.add(<String, Object?>{'type': 'text', 'text': p['text']});
      } else if (p['inline_data'] is Map) {
        final d = p['inline_data'] as Map;
        content.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{'url': 'data:${d['mime_type']};base64,${d['data']}'},
        });
      }
    }
    final body = jsonEncode(<String, Object?>{
      'model': kAiModel,
      'messages': [
        <String, Object?>{'role': 'user', 'content': content}
      ],
      'max_tokens': maxTokens < 16 ? 16 : maxTokens,
      'temperature': 0,
    });
    final r = await http
        .post(
          Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $kOpenRouterKey',
            'HTTP-Referer': 'https://github.com',
            'X-Title': 'FIR',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final ch = (j['choices'] as List?)?.first;
    final t = ((ch['message'] as Map)['content'])?.toString();
    return t?.trim();
  } catch (_) {
    return null;
  }
}

/// true = غير لائقة، false = سليمة، null = تعذر الفحص
Future<bool?> imageUnsafe(Uint8List bytes, {String mime = 'image/jpeg'}) async {
  final t = await _gemini([
    {
      'text': 'You are a strict content moderator for a chat app that teenagers use. '
          'Reply with exactly one word: UNSAFE if the image contains nudity, sexual or pornographic content, '
          'graphic gore, or extreme violence. Otherwise reply SAFE.'
    },
    {
      'inline_data': {'mime_type': mime, 'data': base64Encode(bytes)}
    },
  ], maxTokens: 8);
  if (t == null) return null;
  return t.toUpperCase().contains('UNSAFE');
}

/// يحوّل اسم شخصية عربي إلى لاتيني ثم يجلب صورتها من AniList
Future<String?> charImage(String arabicName) async {
  try {
    final en = await _gemini([
      {
        'text': 'Transliterate this Arabic anime or manga character name to its common English spelling. '
            'Reply with only the English name, or NONE if it is not a known character: $arabicName'
      }
    ], maxTokens: 20);
    if (en == null || en.toUpperCase().contains('NONE') || en.length > 40) return null;
    final r = await http
        .post(
          Uri.parse('https://graphql.anilist.co'),
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({
            'query': 'query(\$s:String){Character(search:\$s){image{large}}}',
            'variables': {'s': en},
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    final u = (((jsonDecode(r.body)['data'] ?? {})['Character'] ?? {})['image'] ?? {})['large']?.toString();
    return (u != null && u.length <= 290) ? u : null;
  } catch (_) {
    return null;
  }
}

/// نتيجة عقوبة: [text] يُعرض للمستخدم، و[warn] = بطاقة تحذير فقط (للرتب العالية في أول مخالفة)
class PunishResult {
  final String text;
  final bool warn;
  const PunishResult(this.text, this.warn);
}

String _durText(int mins) {
  if (mins >= 1440) return '${mins ~/ 1440} يوم';
  if (mins >= 60) return '${mins ~/ 60} ساعة';
  if (mins == 1) return 'دقيقة';
  return '$mins دقائق';
}

/// kind: mild (كلمة خفيفة) | severe (كلمة شنيعة) | image (صورة) | spam
/// الأعضاء: خفيفة 5 دقائق، شنيعة 7 ساعات، صورة 30 دقيقة، سبام 10 دقائق، وتتضاعف عند كل تكرار من النوع نفسه.
/// الرتب العالية (مطور/إمبراطور): تحذير، ثم دقيقة، ثم 5 دقائق، ثم 30 دقيقة.
/// يزيلها المطور بزر «تحرير وقت الحظر» من الملف التعريفي فتبدأ العدّ من جديد.
Future<PunishResult> applyPunish(String kind) async {
  Map<String, Object?> cur = <String, Object?>{};
  try {
    final v = (await ref('mod/$myUid').get()).value;
    if (v is Map) {
      v.forEach((k, x) {
        if (x is num) cur[k.toString()] = x.toInt();
      });
    }
  } catch (_) {}
  final n = (cur['n'] as int?) ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  var dur = 0;
  var warn = false;
  final key = {'mild': 'a', 'severe': 'b', 'image': 'i', 'spam': 's'}[kind] ?? 'a';
  if (Session.isDev) {
    const tiers = [0, 1, 5, 30];
    dur = tiers[n >= 3 ? 3 : n];
    warn = dur == 0;
  } else {
    const base = {'mild': 5, 'severe': 420, 'image': 30, 'spam': 10};
    final c = (cur[key] as int?) ?? 0;
    dur = (base[kind] ?? 5) * pow(2, c > 12 ? 12 : c).toInt();
    if (dur > 20160) dur = 20160;
  }
  cur['n'] = n + 1;
  cur[key] = ((cur[key] as int?) ?? 0) + 1;
  cur['until'] = dur == 0 ? 0 : now + dur * 60000;
  try {
    await ref('mod/$myUid').set(cur);
  } catch (_) {}
  if (!Session.isDev) {
    try {
      final p = await ref('pride/$myUid').get();
      var pr = 100;
      if (!p.exists) {
        await ref('pride/$myUid').set(100);
      } else if (p.value is num) {
        pr = (p.value as num).toInt();
      }
      if (pr > 0) await ref('pride/$myUid').set(max(0, pr - (kind == 'severe' ? 6 : 4 + Random().nextInt(2))));
    } catch (_) {}
  }
  if (warn) {
    return const PunishResult('مرحباً أيها صاحب الرتبة العالية، رجاءً لا تخالف القوانين، وإلا سيتم حظرك من الشات لمدة دقيقة في المرة القادمة.', true);
  }
  return PunishResult('تم تقييدك من الشات لمدة ${_durText(dur)}', false);
}

Future<int> prideOf(String uid) async {
  try {
    final r = await roleOf(uid);
    if (r == 'emp' || r == 'dev') return 100;
    final s = await ref('pride/$uid').get();
    return s.value is num ? (s.value as num).toInt() : 100;
  } catch (_) {
    return 100;
  }
}

/// كاشف السبام: 9 رسائل خلال 8 ثوانٍ
final List<int> _sent = <int>[];
bool spamHit() {
  final n = DateTime.now().millisecondsSinceEpoch;
  _sent.add(n);
  _sent.removeWhere((t) => n - t > 8000);
  if (_sent.length >= 9) {
    _sent.clear();
    return true;
  }
  return false;
}

/// فحص صورة بصيغة data:image
Future<bool?> imageDataUnsafe(String dataUrl) async {
  try {
    final i = dataUrl.indexOf(',');
    if (i < 0) return null;
    return await imageUnsafe(base64Decode(dataUrl.substring(i + 1)));
  } catch (_) {
    return null;
  }
}

// ---------- كلمات مخالفة (حظر فوري قبل الإرسال) ----------
String _nb(String s) {
  var t = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
  t = t
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .toLowerCase();
  return t.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
}

const Set<String> _badExact = {
  'كس', 'كسك', 'كسم', 'كسمك', 'طيز', 'طيزك', 'زب', 'زبي', 'زبك', 'نيك', 'انيك', 'نيكني', 'عرص', 'عرصه',
};
// إهانات خفيفة (عقوبتها أخف)
const Set<String> _mildExact = {'كلب', 'كلاب', 'حمار', 'حمير', 'خرا', 'خره', 'تيس', 'حيوان', 'كلبه'};
const List<String> _badPart = [
  'شرموط', 'شراميط', 'منيك', 'منيوك', 'قحبه', 'قحاب', 'متناك', 'كسمك', 'كسختك', 'كساختك', 'كسامك', 'fuck',
];

/// 0 = نظيف، 1 = إهانة خفيفة، 2 = كلمة شنيعة
int badLevel(String text) {
  final t = _nb(text);
  var lv = 0;
  for (final w in t.split(RegExp(r'[^\u0621-\u064Aa-zA-Z0-9]+'))) {
    if (w.isEmpty) continue;
    if (_badExact.contains(w)) return 2;
    for (final b in _badPart) {
      if (w.contains(_nb(b))) return 2;
    }
    if (_mildExact.contains(w)) lv = 1;
  }
  return lv;
}

bool badWord(String text) => badLevel(text) > 0;

/// تقييد 30 ثانية عند تكرار المنشن (@) بسرعة
Future<void> mentionLock() async {
  Map<String, Object?> cur = <String, Object?>{};
  try {
    final v = (await ref('mod/$myUid').get()).value;
    if (v is Map) {
      v.forEach((k, x) {
        if (x is num) cur[k.toString()] = x.toInt();
      });
    }
  } catch (_) {}
  cur['n'] = ((cur['n'] as int?) ?? 0) + 1;
  cur['until'] = DateTime.now().millisecondsSinceEpoch + 30000;
  try {
    await ref('mod/$myUid').set(cur);
  } catch (_) {}
}
