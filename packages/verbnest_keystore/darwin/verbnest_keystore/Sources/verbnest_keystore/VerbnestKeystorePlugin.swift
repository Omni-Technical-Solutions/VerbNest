import Foundation
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Channel `com.omni.verbnest/keystore` (see apps/verbnest_app/lib/src/state/
/// keystore_relay.dart): supported, identities, import, open, close.
public class VerbnestKeystorePlugin: NSObject, FlutterPlugin {
    private let bridge = KeystoreBridge()

    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(macOS)
        let messenger = registrar.messenger
        #else
        let messenger = registrar.messenger()
        #endif
        let channel = FlutterMethodChannel(name: "com.omni.verbnest/keystore", binaryMessenger: messenger)
        let instance = VerbnestKeystorePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "supported":
            result(true)
        case "identities":
            do { result(try bridge.identities()) } catch { result(Self.failure(error)) }
        case "import":
            guard let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data else {
                return result(FlutterError(code: "args", message: "No file bytes", details: nil))
            }
            do {
                result(try bridge.importPKCS12(bytes, passphrase: args["passphrase"] as? String ?? ""))
            } catch { result(Self.failure(error)) }
        case "remove":
            do {
                try bridge.remove(identityId: args["identity"] as? String ?? "")
                result(nil)
            } catch { result(Self.failure(error)) }
        case "open":
            let cas = (args["cas"] as? [FlutterStandardTypedData] ?? []).map { $0.data }
            bridge.open(
                host: args["host"] as? String ?? "",
                port: args["port"] as? Int ?? 443,
                identityId: args["identity"] as? String ?? "",
                cas: cas,
                minVersion: args["minVersion"] as? String,
                verify: args["verify"] as? Bool ?? true,
                protocols: args["protocols"] as? [String] ?? ["http/1.1"]
            ) { outcome in
                DispatchQueue.main.async {
                    switch outcome {
                    case .success(let map): result(map)
                    case .failure(let e): result(Self.failure(e))
                    }
                }
            }
        case "close":
            bridge.close(sessionId: args["session"] as? String ?? "")
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func failure(_ error: Error) -> FlutterError {
        FlutterError(code: "keystore", message: (error as? KeystoreFailure)?.message ?? "\(error)", details: nil)
    }
}
