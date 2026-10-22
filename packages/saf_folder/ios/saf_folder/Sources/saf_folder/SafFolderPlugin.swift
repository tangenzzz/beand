import Flutter
import UIKit
import UniformTypeIdentifiers

// iOS side of saf_folder: the folder comes from the document picker and is
// kept as a bookmark, so a background task can still write there after a
// restart. The "uri" handed to Dart is that bookmark, base64 with a
// "bookmark:" prefix — opaque to Dart, as the Android tree URI is.
public class SafFolderPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private static let prefix = "bookmark:"
  private var pending: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "beand/saf_folder", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(SafFolderPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "pickFolder":
      pick(result: result)
    case "folderName":
      guard let uri = args?["uri"] as? String else { return badArgs(result) }
      result(Self.nameIfWritable(uri))
    case "writeFile":
      guard let uri = args?["uri"] as? String, let name = args?["name"] as? String,
        let source = args?["source"] as? String
      else { return badArgs(result) }
      // Copying a backup can take a moment: off the main thread.
      DispatchQueue.global(qos: .utility).async {
        do {
          try Self.write(uri: uri, name: name, source: source)
          DispatchQueue.main.async { result(nil) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "write", message: Self.describe(error), details: nil))
          }
        }
      }
    case "release":
      // Nothing held between calls: each write opens and closes the access.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func badArgs(_ result: FlutterResult) {
    result(FlutterError(code: "args", message: "Missing arguments", details: nil))
  }

  // ---- Picker ----

  private func pick(result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "Picker already open", details: nil))
      return
    }
    guard let presenter = Self.topController() else {
      result(FlutterError(code: "ui", message: "No window to show the picker", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pending = result
    presenter.present(picker, animated: true)
  }

  public func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    guard let result = pending else { return }
    pending = nil
    guard let url = urls.first else { return result(nil) }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    do {
      let data = try url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      result(["uri": Self.prefix + data.base64EncodedString(), "name": Self.displayName(url)])
    } catch {
      result(FlutterError(code: "bookmark", message: Self.describe(error), details: nil))
    }
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(nil)
    pending = nil
  }

  private static func topController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  // ---- Folder access ----

  private static func resolve(_ uri: String) throws -> URL {
    guard uri.hasPrefix(prefix), let data = Data(base64Encoded: String(uri.dropFirst(prefix.count)))
    else {
      throw NSError(
        domain: "saf_folder", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Unknown folder"])
    }
    var stale = false
    return try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
  }

  private static func nameIfWritable(_ uri: String) -> String? {
    guard let url = try? resolve(uri) else { return nil }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
      FileManager.default.isWritableFile(atPath: url.path)
    else { return nil }
    return displayName(url)
  }

  // As the Files app shows it. The top of "On My iPhone" is a folder named
  // "File Provider Storage" on disk, and even its localized name says so.
  private static func displayName(_ url: URL) -> String {
    let name =
      (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName
      ?? url.lastPathComponent
    return name == "File Provider Storage" ? "On My \(UIDevice.current.model)" : name
  }

  // Copies into "<name>.part" first and swaps it in only when complete, so
  // a broken run never leaves the last good backup damaged.
  private static func write(uri: String, name: String, source: String) throws {
    let folder = try resolve(uri)
    let access = folder.startAccessingSecurityScopedResource()
    defer { if access { folder.stopAccessingSecurityScopedResource() } }
    let target = folder.appendingPathComponent(name)
    let part = folder.appendingPathComponent(name + ".part")
    var coordinatorError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(
      writingItemAt: folder, options: [], error: &coordinatorError
    ) { dir in
      do {
        let fm = FileManager.default
        let part = dir.appendingPathComponent(part.lastPathComponent)
        let target = dir.appendingPathComponent(target.lastPathComponent)
        if fm.fileExists(atPath: part.path) { try fm.removeItem(at: part) }
        try fm.copyItem(at: URL(fileURLWithPath: source), to: part)
        if fm.fileExists(atPath: target.path) {
          _ = try fm.replaceItemAt(target, withItemAt: part)
        } else {
          try fm.moveItem(at: part, to: target)
        }
      } catch {
        writeError = error
      }
    }
    if let error = coordinatorError ?? writeError { throw error }
  }

  private static func describe(_ error: Error) -> String {
    (error as NSError).localizedDescription
  }
}
