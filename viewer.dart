import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'crop.dart';
import 'data.dart';
import 'home.dart';
import 'widgets.dart';

/// حفظ صورة في الجهاز (يفتح اختيار مكان الحفظ)
Future<void> saveImageBytes(Uint8List bytes, {String name = 'fir'}) async {
  try {
    final fn = '${name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final p = await FilePicker.saveFile(dialogTitle: 'حفظ الصورة', fileName: fn, bytes: bytes);
    if (p != null) toast('تم الحفظ ✅', accent: true);
  } catch (e) {
    toast('تعذر حفظ الصورة', bad: true);
  }
}

/// عارض صورة بحجم كبير مع زر تحميل
class BigImageViewer extends StatelessWidget {
  final Uint8List bytes;
  final String title;
  const BigImageViewer({super.key, required this.bytes, this.title = ''});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(title), actions: [
        IconButton(tooltip: 'تحميل', onPressed: () => saveImageBytes(bytes), icon: const Icon(Icons.download_rounded)),
      ]),
      body: Center(child: InteractiveViewer(minScale: 1, maxScale: 6, child: Image.memory(bytes, fit: BoxFit.contain))),
    );
  }
}

/// صورة القروب بحجم ودقة أكبر + تبديل أو حذف (للمشرفين والمطورين)
class GroupPhotoViewer extends StatefulWidget {
  final String gid;
  final bool canEdit;
  const GroupPhotoViewer({super.key, required this.gid, this.canEdit = false});

  @override
  State<GroupPhotoViewer> createState() => _GroupPhotoViewerState();
}

class _GroupPhotoViewerState extends State<GroupPhotoViewer> {
  Uint8List? bytes;
  bool loading = true;
  bool canEdit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      canEdit = widget.canEdit || Session.isDev || (await ref('groupAdmins/${widget.gid}/$myUid').get()).value == true;
    } catch (_) {}
    try {
      final d = (await ref('groupPhotos/${widget.gid}').get()).value?.toString() ?? '';
      final i = d.indexOf(',');
      if (i >= 0) bytes = UriData.parse(d).contentAsBytes();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _change() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null || !mounted) return;
      final d = await cropImage(context, await x.readAsBytes(), out: const [320, 240, 200], limit: 29000, round: true, title: 'صورة القروب');
      if (d == null) return;
      await ref('groupPhotos/${widget.gid}').set(d);
      dropGroupPhoto(widget.gid);
      setState(() => loading = true);
      await _load();
      toast('تم تبديل الصورة ✅', accent: true);
    } catch (e) {
      err(e);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('حذف صورة القروب؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('نعم')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref('groupPhotos/${widget.gid}').remove();
      dropGroupPhoto(widget.gid);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      err(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(groupName(widget.gid)), actions: [
        if (bytes != null) IconButton(tooltip: 'تحميل', onPressed: () => saveImageBytes(bytes!, name: 'group'), icon: const Icon(Icons.download_rounded)),
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: Center(
                  child: bytes == null
                      ? const Text('لا توجد صورة لهذا القروب', style: TextStyle(color: kMu))
                      : InteractiveViewer(minScale: 1, maxScale: 6, child: Image.memory(bytes!, fit: BoxFit.contain)),
                ),
              ),
              if (canEdit)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(child: AppButton('تبديل الصورة', glow: true, onPressed: _change)),
                      if (bytes != null) ...[
                        const SizedBox(width: 10),
                        Expanded(child: AppButton('حذف', kind: 'r', onPressed: _delete)),
                      ],
                    ]),
                  ),
                ),
            ]),
    );
  }
}
