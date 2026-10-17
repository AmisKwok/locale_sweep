import 'package:flutter_test/flutter_test.dart';
import 'package:locale_sweep/src/cli/flow_filter.dart';

void main() {
  const sources = {
    'test/sweep/app_test.dart': '''
void main() {
  sweepTest('login', builder: () => const Login());
  sweepTest(
    "checkout",
    builder: () => const Checkout(),
  );
  sweepTest('settings', builder: () => const Settings());
}
''',
    'test/sweep/onboarding_test.dart': '''
void main() {
  sweepTest('welcome', builder: () => const Welcome());
}
''',
  };

  group('selectFlows', () {
    test('matches a declared flow name in a differently named file', () {
      final s = selectFlows(sources, {'login'});
      expect(s.files, ['test/sweep/app_test.dart']);
      expect(s.namePattern, isNotNull);
    });

    test('name pattern runs only the requested flows', () {
      final pattern = RegExp(
        selectFlows(sources, {'login', 'checkout'}).namePattern!,
      );
      expect(pattern.hasMatch('sweep: login login [EN · 393x852]'), isTrue);
      expect(
        pattern.hasMatch(
          'sweep: checkout checkout [DE · 2.0x scale · 393x852]',
        ),
        isTrue,
      );
      expect(
        pattern.hasMatch('sweep: settings settings [EN · 393x852]'),
        isFalse,
      );
      expect(
        pattern.hasMatch('sweep: login extra login extra [EN · 393x852]'),
        isFalse,
      );
    });

    test('escapes regex characters in flow names', () {
      final s = selectFlows(
        {'test/sweep/a_test.dart': "sweepTest('cart (v2)', builder: b);"},
        {'cart (v2)'},
      );
      expect(
        RegExp(
          s.namePattern!,
        ).hasMatch('sweep: cart (v2) cart (v2) [EN · 393x852]'),
        isTrue,
      );
    });

    test('file-name match still works and runs the whole file', () {
      final s = selectFlows(sources, {'onboarding'});
      expect(s.files, ['test/sweep/onboarding_test.dart']);
      expect(s.namePattern, isNull);
    });

    test('file name that is also the declared flow keeps the filter', () {
      final s = selectFlows(
        {
          'test/sweep/login_test.dart': "sweepTest('login', builder: b);",
          'test/sweep/other_test.dart': "sweepTest('other', builder: b);",
        },
        {'login'},
      );
      expect(s.files, ['test/sweep/login_test.dart']);
      expect(s.namePattern, isNotNull);
    });

    test('no match reports the declared flows', () {
      final s = selectFlows(sources, {'logn'});
      expect(s.files, isEmpty);
      expect(s.declaredFlows, {'login', 'checkout', 'settings', 'welcome'});
    });
  });
}
