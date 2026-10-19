import 'package:flutter/foundation.dart';

// Licenses of what ships in the app without being a Dart package — the
// license page (Settings → About) only knows the packages by itself.
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['U²-Net (u2netp model)'],
      'U²-Net: Going Deeper with Nested U-Structure for Salient Object '
      'Detection. Copyright (c) Xuebin Qin et al. '
      'https://github.com/xuebinqin/U-2-Net\n\n'
      'Licensed under the Apache License, Version 2.0. You may obtain a '
      'copy of the License at http://www.apache.org/licenses/LICENSE-2.0\n\n'
      'Unless required by applicable law or agreed to in writing, '
      'software distributed under the License is distributed on an "AS '
      'IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND. ONNX '
      'export from rembg (MIT), https://github.com/danielgatis/rembg',
    );
    yield const LicenseEntryWithLineBreaks(
      ['LiteRT (TensorFlow Lite)'],
      'Copyright Google LLC. https://github.com/google-ai-edge/LiteRT\n\n'
      'Licensed under the Apache License, Version 2.0. You may obtain a '
      'copy of the License at http://www.apache.org/licenses/LICENSE-2.0\n\n'
      'Unless required by applicable law or agreed to in writing, '
      'software distributed under the License is distributed on an "AS '
      'IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND.',
    );
  });
}
