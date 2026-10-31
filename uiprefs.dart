import 'package:flutter/material.dart';

import 'app_state.dart';
import 'widgets.dart';

/// مقاس الخط: 12 عقدة (0 إلى 11)
final ValueNotifier<int> fontStep = ValueNotifier<int>(prefs.getInt('fs') ?? 4);

double fontScale(int s) => 0.8 + s.clamp(0, 11) * 0.06;

void showFontSheet(BuildContext context) {
  showAppSheet<void>(context, (sc) => [
        const Text('مقاس الخط', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 10),
        StatefulBuilder(
          builder: (c, set) => Column(children: [
            Slider(
              value: fontStep.value.toDouble(),
              min: 0,
              max: 11,
              divisions: 11,
              label: '${fontStep.value + 1}',
              onChanged: (v) {
                fontStep.value = v.round();
                prefs.setInt('fs', v.round());
                set(() {});
              },
            ),
            Text('${fontStep.value + 1} / 12', style: const TextStyle(color: kMu)),
            const SizedBox(height: 8),
            const Text('هذا مثال على حجم النص في التطبيق', style: TextStyle(fontSize: 16)),
          ]),
        ),
        const SizedBox(height: 12),
        AppButton('تم', onPressed: () => Navigator.of(sc).pop()),
      ]);
}
