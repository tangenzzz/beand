import 'package:beand/services/bundled_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native parts without a Dart package are on the license page', () async {
    registerBundledLicenses();
    final packages = {
      await for (final entry in LicenseRegistry.licenses) ...entry.packages,
    };
    expect(
      packages,
      containsAll([
        'U²-Net (u2netp model)',
        'LiteRT (TensorFlow Lite)',
        'zxing-cpp',
        'libzint',
      ]),
    );
  });
}
