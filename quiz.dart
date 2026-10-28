import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'aljesi.dart';
import 'app_state.dart';
import 'core.dart';
import 'crop.dart';
import 'data.dart';
import 'home.dart';
import 'widgets.dart';

// ---------- سقف الأرباح اليومي للألعاب السريعة ----------
Future<int> quizRoom() async {
  try {
    final s = await ref('qDaily/$myUid').get();
    final v = s.value;
    if (v is Map && v['d'] == dayKey()) return max(0, 300 - ((v['n'] as num?)?.toInt() ?? 0));
  } catch (_) {}
  return 300;
}

Future<void> _quizPaid(int amount) async {
  try {
    final s = await ref('qDaily/$myUid').get();
    final v = s.value;
    var n = 0;
    if (v is Map && v['d'] == dayKey()) n = (v['n'] as num?)?.toInt() ?? 0;
    await ref('qDaily/$myUid').set(<String, Object?>{'d': dayKey(), 'n': min(300, n + amount)});
  } catch (_) {}
}

const List<List<String>> _flags = [
  ['🇸🇦', 'السعودية'], ['🇪🇬', 'مصر'], ['🇯🇵', 'اليابان'], ['🇫🇷', 'فرنسا'], ['🇩🇪', 'ألمانيا'],
  ['🇧🇷', 'البرازيل'], ['🇹🇷', 'تركيا'], ['🇲🇦', 'المغرب'], ['🇮🇹', 'إيطاليا'], ['🇪🇸', 'إسبانيا'],
  ['🇺🇸', 'أمريكا'], ['🇰🇷', 'كوريا الجنوبية'], ['🇮🇳', 'الهند'], ['🇦🇷', 'الأرجنتين'], ['🇨🇦', 'كندا'],
  ['🇷🇺', 'روسيا'], ['🇦🇪', 'الإمارات'], ['🇯🇴', 'الأردن'], ['🇱🇧', 'لبنان'], ['🇸🇾', 'سوريا'],
  ['🇮🇶', 'العراق'], ['🇩🇿', 'الجزائر'], ['🇹🇳', 'تونس'], ['🇶🇦', 'قطر'], ['🇰🇼', 'الكويت'],
];
const List<String> _phrases = [
  'ناروتو يحلم أن يصبح هوكاجي', 'لوفي يريد أن يصبح ملك القراصنة', 'غوكو يتدرب ليصبح أقوى',
  'كاكاشي ينسخ الجتسو بعينه', 'إيرين يحارب من أجل الحرية', 'ليفاي أقوى جندي في الإنسانية',
];
const List<List<Object>> _colors = [
  ['أحمر', Color(0xFFFF4D4D)], ['أزرق', Color(0xFF4D8DFF)], ['أخضر', Color(0xFF4DFF88)],
  ['أصفر', Color(0xFFFFE04D)], ['بنفسجي', Color(0xFFB34DFF)],
];

/// الألعاب السريعة: أعلام / كتابة / ألوان (مكافآت صغيرة + انتظار 3 دقائق + سقف يومي 300)
class QuickQuizScreen extends StatefulWidget {
  final String gid;
  final String kind;
  const QuickQuizScreen({super.key, required this.gid, required this.kind});

  @override
  State<QuickQuizScreen> createState() => _QuickQuizScreenState();
}

class _QuickQuizScreenState extends State<QuickQuizScreen> {
  String info = '';
  int round = 0;
  int ok = 0;
  bool locked = false;
  bool finished = false;
  bool blocked = false;
  final Random rnd = Random();
  late List<List<String>> flagQs = (List<List<String>>.of(_flags)..shuffle()).take(5).toList();
  List<String> flagOpts = [];
  List<Object> colorWord = [];
  List<Object> colorInk = [];
  final String phrase = _phrases[Random().nextInt(_phrases.length)];
  final TextEditingController tc = TextEditingController();
  int t0 = 0;
  Timer? timeout;

