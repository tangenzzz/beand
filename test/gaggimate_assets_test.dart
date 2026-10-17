import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The GaggiMate logo and mode icons are SVG assets; a missing pubspec entry
// would only show up as an empty spot in the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final name in ['wordmark', 'brew', 'steam', 'water']) {
    test('$name.svg is bundled', () async {
      final svg = await rootBundle.loadString('assets/gaggimate/$name.svg');
      expect(svg, contains('<svg'));
    });
  }
}
