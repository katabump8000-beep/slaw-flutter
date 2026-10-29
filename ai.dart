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
    final body = jsonEncode(<String, Object?>{
      'contents': [
        {
          'role': 'user',
          'parts': parts
        }
      ],
      'generationConfig': {'temperature': 0, 'maxOutputTokens': maxTokens},
    });
    // مفاتيح AQ. هي مفاتيح Vertex AI السريعة، ومفاتيح AIza هي مفاتيح AI Studio
    final urls = kGeminiKey.startsWith('AQ.')
        ? <String>[
            'https://aiplatform.googleapis.com/v1/publishers/google/models/$kGeminiModel:generateContent?key=$kGeminiKey',
            'https://generativelanguage.googleapis.com/v1beta/models/$kGeminiModel:generateContent?key=$kGeminiKey',
          ]
        : <String>[
            'https://generativelanguage.googleapis.com/v1beta/models/$kGeminiModel:generateContent?key=$kGeminiKey',
            'https://aiplatform.googleapis.com/v1/publishers/google/models/$kGeminiModel:generateContent?key=$kGeminiKey',
          ];
    http.Response? r;
    for (final u in urls) {
      try {
        final x = await http.post(Uri.parse(u), headers: {'Content-Type': 'application/json'}, body: body).timeout(const Duration(seconds: 18));
        if (x.statusCode == 200) {
          r = x;
          break;
        }
      } catch (_) {}
    }
    if (r == null) return null;
    final j = jsonDecode(r.body);
    if (j is Map && j['promptFeedback'] is Map && (j['promptFeedback'] as Map)['blockReason'] != null) return 'UNSAFE';
    final c = (j['candidates'] as List?)?.first;
    final t = ((c['content'] as Map)['parts'] as List).first['text']?.toString();
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
    final s = await ref('pride/$uid').get();
    return s.value is num ? (s.value as num).toInt() : 100;
  } catch (_) {
    return 100;
  }
}

/// كاشف السبام: 7 رسائل خلال 8 ثوانٍ
final List<int> _sent = <int>[];
bool spamHit() {
  final n = DateTime.now().millisecondsSinceEpoch;
  _sent.add(n);
  _sent.removeWhere((t) => n - t > 8000);
  if (_sent.length >= 7) {
    _sent.clear();
    return true;
  }
  return false;
}