  String get title => widget.kind == 'flags' ? '🏳️ تخمين الأعلام' : (widget.kind == 'typing' ? '⌨️ سرعة الكتابة' : '🎨 لعبة الألوان');
  int get rounds => widget.kind == 'flags' ? 5 : 6;

  @override
  void initState() {
    super.initState();
    final left = 180000 - (DateTime.now().millisecondsSinceEpoch - (prefs.getInt('cd_${widget.kind}') ?? 0));
    if (left > 0) {
      blocked = true;
      info = 'انتظر ${(left / 1000).ceil()} ثانية قبل إعادة اللعب';
    } else if (widget.kind != 'typing') {
      _next();
    } else {
      info = 'اكتب الجملة بأسرع ما يمكن';
    }
  }

  @override
  void dispose() {
    timeout?.cancel();
    super.dispose();
  }

  void _next() {
    if (round >= rounds) {
      _end();
      return;
    }
    setState(() {
      locked = false;
      info = 'الجولة ${round + 1}/$rounds';
      if (widget.kind == 'flags') {
        final q = flagQs[round];
        final others = (List<List<String>>.of(_flags)..removeWhere((x) => x[1] == q[1])..shuffle()).take(3).map((x) => x[1]).toList();
        flagOpts = [q[1], ...others]..shuffle();
      } else {
        colorWord = _colors[rnd.nextInt(_colors.length)];
        final rest = _colors.where((x) => x[0] != colorWord[0]).toList();
        colorInk = rest[rnd.nextInt(rest.length)];
      }
    });
  }

  Future<void> _end({int? typingPay}) async {
    if (finished) return;
    finished = true;
    prefs.setInt('cd_${widget.kind}', DateTime.now().millisecondsSinceEpoch);
    final raw = typingPay ?? (widget.kind == 'flags' ? ok * 8 : ok * 4);
    final room = await quizRoom();
    final pay = min(raw, room);
    var m = pay > 0 ? '🎉 ربح $pay رصيد' : (raw > 0 ? '🔒 وصلت للسقف اليومي للألعاب' : '💥 لم يربح');
    if (pay > 0) {
      try {
        await addBalRetry(pay);
        await _quizPaid(pay);
      } catch (_) {
        m = 'تعذر إضافة الربح';
      }
    }
    if (mounted) setState(() => info = m);
    await botSay(widget.gid, '$title — ${Session.me.name}\n$m');
  }

  void _answer(bool right) {
    if (locked) return;
    locked = true;
    if (right) ok++;
    round++;
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _next();
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final w = <Widget>[Center(child: Text(info, style: TextStyle(color: context.accent2, fontWeight: FontWeight.w700)))];
    if (!blocked && !finished) {
      if (widget.kind == 'flags' && round < 5) {
        w.add(Center(child: Text(flagQs[round][0], style: const TextStyle(fontSize: 90))));
        for (final o in flagOpts) {
          w.add(Padding(padding: const EdgeInsets.only(top: 10), child: AppButton(o, kind: 'g', onPressed: () => _answer(o == flagQs[round][1]))));
        }
      } else if (widget.kind == 'colors' && round < 6 && colorWord.isNotEmpty) {
        w.add(Center(child: Text(colorWord[0] as String, style: TextStyle(fontSize: 54, fontWeight: FontWeight.w800, color: colorInk[1] as Color))));
        for (final c in List<List<Object>>.of(_colors)..shuffle()) {
          w.add(Padding(padding: const EdgeInsets.only(top: 10), child: AppButton(c[0] as String, kind: 'g', onPressed: () => _answer(c[0] == colorInk[0]))));
        }
      } else if (widget.kind == 'typing') {
        w.add(Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: kLine), borderRadius: BorderRadius.circular(12)),
          child: Text(t0 == 0 ? 'اضغط ابدأ' : phrase, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20)),
        ));
        if (t0 == 0) {
          w.add(AppButton('ابدأ', onPressed: () {
            setState(() => t0 = DateTime.now().millisecondsSinceEpoch);
            timeout = Timer(const Duration(seconds: 40), () {
              if (!finished) _end(typingPay: 0);
            });
          }));
        } else {
          w.add(TextField(
            controller: tc,
            autofocus: true,
            onChanged: (v) {
              if (finished) return;
              if (normAr(v) == normAr(phrase)) {
                final s = (DateTime.now().millisecondsSinceEpoch - t0) / 1000;
                setState(() => info = '⏱ ${s.toStringAsFixed(1)} ثانية');
                _end(typingPay: s <= 8 ? 25 : (s <= 15 ? 12 : 0));
              }
            },
          ));
        }
      }
    }
    return Scaffold(appBar: AppBar(title: Text(title)), body: ListView(padding: const EdgeInsets.all(18), children: w));
  }
}

