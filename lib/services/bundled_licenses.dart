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
    // Compiled into flutter_zxing (QR scanner), whose own license page entry
    // covers only its Dart and wrapper code.
    yield const LicenseEntryWithLineBreaks(
      ['zxing-cpp'],
      'Copyright the ZXing authors and Axel Waggershauser. '
      'https://github.com/zxing-cpp/zxing-cpp\n\n'
      'Licensed under the Apache License, Version 2.0. You may obtain a '
      'copy of the License at http://www.apache.org/licenses/LICENSE-2.0\n\n'
      'Unless required by applicable law or agreed to in writing, '
      'software distributed under the License is distributed on an "AS '
      'IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['libzint'],
      'libzint - the open source barcode library\n'
      'Copyright (C) 2009-2025 Robin Stuart\n\n'
      'Redistribution and use in source and binary forms, with or without '
      'modification, are permitted provided that the following conditions '
      'are met:\n\n'
      '1. Redistributions of source code must retain the above copyright '
      'notice, this list of conditions and the following disclaimer.\n'
      '2. Redistributions in binary form must reproduce the above copyright '
      'notice, this list of conditions and the following disclaimer in the '
      'documentation and/or other materials provided with the distribution.\n'
      '3. Neither the name of the project nor the names of its contributors '
      'may be used to endorse or promote products derived from this software '
      'without specific prior written permission.\n\n'
      'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS '
      '"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT '
      'LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR '
      'A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT '
      'OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, '
      'SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT '
      'LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, '
      'DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY '
      'THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT '
      '(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE '
      'OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.',
    );
  });
}
