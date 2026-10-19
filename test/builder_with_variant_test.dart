import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locale_sweep/locale_sweep.dart';

void main() {
  group('builderWithVariant', () {
    test('requires exactly one builder', () {
      expect(() => sweepTest('neither'), throwsArgumentError);
      expect(
        () => sweepTest(
          'both',
          builder: () => const SizedBox.shrink(),
          builderWithVariant: (variant) => const SizedBox.shrink(),
        ),
        throwsArgumentError,
      );
    });

    SweepVariant? seen;

    sweepTest(
      'variant-builder',
      builderWithVariant: (variant) {
        seen = variant;
        return const SizedBox.shrink();
      },
      locales: const ['en'],
      textScales: const [1.0],
      viewports: const [ViewportPreset.phone],
      captureScreenshots: false,
    );

    tearDownAll(() {
      final file = File('.locale_sweep/results/variant-builder.json');
      if (file.existsSync()) file.deleteSync();
    });

    test('receives the current variant', () {
      expect(seen?.locale, 'en');
      expect(seen?.textScale, 1.0);
    });
  });
}
