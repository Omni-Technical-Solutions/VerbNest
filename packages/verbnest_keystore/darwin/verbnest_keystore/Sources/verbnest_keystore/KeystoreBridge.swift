import Foundation
import Network
import Security
import CryptoKit

struct KeystoreFailure: Error {
    let message: String
}

/// Identities held by the Keychain, and loopback relays that open TLS with one
/// of them (FR-HTTP-013f). The private key never leaves the Keychain: signing
/// happens inside Network.framework.
final class KeystoreBridge {
    private let queue = DispatchQueue(label: "com.omni.verbnest.keystore")
    private var sessions: [String: RelaySession] = [:]

    // MARK: identities

    func identities() throws -> [[String: Any]] {
        try allIdentities().map { describe($0) }
    }

    private func allIdentities() throws -> [SecIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let out = out else {
            throw KeystoreFailure(message: "The keychain could not be read (\(status)).")
        }
        if CFGetTypeID(out) == SecIdentityGetTypeID() { return [out as! SecIdentity] }
        return (out as? [SecIdentity]) ?? []
    }

    private func certificate(of identity: SecIdentity) -> SecCertificate? {
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        return cert
    }

    static func fingerprint(_ der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private func describe(_ identity: SecIdentity) -> [String: Any] {
        guard let cert = certificate(of: identity) else { return ["id": "?", "label": "?"] }
        let der = SecCertificateCopyData(cert) as Data
        let name = (SecCertificateCopySubjectSummary(cert) as String?) ?? "Identity"
        let id = KeystoreBridge.fingerprint(der)
        return ["id": id, "label": name, "subject": name, "sha256": id]
    }

    private func find(_ id: String) throws -> SecIdentity {
        for i in try allIdentities() {
            if let c = certificate(of: i),
               KeystoreBridge.fingerprint(SecCertificateCopyData(c) as Data) == id {
                return i
            }
        }
        throw KeystoreFailure(message: "The identity is not in the keystore any more. Choose it again in Settings > Network.")
    }

    // MARK: import

    /// Imports a PKCS#12 file into the Keychain and returns the identity. The
    /// key is kept by the system from then on; the file's bytes are not kept.
    func importPKCS12(_ data: Data, passphrase: String) throws -> [String: Any] {
        var items: CFArray?
        let status = SecPKCS12Import(
            data as CFData,
            [kSecImportExportPassphrase as String: passphrase] as CFDictionary,
            &items
        )
        switch status {
        case errSecSuccess: break
        case errSecAuthFailed, -25264:
            throw KeystoreFailure(message: "The passphrase is wrong, or the file uses encryption this system does not support.")
        case errSecDecode:
            throw KeystoreFailure(message: "That is not a PKCS#12 file.")
        default:
            throw KeystoreFailure(message: "The file could not be imported (\(status)).")
        }
        guard let first = (items as? [[String: Any]])?.first,
              let any = first[kSecImportItemIdentity as String]
        else { throw KeystoreFailure(message: "The file holds no certificate and key.") }
        let identity = any as! SecIdentity
        // SecPKCS12Import only returns references: store the identity (app
        // keychain on iOS, default keychain on macOS). "Duplicate" is fine. An
        // unsigned build (the iOS simulator) has no keychain entitlement and
        // fails here with -25303.
        let add: [String: Any] = [
            kSecValueRef as String: identity,
            kSecAttrIsPermanent as String: true,
        ]
        let s = SecItemAdd(add as CFDictionary, nil)
        if s != errSecSuccess && s != errSecDuplicateItem {
            throw KeystoreFailure(message: "The identity could not be stored in the keychain (\(s)).")
        }
        return describe(identity)
    }

    /// Deletes an identity (certificate and key) from the Keychain.
    func remove(identityId: String) throws {
        let identity = try find(identityId)
        let status = SecItemDelete([kSecValueRef as String: identity] as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeystoreFailure(message: "The identity could not be removed (\(status)).")
        }
    }

    // MARK: relay

    func open(
        host: String, port: Int, identityId: String, cas: [Data], minVersion: String?,
        verify: Bool, protocols: [String],
        completion: @escaping (Result<[String: Any], KeystoreFailure>) -> Void
    ) {
        let identity: SecIdentity
        do { identity = try find(identityId) } catch {
            return completion(.failure(error as? KeystoreFailure ?? KeystoreFailure(message: "\(error)")))
        }
        guard port > 0 && port < 65536 else {
            return completion(.failure(KeystoreFailure(message: "Bad port \(port).")))
        }
        let anchors: [SecCertificate] = cas.compactMap { SecCertificateCreateWithData(nil, Self.der(from: $0) as CFData) }
        let session = RelaySession(queue: queue)
        queue.async {
            self.sessions[session.id] = session
            session.start(
                host: host, port: UInt16(port), identity: identity, anchors: anchors,
                minVersion: minVersion, verify: verify, protocols: protocols
            ) { outcome in
                if case .failure = outcome { self.queue.async { self.sessions[session.id] = nil } }
                completion(outcome)
            }
        }
    }

    func close(sessionId: String) {
        queue.async {
            self.sessions.removeValue(forKey: sessionId)?.cancel()
        }
    }

    /// CA files come as PEM or DER; the Security framework wants DER.
    static func der(from data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN") else { return data }
        let body = text.split(separator: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: body) ?? data
    }
}

/// One relay: Dart connects to 127.0.0.1:port in plain TCP; the other end is a
/// TLS connection, already established, that carries the identity.
final class RelaySession {
    let id = UUID().uuidString
    private let queue: DispatchQueue
    private var upstream: NWConnection?
    private var listener: NWListener?
    private var inbound: NWConnection?
    private var finished = false
    private var serverCertificate: Data?
    private var verifyFailure: String?

