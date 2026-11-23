import Foundation
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

enum FlutterBytes {
    /// Bytes as the standard codec's typed data, so Dart receives a Uint8List.
    static func wrap(_ data: Data) -> FlutterStandardTypedData { FlutterStandardTypedData(bytes: data) }
}
