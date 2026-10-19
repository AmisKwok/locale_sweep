import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locale_sweep/locale_sweep.dart';

void main() {
  final screenshots = Directory.systemTemp.createTempSync(
    'locale_sweep_capture_',
  );

  sweepTest(
    'capture-only',
    builder: () => const SizedBox(
      width: 100,
      height: 100,
      child: ColoredBox(color: Colors.red),
    ),
    locales: const ['en'],
    textScales: const [1.0],
    viewports: const [ViewportPreset.phone],
    captureScreenshots: true,
    compareScreenshots: false,
    screenshotDir: screenshots.path,
  );

  tearDownAll(() {
    final result = File('.locale_sweep/results/capture-only.json');
    if (result.existsSync()) result.deleteSync();
    screenshots.deleteSync(recursive: true);
  });

  test('writes a screenshot without a golden baseline', () {
    final pngs = screenshots
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.png'))
        .toList();

    expect(pngs, hasLength(1));
    expect(pngs.single.lengthSync(), greaterThan(0));
  });
}
