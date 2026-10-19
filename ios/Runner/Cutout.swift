import Flutter
import Vision

// Mask for cutting gear photos out (lib/services/gear_cutout.dart): Apple's
// Vision subject lifting (iOS 17+), on the device. Returns only the mask;
// cropping and grading happen in Dart, the same for Android and iOS.
enum Cutout {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "beand/cutout", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "mask" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String
      else {
        result(FlutterError(code: "args", message: "path missing", details: nil))
        return
      }
      guard #available(iOS 17.0, *) else {
        result(FlutterError(code: "unsupported", message: "Needs iOS 17", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let mask = try Cutout.mask(path: path)
          DispatchQueue.main.async { result(mask) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "cutout", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  @available(iOS 17.0, *)
  private static func mask(path: String) throws -> [String: Any] {
    let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path))
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])
    guard let observation = request.results?.first else {
      return ["width": 0, "height": 0, "mask": FlutterStandardTypedData(bytes: Data())]
    }
    let buffer = try observation.generateScaledMaskForImage(
      forInstances: observation.allInstances, from: handler)
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
      throw NSError(domain: "cutout", code: 1)
    }
    // One float per pixel, 0…1.
    var bytes = Data(count: width * height)
    bytes.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
      for y in 0..<height {
        let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float32.self)
        for x in 0..<width {
          out[y * width + x] = UInt8(max(0, min(255, row[x] * 255)))
        }
      }
    }
    return ["width": width, "height": height, "mask": FlutterStandardTypedData(bytes: bytes)]
  }
}
