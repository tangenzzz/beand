import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Cuts a gear photo out of its background so the piece stands freely on its
// My Coffee Desk shelf, and grades it gently to sit well on the dark card.
// All on the device, no AI key: the platform only delivers a mask —
// Android runs U²-Net small on LiteRT (android/.../Cutout.kt, works
// without Google Play services), iOS 17+ uses Vision's subject lifting (ios/Runner/
// Cutout.swift). Everything else happens here, the same on both.
class GearCutout {
  static const _channel = MethodChannel('beand/cutout');

  /// Longest side the photo is worked on at; the result is at most
  /// [outputSize].
  static const workSize = 1024;
  static const outputSize = 600;

  /// PNG of the cut-out, graded piece; null when the platform can't do it
  /// (older iOS, no subject found) — the caller then keeps the photo.
  static Future<Uint8List?> cutout(String photoPath) async {
    try {
      final temp = await getTemporaryDirectory();
      final work = p.join(
        temp.path,
        'cutout_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      // Upright and smaller first: the native side then needs no EXIF
      // handling, and the mask matches the pixels Dart works on.
      final jpg = await compute(_prepare, await File(photoPath).readAsBytes());
      if (jpg == null) return null;
      await File(work).writeAsBytes(jpg);
      try {
        final result = await _channel.invokeMapMethod<String, Object?>('mask', {
          'path': work,
        });
        final mask = result?['mask'];
        final w = result?['width'];
        final h = result?['height'];
        if (mask is! Uint8List || w is! int || h is! int || w == 0) {
          return null;
        }
        return await compute(
          (args) => composeCutout(args.$1, args.$2, args.$3, args.$4),
          (jpg, mask, w, h),
        );
      } finally {
        File(work).delete().ignore();
      }
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Uint8List? _prepare(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var upright = img.bakeOrientation(decoded);
    if (math.max(upright.width, upright.height) > workSize) {
      upright = upright.width >= upright.height
          ? img.copyResize(upright, width: workSize)
          : img.copyResize(upright, height: workSize);
    }
    return img.encodeJpg(upright, quality: 92);
  }
}

/// The photo [jpg] with the [mask] (grayscale, any size, 0–255) as alpha:
/// graded, cropped to the piece and scaled to at most
/// [GearCutout.outputSize]. Null when the mask holds no clear subject.
@visibleForTesting
Uint8List? composeCutout(
  Uint8List jpg,
  Uint8List mask,
  int maskWidth,
  int maskHeight,
) {
  final photo = img.decodeImage(jpg);
  if (photo == null || mask.length != maskWidth * maskHeight) return null;
  final w = photo.width;
  final h = photo.height;
  final maskImage = img.Image.fromBytes(
    width: maskWidth,
    height: maskHeight,
    // A copy: the channel's list may be a view into a larger buffer.
    bytes: Uint8List.fromList(mask).buffer,
    numChannels: 1,
  );
  final scaled = maskWidth == w && maskHeight == h
      ? maskImage
      : img.copyResize(
          maskImage,
          width: w,
          height: h,
          interpolation: img.Interpolation.linear,
        );

  // Raw bytes instead of getPixel: several times faster on the phone.
  final rgb = photo
      .convert(format: img.Format.uint8, numChannels: 3)
      .toUint8List();
  final maskBytes = scaled.toUint8List();

  // Soft edge: below 25 % gone, above 60 % solid.
  final alpha = Float32List(w * h);
  var solid = 0;
  final histogram = List<int>.filled(256, 0);
  for (var i = 0; i < w * h; i++) {
    final a = ((maskBytes[i] / 255 - 0.25) / 0.35).clamp(0.0, 1.0);
    alpha[i] = a;
    if (a > 0.5) {
      solid++;
      final o = i * 3;
      histogram[_luma(rgb[o], rgb[o + 1], rgb[o + 2]).round().clamp(0, 255)]++;
    }
  }
  final coverage = solid / (w * h);
  if (coverage < 0.02 || coverage > 0.97) return null;

  final (lo, hi) = _percentiles(histogram, solid);
  final grade = SubjectGrade(lo / 255, hi / 255);

  // Bounding box of everything visible, a little room around it.
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (alpha[y * w + x] > 0.1) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  const pad = 8;
  minX = math.max(minX - pad, 0);
  minY = math.max(minY - pad, 0);
  maxX = math.min(maxX + pad, w - 1);
  maxY = math.min(maxY + pad, h - 1);

  final outW = maxX - minX + 1, outH = maxY - minY + 1;
  final rgba = Uint8List(outW * outH * 4);
  var o = 0;
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final i = y * w + x;
      final a = alpha[i];
      if (a > 0) {
        final (r, g, b) = grade.apply(
          rgb[i * 3] / 255,
          rgb[i * 3 + 1] / 255,
          rgb[i * 3 + 2] / 255,
        );
        rgba[o] = (r * 255).round();
        rgba[o + 1] = (g * 255).round();
        rgba[o + 2] = (b * 255).round();
        rgba[o + 3] = (a * 255).round();
      }
      o += 4;
    }
  }
  var out = img.Image.fromBytes(
    width: outW,
    height: outH,
    bytes: rgba.buffer,
    numChannels: 4,
  );
  if (math.max(out.width, out.height) > GearCutout.outputSize) {
    out = out.width >= out.height
        ? img.copyResize(
            out,
            width: GearCutout.outputSize,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            out,
            height: GearCutout.outputSize,
            interpolation: img.Interpolation.average,
          );
  }
  return img.encodePng(out);
}

double _luma(num r, num g, num b) => 0.299 * r + 0.587 * g + 0.114 * b;

// 1st and 99th percentile of the subject's brightness.
(int, int) _percentiles(List<int> histogram, int total) {
  var lo = 0, hi = 255, seen = 0;
  final loAt = total * 0.01, hiAt = total * 0.99;
  var loFound = false;
  for (var i = 0; i < 256; i++) {
    seen += histogram[i];
    if (!loFound && seen >= loAt) {
      lo = i;
      loFound = true;
    }
    if (seen >= hiAt) {
      hi = i;
      break;
    }
  }
  return (lo, math.max(hi, lo + 1));
}

/// The gentle look the cut-out gets: the subject's own brightness range
/// stretched to full (1st..99th percentile), a mild S-curve, a touch less
/// saturation, slightly warm — so photos from different rooms and lights
/// sit together on one shelf.
@immutable
class SubjectGrade {
  const SubjectGrade(this.low, this.high);

  /// Subject brightness at the 1st and 99th percentile, 0–1.
  final double low;
  final double high;

  static const contrast = 0.12;
  static const saturation = 0.9;
  static const warm = (1.02, 1.0, 0.97);

  (double, double, double) apply(double r, double g, double b) {
    final range = math.max(high - low, 1e-3);
    double level(double v) {
      final t = ((v - low) / range).clamp(0.0, 1.0);
      return t + contrast * (t - 0.5) * (1 - (2 * t - 1).abs());
    }

    var rr = level(r), gg = level(g), bb = level(b);
    final l = _luma(rr, gg, bb).toDouble();
    rr = l + saturation * (rr - l);
    gg = l + saturation * (gg - l);
    bb = l + saturation * (bb - l);
    return (
      (rr * warm.$1).clamp(0.0, 1.0),
      (gg * warm.$2).clamp(0.0, 1.0),
      (bb * warm.$3).clamp(0.0, 1.0),
    );
  }
}
