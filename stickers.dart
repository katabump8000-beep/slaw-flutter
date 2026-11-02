import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data.dart';
import 'widgets.dart';

/// زر «سرقة الملصق» عند الضغط المطوّل على ملصق. لو كان الملصق مسروقاً قبل ذلك يظهر اسم صانعه فوق الزر
class StealStickerButton extends StatefulWidget {
  final String sid;
  final VoidCallback close;
  const StealStickerButton({super.key, required this.sid, required this.close});

  @override
  State<StealStickerButton> createState() => _StealState();
}

class _StealState extends State<StealStickerButton> {
  String owner = '';
  String maker = '';
  String data = '';
  bool mine = false;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = (await ref('stickers/${widget.sid}').get()).value;
      if (v is Map) {
        owner = (v['u'] ?? '').toString();
        maker = (v['o'] ?? '').toString();
        data = (v['d'] ?? '').toString();
      }
      final h = await ref('myStickers/$myUid/${widget.sid}').get();
      mine = h.exists || owner == myUid;
    } catch (_) {}
    if (mounted) setState(() => loaded = true);
  }

  Future<void> _steal() async {
    widget.close();
    try {
      final sid2 = ref('stickers').push().key!;
      await db.ref().update(<String, Object?>{
        'stickers/$sid2': <String, Object?>{'u': myUid, 'd': data, 'o': maker.isNotEmpty ? maker : owner},
        'myStickers/$myUid/$sid2': true,
      });
      toast('تمت سرقة الملصق 🕵️');
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded || mine || data.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (maker.isNotEmpty || owner.isNotEmpty)
        FutureBuilder<Prof>(
          future: prof(maker.isNotEmpty ? maker : owner),
          builder: (c, p) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(maker.isNotEmpty ? 'مسروق من: ${p.data?.name ?? '...'}' : 'صانع الملصق: ${p.data?.name ?? '...'}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFD54A), fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ),
      AppButton('🕵️ سرقة الملصق', kind: 'g', onPressed: _steal),
    ]);
  }
}