// ---------- فعاليتا الحيوانات وتخمين الشخصيات (يديرهما جهاز من بدأ الفعالية) ----------
class _Item {
  final String n;
  final String d;
  _Item(this.n, this.d);
}

class QuizHost {
  static final Map<String, QuizHost> _active = {};
  final String gid;
  final String cat;
  final List<_Item> items;
  bool stopped = false;
  StreamSubscription<DatabaseEvent>? _sub;
  QuizHost(this.gid, this.cat, this.items);

  static Future<void> start(BuildContext ctx, String gid, String cat) async {
    if (_active.containsKey(gid)) {
      toast('هناك فعالية قيد التشغيل في هذا القروب', bad: true);
      return;
    }
    final list = <_Item>[];
    try {
      final s = await ref('quizImgs/$cat').get();
      final v = s.value;
      if (v is Map) {
        v.forEach((k, x) {
          if (x is Map) list.add(_Item((x['n'] ?? '').toString(), (x['d'] ?? '').toString()));
        });
      }
    } catch (e) {
      err(e);
      return;
    }
    if (list.isEmpty) {
      await botSay(gid, 'لا توجد صور لهذه الفعالية بعد. يضيفها المطورون من «الفعاليات ⚙️».');
      return;
    }
    final h = QuizHost(gid, cat, list);
    _active[gid] = h;
    h.run();
  }

