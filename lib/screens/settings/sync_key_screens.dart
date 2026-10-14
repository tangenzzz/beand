import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../sync/secure_screen.dart';
import '../../theme/app_theme.dart';

// Pairing devices via QR:
//  * PlainKeyScreen: the key (nsec) as QR — only after fingerprint/PIN,
//    with a warning. There is no longer a password variant.
//  * ScanKeyScreen: camera or photo from the gallery, returns the scanned
//    text.
// Both key pages run under SecureScreen (no screenshot, empty preview in
// the app switcher). Short texts.

/// Fingerprint, face or device PIN. false if cancelled. Without any screen
/// lock there is nothing to ask — whoever holds the device can get at
/// everything anyway; the QR still only comes with a warning.
Future<bool> confirmDeviceOwner() async {
  final auth = LocalAuthentication();
  try {
    if (!await auth.isDeviceSupported()) return true;
    return await auth.authenticate(
      localizedReason: 'Show your sync key as a QR code',
    );
  } catch (_) {
    return false;
  }
}

/// Main path: the key as QR, without a password, but only after
/// fingerprint/face/PIN and with a warning — you pair your own devices,
/// usually alone.
class PlainKeyScreen extends StatelessWidget {
  const PlainKeyScreen({super.key, required this.nsec});

  final String nsec;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SecureScreen(
      child: Scaffold(
        appBar: AppBar(title: const Text('Link another device')),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
          children: [
            Text(
              'On the other device: Settings → Sync → Scan QR code.',
              style: TextStyle(color: colors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              'This code is your sync key. Anyone who scans it can read your '
              'synced data — only show it to your own devices.',
              style: TextStyle(color: colors.danger, height: 1.4),
            ),
            const SizedBox(height: 20),
            Center(child: _KeyQr(data: nsec)),
          ],
        ),
      ),
    );
  }
}

// White background, black modules — scanners cope poorly with dark
// backgrounds, even in the dark theme.
class _KeyQr extends StatelessWidget {
  const _KeyQr({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: QrImageView(
        data: data,
        size: 240,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
      ),
    );
  }
}

/// Camera; returns the first code that looks like a sync key
/// (`ncryptsec1…` or `nsec1…`), otherwise null.
class ScanKeyScreen extends StatefulWidget {
  const ScanKeyScreen({super.key});

  @override
  State<ScanKeyScreen> createState() => _ScanKeyScreenState();
}

class _ScanKeyScreenState extends State<ScanKeyScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  bool _wrongCode = false;
  bool _noKeyInPhoto = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // true if a key was found — the page is already closed then.
  bool _accept(BarcodeCapture capture) {
    for (final code in capture.barcodes) {
      final value = code.rawValue?.trim() ?? '';
      if (value.startsWith('ncryptsec1') || value.startsWith('nsec1')) {
        _done = true;
        Navigator.of(context).pop(value);
        return true;
      }
    }
    return false;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done || _accept(capture)) return;
    if (!_wrongCode && mounted) setState(() => _wrongCode = true);
  }

  // QR from a photo (e.g. taken of another device's screen). Also works
  // without camera permission — the system image picker needs none.
  Future<void> _pickPhoto() async {
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    } catch (_) {
      return;
    }
    if (picked == null || _done || !mounted) return;
    BarcodeCapture? capture;
    try {
      capture = await _controller.analyzeImage(
        picked.path,
        formats: const [BarcodeFormat.qrCode],
      );
    } catch (_) {
      // No readable code — same as "nothing found".
    }
    if (_done || !mounted) return;
    if (capture != null && _accept(capture)) return;
    setState(() => _noKeyInPhoto = true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan sync key'),
        actions: [
          IconButton(
            tooltip: 'Choose photo',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _pickPhoto,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? 'Camera access is off. Allow it in the system '
                                'settings.'
                          : 'Camera not available.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose photo'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.card.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _noKeyInPhoto
                    ? 'No sync key in this photo.'
                    : _wrongCode
                    ? 'Not a sync key. On the other device: Show QR code.'
                    : 'On the other device: Settings → Sync → Show QR code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
