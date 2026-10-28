import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import 'app_state.dart';
import 'widgets.dart';

/// شاشة قص الصورة: تحرّك وتكبّر ثم تحفظ. ترجع data:image/jpeg أو null عند الإلغاء.
/// out: أحجام الإخراج بالترتيب (إذا كبر الناتج عن limit نجرب الحجم التالي)
Future<String?> cropImage(
  BuildContext context,
  Uint8List bytes, {
  List<int> out = const [256],
  int limit = 29000,
  bool round = true,
  String title = 'قص الصورة',
  double ratio = 1,
}) {
  return Navigator.of(context).push<String>(MaterialPageRoute<String>(
    fullscreenDialog: true,
    builder: (_) => CropScreen(
      bytes: bytes,
      out: out,
      limit: limit,
      round: round,
      title: title,
      ratio: ratio,
    ),
  ));
}

class CropScreen extends StatefulWidget {
  final Uint8List bytes;
  final List<int> out;
  final int limit;
  final bool round;
  final String title;
  final double ratio;

  const CropScreen({
    super.key,
    required this.bytes,
    required this.out,
    required this.limit,
    required this.round,
    required this.title,
    required this.ratio,
  });

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final GlobalKey _key = GlobalKey();
  final TransformationController _tc = TransformationController();
  ui.Image? _im;
  bool _failed = false;
  bool _busy = false;
  bool _inited = false;
  double _side = 0;
  double _h = 0;
  double _cw = 0;
  double _ch = 0;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _tc.addListener(() {
      final z0 = _tc.value.getMaxScaleOnAxis();
      final z = z0 < 1 ? 1.0 : (z0 > 4 ? 4.0 : z0);
      if ((z - _zoom).abs() > .001 && mounted) setState(() => _zoom = z);
    });
    _decode();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(
        widget.bytes,
        targetWidth: 1200,
        allowUpscaling: false,
      );
      final fi = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _im = fi.image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _setZoom(double z2) {
    final m = _tc.value;
    final z = m.getMaxScaleOnAxis();
    final tx = m.storage[12];
    final ty = m.storage[13];
    final px = (_side / 2 - tx) / z;
    final py = (_h / 2 - ty) / z;
    var nx = _side / 2 - px * z2;
    var ny = _h / 2 - py * z2;
    nx = nx.clamp(_side - _cw * z2, 0.0).toDouble();
    ny = ny.clamp(_h - _ch * z2, 0.0).toDouble();
    _tc.value = Matrix4(z2, 0, 0, 0, 0, z2, 0, 0, 0, 0, 1, 0, nx, ny, 0, 1);
  }

  Future<String?> _render() async {
    final ro = _key.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return null;
    for (final sz in widget.out) {
      final image = await ro.toImage(pixelRatio: sz / _side);
      final w = image.width;
      final h = image.height;
      final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (bd == null) continue;
      final base = img.Image.fromBytes(width: w, height: h, bytes: bd.buffer, numChannels: 4);
      var q = 85;
      while (q > 30) {
        final jpg = img.encodeJpg(base, quality: q);
        final d = 'data:image/jpeg;base64,${base64Encode(jpg)}';
        if (d.length < widget.limit) return d;
        q -= 12;
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final d = await _render();
      if (d != null) {
        if (mounted) Navigator.of(context).pop(d);
        return;
      }
      toast('الصورة كبيرة جداً', bad: true);
    } catch (_) {
      toast('تعذر معالجة الصورة', bad: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    final s = min(300.0, min(mq.height * .5 / widget.ratio, mq.width - 56));
    final h = s * widget.ratio;
    _side = s;
    _h = h;

    Widget body;
    final im = _im;
    if (_failed) {
      body = const Center(child: Text('تعذر فتح الصورة', style: TextStyle(color: kMu)));
    } else if (im == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final base = max(s / im.width, h / im.height);
      _cw = im.width * base;
      _ch = im.height * base;
      if (!_inited) {
        _inited = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _tc.value = Matrix4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -(_cw - _side) / 2, -(_ch - _h) / 2, 0, 1);
        });
      }
      final viewport = SizedBox(
        width: s,
        height: h,
        child: RepaintBoundary(
          key: _key,
          child: ColoredBox(
            color: Colors.white,
            child: InteractiveViewer(
              transformationController: _tc,
              constrained: false,
              minScale: 1,
              maxScale: 4,
              child: SizedBox(
                width: _cw,
                height: _ch,
                child: RawImage(image: im, fit: BoxFit.fill),
              ),
            ),
          ),
        ),
      );
      final framed = Container(
        decoration: BoxDecoration(
          shape: widget.round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.round ? null : BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: accentA(context, .55), blurRadius: 26),
            BoxShadow(color: context.accent, spreadRadius: 3),
          ],
        ),
        child: widget.round
            ? ClipOval(child: viewport)
            : ClipRRect(borderRadius: BorderRadius.circular(18), child: viewport),
      );
      body = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              framed,
              const SizedBox(height: 22),
              const Text('اسحب لتحريك الصورة، وكبّرها بالشريط أو بإصبعين',
                  textAlign: TextAlign.center, style: TextStyle(color: kMu, fontSize: 13)),
              SizedBox(
                width: s,
                child: Slider(
                  min: 1,
                  max: 4,
                  value: _zoom < 1 ? 1.0 : (_zoom > 4 ? 4.0 : _zoom),
                  onChanged: _setZoom,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: s,
                child: Row(
                  children: [
                    Expanded(child: AppButton(_busy ? '...' : 'حفظ', onPressed: _busy ? null : _save)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton('إلغاء', kind: 'g', onPressed: () => Navigator.of(context).pop()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), automaticallyImplyLeading: false),
      body: body,
    );
  }
}