  Future<void> run() async {
    final title = cat == 'animals' ? 'فعالية الحيوانات 🐾' : 'تخمين الشخصيات 🎭';
    await botSay(gid, '🎉 بدأت $title!\nأول من يصل إلى 10 إجابات صحيحة يفوز.\nلكل صورة 40 ثانية.');
    final order = List<_Item>.of(items)..shuffle();
    final scores = <String, int>{};
    var idx = 0;
    var idle = 0;
    while (!stopped) {
      final it = order[idx % order.length];
      idx++;
      final key = ref('messages/$gid').push().key!;
      try {
        await ref('messages/$gid/$key').set(<String, Object?>{
          'from': myUid,
          'type': 'sys',
          'k': 'bot',
          'f': Session.me.name,
          'text': '❓ من هذا؟ لديكم 40 ثانية ⏱',
          'img': it.d,
          'ts': ServerValue.timestamp,
        });
      } catch (_) {
        break;
      }
      final done = Completer<String>();
      final want = normAr(it.n);
      _sub?.cancel();
      _sub = ref('messages/$gid').orderByKey().startAfter(key).onChildAdded.listen((e) {
        final v = e.snapshot.value;
        if (v is! Map || done.isCompleted) return;
        if (v['type'] != 'text') return;
        final from = (v['from'] ?? '').toString();
        if (normAr((v['text'] ?? '').toString()) == want) done.complete(from);
      });
      String? winner;
      try {
        winner = await done.future.timeout(const Duration(seconds: 40));
      } catch (_) {
        winner = null;
      }
      await _sub?.cancel();
      if (stopped) break;
      if (winner != null) {
        idle = 0;
        scores[winner] = (scores[winner] ?? 0) + 1;
        final n = (await prof(winner)).name;
        await botSay(gid, '✅ الإجابة الصحيحة: ${it.n}\n🏆 $n — ${scores[winner]} من 10');
        if (scores[winner]! >= 10) {
          await botSay(gid, '🎊 فاز $n بـ $title! 🏆', d: jsonEncode({'win': winner}));
          break;
        }
      } else {
        idle++;
        await botSay(gid, '⌛ انتهى الوقت! الإجابة: ${it.n}');
        if (idle >= 2) {
          await botSay(gid, '🛑 تم إلغاء الفعالية لعدم التفاعل.');
          break;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    _sub?.cancel();
    _active.remove(gid);
  }
}

// ---------- الفعاليات ⚙️ (للمطورين): رفع الصور وأسمائها ----------
class QuizAdminScreen extends StatefulWidget {
  const QuizAdminScreen({super.key});

  @override
  State<QuizAdminScreen> createState() => _QuizAdminScreenState();
}

class _QuizAdminScreenState extends State<QuizAdminScreen> {
  String cat = 'animals';
  Map<String, Map<String, dynamic>> data = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final s = await ref('quizImgs/$cat').get();
      final v = s.value;
      data = {};
      if (v is Map) {
        v.forEach((k, x) {
          if (x is Map) data[k.toString()] = Map<String, dynamic>.from(x);
        });
      }
    } catch (e) {
      err(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _add() async {
    if (data.length >= 200) {
      toast('الحد الأقصى 200 صورة', bad: true);
      return;
    }
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null || !mounted) return;
      final b = await x.readAsBytes();
      if (!mounted) return;
      final d = await cropImage(context, b, out: const [200, 160, 128, 100], limit: 24000, round: false, title: 'قص الصورة', ratio: 1);
      if (d == null || !mounted) return;
      final nm = TextEditingController();
      final name = await showAppSheet<String>(context, (sc) => [
            Text(cat == 'animals' ? 'اسم الحيوان' : 'اسم الشخصية', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(d.substring(d.indexOf(',') + 1)), height: 160, fit: BoxFit.cover)),
            TextField(controller: nm, maxLength: 40, decoration: const InputDecoration(hintText: 'اكتب الاسم الصحيح')),
            AppButton('حفظ', onPressed: () => Navigator.of(sc).pop(nm.text.trim())),
          ]);
      if (name == null || name.isEmpty) return;
      await ref('quizImgs/$cat').push().set(<String, Object?>{'n': name, 'd': d});
      await _load();
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = data.keys.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('الفعاليات ⚙️')),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: AppButton('حيوانات', kind: cat == 'animals' ? 'main' : 'g', onPressed: () {
              cat = 'animals';
              _load();
            })),
            const SizedBox(width: 10),
            Expanded(child: AppButton('شخصيات', kind: cat == 'chars' ? 'main' : 'g', onPressed: () {
              cat = 'chars';
              _load();
            })),
          ]),
        ),
        Text('${data.length} / 200', style: const TextStyle(color: kMu)),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : keys.isEmpty
                  ? const Center(child: Text('لا توجد صور بعد. اضغط + لإضافة صورة', style: TextStyle(color: kMu)))
                  : GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: .85),
                      itemCount: keys.length,
                      itemBuilder: (c, i) {
                        final k = keys[i];
                        final Uint8List? b = dataUrlBytesLocal((data[k]!['d'] ?? '').toString());
                        return GestureDetector(
                          onLongPress: () async {
                            try {
                              await ref('quizImgs/$cat/$k').remove();
                              await _load();
                            } catch (e) {
                              err(e);
                            }
                          },
                          child: Column(children: [
                            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: b == null ? const SizedBox() : Image.memory(b, fit: BoxFit.cover, width: double.infinity))),
                            Text((data[k]!['n'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          ]),
                        );
                      },
                    ),
        ),
        const Padding(padding: EdgeInsets.all(8), child: Text('اضغط مطولاً على صورة لحذفها', style: TextStyle(color: kMu, fontSize: 11))),
      ]),
    );
  }
}

Uint8List? dataUrlBytesLocal(String d) {
  try {
    final i = d.indexOf(',');
    return i < 0 ? null : base64Decode(d.substring(i + 1));
  } catch (_) {
    return null;
  }
}
