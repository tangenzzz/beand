import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/gear_cutout.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

// After a gear photo is taken: the app cuts the piece out right away and
// shows it standing on a shelf board — Use it, keep the Original photo
// (round, as before), or Retake.

enum PhotoChoice { cutout, original, retake }

/// The choice, and with [PhotoChoice.cutout] the cut-out PNG. Null when
/// dismissed (nothing changes).
Future<(PhotoChoice, Uint8List?)?> showCutoutPreview(
  BuildContext context,
  String photoPath, {
  Future<Uint8List?> Function(String path)? cutout,
  bool allowRetake = true,
}) => showDialog<(PhotoChoice, Uint8List?)>(
  context: context,
  builder: (_) => _CutoutPreview(
    photoPath: photoPath,
    cutout: cutout ?? GearCutout.cutout,
    allowRetake: allowRetake,
  ),
);

class _CutoutPreview extends StatefulWidget {
  const _CutoutPreview({
    required this.photoPath,
    required this.cutout,
    required this.allowRetake,
  });

  final String photoPath;
  final Future<Uint8List?> Function(String path) cutout;
  final bool allowRetake;

  @override
  State<_CutoutPreview> createState() => _CutoutPreviewState();
}

class _CutoutPreviewState extends State<_CutoutPreview> {
  late final Future<Uint8List?> _result = widget.cutout(widget.photoPath);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.card,
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      content: FutureBuilder<Uint8List?>(
        future: _result,
        builder: (context, snap) {
          final done = snap.connectionState == ConnectionState.done;
          final png = snap.data;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 220,
                child: !done
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Cutting out…',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : png == null
                    ? _Failed(photoPath: widget.photoPath)
                    : ShelfPreview(image: Image.memory(png)),
              ),
              const SizedBox(height: 12),
              if (done && png != null)
                AppButton(
                  label: 'Use',
                  onPressed: () =>
                      Navigator.of(context).pop((PhotoChoice.cutout, png)),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.allowRetake)
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop((PhotoChoice.retake, null)),
                      child: Text(
                        'Retake',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                  TextButton(
                    onPressed: done
                        ? () =>
                              Navigator.of(context)
                                  .pop((PhotoChoice.original, null))
                        : null,
                    child: Text(
                      done && png == null ? 'Use photo' : 'Original',
                      style: TextStyle(
                        color: done
                            ? colors.textSecondary
                            : colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.photoPath});

  final String photoPath;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipOval(
          child: Image.file(
            File(photoPath),
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            cacheWidth: 300,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Couldn't find the piece in this photo.",
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

/// A cut-out standing on a shelf board with a soft shadow — the preview,
/// and the same look as on the desk.
class ShelfPreview extends StatelessWidget {
  const ShelfPreview({super.key, required this.image});

  final Image image;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: StandingImage(image: image),
          ),
        ),
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: colors.textTertiary,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      ],
    );
  }
}

/// The cut-out with a soft contact shadow at its foot.
class StandingImage extends StatelessWidget {
  const StandingImage({super.key, required this.image});

  final Image image;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          bottom: -3,
          left: 0,
          right: 0,
          child: FractionallySizedBox(
            widthFactor: 0.8,
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 6,
                    spreadRadius: -1,
                  ),
                ],
              ),
            ),
          ),
        ),
        image,
      ],
    );
  }
}
