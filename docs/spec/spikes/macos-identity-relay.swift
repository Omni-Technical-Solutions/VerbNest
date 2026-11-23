import Foundation
import Network
import Security

// Spike: loopback plain-TCP relay that opens TLS with a client identity (Network.framework).
let args = CommandLine.arguments
let p12Path = args[1], pass = args[2], caPath = args[3], host = args[4], port = UInt16(args[5])!
let seconds = Double(args[6]) ?? 20

func loadIdentity() -> SecIdentity {
    let data = try! Data(contentsOf: URL(fileURLWithPath: p12Path))
    var items: CFArray?
    let st = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: pass, kSecImportToMemoryOnly as String: true] as CFDictionary, &items)
    precondition(st == errSecSuccess, "import failed \(st)")
    let d = (items as! [[String: Any]])[0]
    return d[kSecImportItemIdentity as String] as! SecIdentity
}
func loadCA() -> SecCertificate {
    let pem = try! String(contentsOfFile: caPath)
    let b64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
    return SecCertificateCreateWithData(nil, Data(base64Encoded: b64)! as CFData)!
}
let identity = loadIdentity()
let ca = loadCA()
var cn: CFString?
var cert: SecCertificate?
SecIdentityCopyCertificate(identity, &cert)
SecCertificateCopyCommonName(cert!, &cn)
print("identity: \(cn! as String)"); fflush(stdout)

let q = DispatchQueue(label: "relay")
func tlsParams() -> NWParameters {
    let tls = NWProtocolTLS.Options()
    sec_protocol_options_set_local_identity(tls.securityProtocolOptions, sec_identity_create(identity)!)
    sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trustRef, done in
        print("verify block"); fflush(stdout)
        let trust = sec_trust_copy_ref(trustRef).takeRetainedValue()
        SecTrustSetAnchorCertificates(trust, [ca] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        var err: CFError?
        let ok = SecTrustEvaluateWithError(trust, &err); print("trust ok=\(ok) \(String(describing: err))"); fflush(stdout)
        done(ok)
    }, q)
    return NWParameters(tls: tls)
}
func pipe(_ a: NWConnection, _ b: NWConnection) {
    a.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isDone, err in
        if let data = data, !data.isEmpty { b.send(content: data, completion: .contentProcessed { _ in pipe(a, b) }) }
        else if isDone || err != nil { b.cancel() ; a.cancel() }
        else { pipe(a, b) }
    }
}
let listener = try! NWListener(using: .tcp, on: .any)
listener.newConnectionHandler = { inbound in
    print("inbound"); fflush(stdout)
    let out = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: tlsParams())
    out.stateUpdateHandler = { s in
        switch s {
        case .ready: pipe(inbound, out); pipe(out, inbound)
        case .failed(let e): print("upstream failed: \(e)"); fflush(stdout); inbound.cancel()
        default: print("state \(s)"); fflush(stdout)
        }
    }
    inbound.start(queue: q); out.start(queue: q)
}
listener.stateUpdateHandler = { s in
    if case .ready = s { print("port: \(listener.port!.rawValue)"); fflush(stdout) }
}
listener.start(queue: q)
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
RunLoop.main.run()