    init(queue: DispatchQueue) { self.queue = queue }

    func start(
        host: String, port: UInt16, identity: SecIdentity, anchors: [SecCertificate],
        minVersion: String?, verify: Bool, protocols: [String],
        done: @escaping (Result<[String: Any], KeystoreFailure>) -> Void
    ) {
        let tls = NWProtocolTLS.Options()
        let opts = tls.securityProtocolOptions
        if let id = sec_identity_create(identity) { sec_protocol_options_set_local_identity(opts, id) }
        switch minVersion {
        case "1.3": sec_protocol_options_set_min_tls_protocol_version(opts, .TLSv13)
        case "1.2": sec_protocol_options_set_min_tls_protocol_version(opts, .TLSv12)
        default: break
        }
        for p in protocols { sec_protocol_options_add_tls_application_protocol(opts, p) }
        sec_protocol_options_set_verify_block(opts, { [weak self] _, trustRef, complete in
            let trust = sec_trust_copy_ref(trustRef).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first {
                self?.serverCertificate = SecCertificateCopyData(leaf) as Data
            }
            if !verify { return complete(true) }
            SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
            if !anchors.isEmpty {
                SecTrustSetAnchorCertificates(trust, anchors as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, false)
            }
            var err: CFError?
            let ok = SecTrustEvaluateWithError(trust, &err)
            if !ok { self?.verifyFailure = (err as Error?)?.localizedDescription ?? "not trusted" }
            complete(ok)
        }, queue)

        let began = DispatchTime.now()
        let conn = NWConnection(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!,
            using: NWParameters(tls: tls)
        )
        upstream = conn
        func finish(_ r: Result<[String: Any], KeystoreFailure>) {
            if finished { return }
            finished = true
            if case .failure = r { cancel() }
            done(r)
        }
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                let ms = Double(DispatchTime.now().uptimeNanoseconds - began.uptimeNanoseconds) / 1e6
                var proto: String?
                if let meta = conn.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata,
                   let p = sec_protocol_metadata_get_negotiated_protocol(meta.securityProtocolMetadata) {
                    proto = String(cString: p)
                }
                self.listen(conn, certificate: self.serverCertificate, protocolName: proto, handshakeMs: ms, finish: finish)
            case .waiting(let e):
                // Network.framework waits instead of failing when the TLS
                // handshake is refused; there is nothing to wait for here.
                if let why = self.verifyFailure {
                    finish(.failure(KeystoreFailure(message: "The server certificate is not trusted: \(why)")))
                } else {
                    finish(.failure(KeystoreFailure(message: "TLS handshake failed: \(e.localizedDescription)")))
                }
            case .failed(let e):
                finish(.failure(KeystoreFailure(message: "TLS connection failed: \(e.localizedDescription)")))
            default: break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 20) {
            finish(.failure(KeystoreFailure(message: "Timed out connecting to \(host):\(port).")))
        }
    }

    private func listen(
        _ up: NWConnection, certificate: Data?, protocolName: String?, handshakeMs: Double,
        finish: @escaping (Result<[String: Any], KeystoreFailure>) -> Void
    ) {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        guard let l = try? NWListener(using: params) else {
            return finish(.failure(KeystoreFailure(message: "Could not open the local relay port.")))
        }
        listener = l
        l.newConnectionHandler = { [weak self] c in
            guard let self = self, self.inbound == nil else { c.cancel(); return }
            self.inbound = c
            c.start(queue: self.queue)
            Self.pipe(c, up)
            Self.pipe(up, c)
        }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                var map: [String: Any] = [
                    "session": self?.id ?? "", "port": Int(l.port?.rawValue ?? 0), "handshakeMs": handshakeMs,
                ]
                if let c = certificate { map["certificate"] = FlutterBytes.wrap(c) }
                if let p = protocolName { map["protocol"] = p }
                finish(.success(map))
            case .failed(let e):
                finish(.failure(KeystoreFailure(message: "The local relay failed: \(e.localizedDescription)")))
            default: break
            }
        }
        l.start(queue: queue)
    }

    /// Copies bytes one way until the sender is done, then closes both ends.
    private static func pipe(_ a: NWConnection, _ b: NWConnection) {
        a.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                b.send(content: data, completion: .contentProcessed { _ in
                    if isComplete || error != nil { a.cancel(); b.cancel() } else { pipe(a, b) }
                })
            } else if isComplete || error != nil {
                a.cancel(); b.cancel()
            } else {
                pipe(a, b)
            }
        }
    }

    func cancel() {
        listener?.cancel()
        inbound?.cancel()
        upstream?.cancel()
        listener = nil
    }
}
