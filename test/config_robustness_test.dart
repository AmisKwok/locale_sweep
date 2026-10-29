import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locale_sweep/locale_sweep.dart';

void main() {
  group('SweepConfig robustness', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('sweep_cfg_'));

    tearDown(() => dir.deleteSync(recursive: true));

    SweepConfig load(String yaml) {
      final file = File('${dir.path}/locale_sweep.yaml')
        ..writeAsStringSync(yaml);
      return SweepConfig.load(file.path);
    }

    test('drops non-string locale entries instead of throwing', () {
      // `locales: [en, 1]` used to throw a TypeError out of SweepConfig.load.
      final cfg = load('''
locales:
  - en
  - 1
''');
      expect(cfg.locales, ['en']);
    });

    test('falls back to the default matrix when every entry is invalid', () {
      final cfg = load('''
locales:
  - 1
  - true
text_scales:
  - "2.0"
''');
      expect(cfg.locales, ['en', 'de', 'ar', 'ja']);
      expect(cfg.textScales, [1.0, 2.0]);
    });

    test('drops malformed viewports instead of throwing', () {
      final cfg = load('''
viewports:
  - name: broken
  - name: phone
    width: 393
    height: 852
''');
      expect(cfg.viewports, hasLength(1));
      expect(cfg.viewports.first.name, 'phone');
      expect(cfg.viewports.first.width, 393);
    });

    test('keeps valid entries alongside invalid ones', () {
      final cfg = load('''
locales:
  - en
  - de
  - 42
text_scales: [1.0, "2.0", 3.0]
''');
      expect(cfg.locales, ['en', 'de']);
      expect(cfg.textScales, [1.0, 3.0]);
    });

    test('loads a valid config unchanged', () {
      final cfg = load('''
locales: [en, de]
text_scales: [1.0, 2.0]
viewports:
  - name: phone
    width: 393
    height: 852
tolerance: 1.5
''');
      expect(cfg.locales, ['en', 'de']);
      expect(cfg.textScales, [1.0, 2.0]);
      expect(cfg.viewports.first.name, 'phone');
      expect(cfg.tolerance, 1.5);
    });
  });
}
