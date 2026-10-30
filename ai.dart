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

/// مخالفة: تقييد تصاعدي (5د، 10د، 2س، 10س، ثم 12س) + إنقاص درجة الفخر 4 أو 5 أو 6
Future<String> strike(String reason) async {
  if (Session.isDev) return '0 دقائق';
  const mins = [5, 10, 120, 600, 720];
  var n = 0;
  try {
    final s = await ref('mod/$myUid').get();
    final v = s.value;
    if (v is Map) n = (v['n'] as num?)?.toInt() ?? 0;
  } catch (_) {}
  final dur = mins[n >= 5 ? 4 : n];
  final until = DateTime.now().millisecondsSinceEpoch + dur * 60000;
  try {
    await ref('mod/$myUid').set(<String, Object?>{'n': n + 1, 'until': until});
  } catch (_) {}
  try {
    final p = await ref('pride/$myUid').get();
    var cur = 100;
    if (!p.exists) {
      await ref('pride/$myUid').set(100);
    } else if (p.value is num) {
      cur = (p.value as num).toInt();
    }
    if (cur > 0) await ref('pride/$myUid').set(max(0, cur - (4 + Random().nextInt(3))));
  } catch (_) {}
  return dur >= 60 ? '${dur ~/ 60} ساعة' : '$dur دقائق';
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
  'كس', 'كسك', 'كسم', 'كسمك', 'طيز', 'طيزك', 'زب', 'زبي', 'زبك', 'نيك', 'انيك', 'نيكني', 'عرص', 'عرصه', 'خرا',
};
const List<String> _badPart = [
  'شرموط', 'شراميط', 'منيك', 'منيوك', 'قحبه', 'قحاب', 'متناك', 'كسمك', 'كسختك', 'كساختك', 'كسامك', 'fuck',
];

/// true = فيها كلمة غير لائقة (كلب ومعاق وأمثالها مسموحة)
bool badWord(String text) {
  final t = _nb(text);
  for (final w in t.split(RegExp(r'[^\u0621-\u064Aa-zA-Z0-9]+'))) {
    if (w.isEmpty) continue;
    if (_badExact.contains(w)) return true;
    for (final b in _badPart) {
      if (w.contains(_nb(b))) return true;
    }
  }
  return false;
}

/// عقوبة كلمة غير لائقة: تقييد 10 دقائق وخصم 5 من درجة الفخر
Future<String> strikeWord() async {
  if (Session.isDev) return '0 دقائق';
  var n = 0;
  try {
    final s = await ref('mod/$myUid').get();
    final v = s.value;
    if (v is Map) n = (v['n'] as num?)?.toInt() ?? 0;
  } catch (_) {}
  final until = DateTime.now().millisecondsSinceEpoch + 10 * 60000;
  try {
    await ref('mod/$myUid').set(<String, Object?>{'n': n + 1, 'until': until});
  } catch (_) {}
  try {
    final p = await ref('pride/$myUid').get();
    var cur = 100;
    if (!p.exists) {
      await ref('pride/$myUid').set(100);
    } else if (p.value is num) {
      cur = (p.value as num).toInt();
    }
    if (cur > 0) await ref('pride/$myUid').set(max(0, cur - 5));
  } catch (_) {}
  return '10 دقائق';
}
