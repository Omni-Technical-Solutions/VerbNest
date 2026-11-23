// Windows keystore bridge (FR-HTTP-013f phase K): certificates of the user's
// "MY" store whose keys sit in CNG (non-exportable, TPM, smart card), TLS by
// SChannel. Channel com.omni.verbnest/keystore. NOT BUILT OR TESTED YET: see
// docs/release/keystore-linux-windows.md.
#include "verbnest_keystore_plugin.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#define SECURITY_WIN32
#include <schannel.h>
#include <security.h>
#include <wincrypt.h>

#include <atomic>
#include <chrono>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace verbnest_keystore {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

struct Failure { std::string message; };

std::string Utf8(const std::wstring& w) {
  if (w.empty()) return "";
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0, nullptr, nullptr);
  std::string s(n, 0);
  WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n, nullptr, nullptr);
  return s;
}
std::wstring Wide(const std::string& s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
  return w;
}

std::string Sha256Hex(const BYTE* der, DWORD len) {
  BYTE hash[32];
  DWORD size = sizeof(hash);
  // CryptHashCertificate2 with the CNG SHA-256 provider.
  if (!CryptHashCertificate2(BCRYPT_SHA256_ALGORITHM, 0, nullptr, der, len, hash, &size)) return "";
  static const char* hex = "0123456789ABCDEF";
  std::string s;
  for (int i = 0; i < 32; i++) {
    if (i) s += ':';
    s += hex[hash[i] >> 4];
    s += hex[hash[i] & 15];
  }
  return s;
}

std::string CertName(PCCERT_CONTEXT c, DWORD type) {
  DWORD n = CertGetNameStringW(c, type, 0, nullptr, nullptr, 0);
  std::wstring w(n, 0);
  CertGetNameStringW(c, type, 0, nullptr, w.data(), n);
  if (!w.empty() && w.back() == 0) w.pop_back();
  return Utf8(w);
}

bool HasKey(PCCERT_CONTEXT c) {
  DWORD size = 0;
  return CertGetCertificateContextProperty(c, CERT_KEY_PROV_INFO_PROP_ID, nullptr, &size) != 0;
}

EncodableMap Describe(PCCERT_CONTEXT c) {
  std::string id = Sha256Hex(c->pbCertEncoded, c->cbCertEncoded);
  EncodableMap m;
  m[EncodableValue("id")] = EncodableValue(id);
  m[EncodableValue("label")] = EncodableValue(CertName(c, CERT_NAME_SIMPLE_DISPLAY_TYPE));
  m[EncodableValue("subject")] = EncodableValue(CertName(c, CERT_NAME_RDN_TYPE));
  m[EncodableValue("issuer")] = EncodableValue(CertName(c, CERT_NAME_ISSUER_FLAG));
  m[EncodableValue("sha256")] = EncodableValue(id);
  return m;
}

// The certificate (with its key) in "MY" whose SHA-256 is [id]; the caller frees it.
PCCERT_CONTEXT FindIdentity(const std::string& id) {
  HCERTSTORE store = CertOpenSystemStoreW(0, L"MY");
  if (!store) throw Failure{"The certificate store could not be opened."};
  PCCERT_CONTEXT found = nullptr;
  PCCERT_CONTEXT c = nullptr;
  while ((c = CertEnumCertificatesInStore(store, c)) != nullptr) {
    if (HasKey(c) && Sha256Hex(c->pbCertEncoded, c->cbCertEncoded) == id) {
      found = CertDuplicateCertificateContext(c);
      CertFreeCertificateContext(c);
      break;
    }
  }
  CertCloseStore(store, 0);
  if (!found)
    throw Failure{"The identity is not in the certificate store any more. Choose it again in Settings > Network."};
  return found;
}

EncodableList Identities() {
  EncodableList out;
  HCERTSTORE store = CertOpenSystemStoreW(0, L"MY");
  if (!store) return out;
  PCCERT_CONTEXT c = nullptr;
  while ((c = CertEnumCertificatesInStore(store, c)) != nullptr) {
    if (HasKey(c)) out.push_back(EncodableValue(Describe(c)));
  }
  CertCloseStore(store, 0);
  return out;
}

// Imports a PKCS#12 file into the user's "MY" store; the key stays non-exportable.
EncodableMap ImportPkcs12(const std::vector<uint8_t>& bytes, const std::string& pass) {
  CRYPT_DATA_BLOB blob{(DWORD)bytes.size(), const_cast<BYTE*>(bytes.data())};
  std::wstring wp = Wide(pass);
  HCERTSTORE pfx = PFXImportCertStore(&blob, wp.c_str(), CRYPT_USER_KEYSET);
  if (!pfx) {
    DWORD e = GetLastError();
    if (e == ERROR_INVALID_PASSWORD) throw Failure{"The passphrase is wrong, or the file uses encryption this system does not support."};
    throw Failure{"That is not a PKCS#12 file, or it could not be read."};
  }
  HCERTSTORE my = CertOpenSystemStoreW(0, L"MY");
  PCCERT_CONTEXT c = nullptr;
  PCCERT_CONTEXT keep = nullptr;
  while ((c = CertEnumCertificatesInStore(pfx, c)) != nullptr) {
    if (!HasKey(c)) continue;
    PCCERT_CONTEXT added = nullptr;
    if (CertAddCertificateContextToStore(my, c, CERT_STORE_ADD_REPLACE_EXISTING, &added)) {
      if (keep) CertFreeCertificateContext(keep);
      keep = added;
    }
  }
  CertCloseStore(pfx, 0);
  CertCloseStore(my, 0);
  if (!keep) throw Failure{"The file holds no certificate and key."};
  EncodableMap m = Describe(keep);
  CertFreeCertificateContext(keep);
  return m;
}

void RemoveIdentity(const std::string& id) {
  PCCERT_CONTEXT c = FindIdentity(id);
  // Best effort: delete the key as well as the certificate.
  HCRYPTPROV_OR_NCRYPT_KEY_HANDLE key = 0;
  DWORD spec = 0;
  BOOL free_key = FALSE;
  if (CryptAcquireCertificatePrivateKey(c, CRYPT_ACQUIRE_ONLY_NCRYPT_KEY_FLAG | CRYPT_ACQUIRE_SILENT_FLAG, nullptr,
                                        &key, &spec, &free_key) && spec == CERT_NCRYPT_KEY_SPEC) {
    NCryptDeleteKey(key, 0);
  }
  if (!CertDeleteCertificateFromStore(c)) throw Failure{"The identity could not be removed."};
}

// ---- relay ------------------------------------------------------------------

struct Relay {
  std::string id;
  SOCKET upstream = INVALID_SOCKET;
  SOCKET server = INVALID_SOCKET;
  CredHandle cred{};
  CtxtHandle ctx{};
  bool have_cred = false, have_ctx = false;
  SecPkgContext_StreamSizes sizes{};
  std::vector<BYTE> pending;  // received but not yet decrypted
  std::vector<uint8_t> certificate;
  std::string protocol;
  double handshake_ms = 0;
  int port = 0;
  std::atomic<bool> closing{false};
  std::thread worker;

  ~Relay() { Shutdown(); }
  void Shutdown() {
    if (closing.exchange(true)) return;
    if (server != INVALID_SOCKET) closesocket(server);
    if (upstream != INVALID_SOCKET) shutdown(upstream, SD_BOTH);
    if (worker.joinable()) worker.join();
    if (have_ctx) DeleteSecurityContext(&ctx);
    if (have_cred) FreeCredentialsHandle(&cred);
    if (upstream != INVALID_SOCKET) closesocket(upstream);
  }
};

std::mutex g_mutex;
std::map<std::string, std::shared_ptr<Relay>> g_sessions;

SOCKET ConnectTcp(const std::string& host, int port) {
  WSADATA d;
  WSAStartup(MAKEWORD(2, 2), &d);
  addrinfo hints{};
  hints.ai_socktype = SOCK_STREAM;
  addrinfo* res = nullptr;
  if (getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &res) != 0) return INVALID_SOCKET;
  SOCKET s = INVALID_SOCKET;
  for (addrinfo* a = res; a; a = a->ai_next) {
    s = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
    if (s == INVALID_SOCKET) continue;
    if (connect(s, a->ai_addr, (int)a->ai_addrlen) == 0) break;
    closesocket(s);
    s = INVALID_SOCKET;
  }
  freeaddrinfo(res);
  return s;
}

// Checks the server certificate against the system roots plus [cas], and the
// host name. SChannel is asked not to validate (manual mode) so the extra CAs
// can count as roots.
std::string ValidateServer(PCCERT_CONTEXT remote, const std::string& host, const std::vector<std::vector<uint8_t>>& cas) {
  HCERTSTORE roots = CertOpenStore(CERT_STORE_PROV_MEMORY, 0, 0, 0, nullptr);
  HCERTSTORE sys = CertOpenSystemStoreW(0, L"ROOT");
  PCCERT_CONTEXT c = nullptr;
  while (sys && (c = CertEnumCertificatesInStore(sys, c)) != nullptr)
    CertAddCertificateContextToStore(roots, c, CERT_STORE_ADD_USE_EXISTING, nullptr);
  if (sys) CertCloseStore(sys, 0);
  for (const auto& ca : cas)
    CertAddEncodedCertificateToStore(roots, X509_ASN_ENCODING, ca.data(), (DWORD)ca.size(),
                                     CERT_STORE_ADD_USE_EXISTING, nullptr);
  CERT_CHAIN_ENGINE_CONFIG cfg{};
  cfg.cbSize = sizeof(cfg);
  cfg.hExclusiveRoot = roots;
  HCERTCHAINENGINE engine = nullptr;
  std::string error;
  if (CertCreateCertificateChainEngine(&cfg, &engine)) {
    CERT_CHAIN_PARA para{};
    para.cbSize = sizeof(para);
    PCCERT_CHAIN_CONTEXT chain = nullptr;
    if (CertGetCertificateChain(engine, remote, nullptr, remote->hCertStore, &para, 0, nullptr, &chain)) {
      std::wstring name = Wide(host);
      SSL_EXTRA_CERT_CHAIN_POLICY_PARA ssl{};
      ssl.cbSize = sizeof(ssl);
      ssl.dwAuthType = AUTHTYPE_SERVER;
      ssl.pwszServerName = name.data();
      CERT_CHAIN_POLICY_PARA pol{};
      pol.cbSize = sizeof(pol);
      pol.pvExtraPolicyPara = &ssl;
      CERT_CHAIN_POLICY_STATUS status{};
      status.cbSize = sizeof(status);
      if (!CertVerifyCertificateChainPolicy(CERT_CHAIN_POLICY_SSL, chain, &pol, &status) || status.dwError != 0) {
        std::ostringstream o;
        o << "The server certificate is not trusted or does not name " << host << " (0x" << std::hex << status.dwError << ").";
        error = o.str();
      }
      CertFreeCertificateChain(chain);
    } else {
      error = "The server certificate chain could not be built.";
    }
    CertFreeCertificateChainEngine(engine);
  } else {
    error = "The certificate check could not be set up.";
  }
  CertCloseStore(roots, 0);
  return error;
}

bool SendAll(SOCKET s, const BYTE* data, int len) {
  int off = 0;
  while (off < len) {
    int n = send(s, reinterpret_cast<const char*>(data) + off, len - off, 0);
    if (n <= 0) return false;
    off += n;
  }
  return true;
}

// The SChannel client handshake. Returns an error text, empty on success.
std::string Handshake(Relay* r, const std::string& host, const std::vector<std::string>& protocols) {
  std::wstring target = Wide(host);
  // ALPN extension buffer.
  std::vector<BYTE> alpn(sizeof(SEC_APPLICATION_PROTOCOLS) + 4 + 256, 0);
  std::vector<BYTE> list;
  for (const auto& p : protocols) { list.push_back((BYTE)p.size()); list.insert(list.end(), p.begin(), p.end()); }
  auto* ap = reinterpret_cast<SEC_APPLICATION_PROTOCOLS*>(alpn.data());
  auto* entry = reinterpret_cast<SEC_APPLICATION_PROTOCOL_LIST*>(ap->ProtocolLists);
  entry->ProtoNegoExt = SecApplicationProtocolNegotiationExt_ALPN;
  entry->ProtocolListSize = (USHORT)list.size();
  memcpy(entry->ProtocolList, list.data(), list.size());
  ap->ProtocolListsSize = (ULONG)(sizeof(SEC_APPLICATION_PROTOCOL_LIST) - 1 + list.size() + 0);

  ULONG flags = ISC_REQ_SEQUENCE_DETECT | ISC_REQ_REPLAY_DETECT | ISC_REQ_CONFIDENTIALITY | ISC_RET_EXTENDED_ERROR |
                ISC_REQ_ALLOCATE_MEMORY | ISC_REQ_STREAM | ISC_REQ_MANUAL_CRED_VALIDATION;
  SecBuffer out_buf[1];
  SecBufferDesc out_desc{SECBUFFER_VERSION, 1, out_buf};
  ULONG attrs = 0;
  std::vector<BYTE> in;
  bool first = true;
  SECURITY_STATUS st = SEC_I_CONTINUE_NEEDED;
  while (st == SEC_I_CONTINUE_NEEDED || st == SEC_E_INCOMPLETE_MESSAGE) {
    SecBuffer in_buf[3] = {};
    SecBufferDesc in_desc{SECBUFFER_VERSION, 0, in_buf};
    int n_in = 0;
    if (!first) {
      if (st == SEC_E_INCOMPLETE_MESSAGE || in.empty()) {
        BYTE tmp[16384];
        int got = recv(r->upstream, reinterpret_cast<char*>(tmp), sizeof(tmp), 0);
        if (got <= 0) return "The server closed the connection during the handshake.";
        in.insert(in.end(), tmp, tmp + got);
      }
      in_buf[0] = {(ULONG)in.size(), SECBUFFER_TOKEN, in.data()};
      in_buf[1] = {0, SECBUFFER_EMPTY, nullptr};
      n_in = 2;
    } else {
      in_buf[0] = {ap->ProtocolListsSize + (ULONG)sizeof(ULONG) + (ULONG)sizeof(ULONG), SECBUFFER_APPLICATION_PROTOCOLS, alpn.data()};
      n_in = 1;
    }
    in_desc.cBuffers = n_in;
    out_buf[0] = {0, SECBUFFER_TOKEN, nullptr};
    st = InitializeSecurityContextW(&r->cred, first ? nullptr : &r->ctx, first ? target.data() : nullptr, flags, 0, 0,
                                    &in_desc, 0, first ? &r->ctx : nullptr, &out_desc, &attrs, nullptr);
    if (first) r->have_ctx = true;
    first = false;
    if (out_buf[0].cbBuffer && out_buf[0].pvBuffer) {
      bool ok = SendAll(r->upstream, static_cast<BYTE*>(out_buf[0].pvBuffer), (int)out_buf[0].cbBuffer);
      FreeContextBuffer(out_buf[0].pvBuffer);
      if (!ok) return "The connection was lost during the handshake.";
    }
    if (st == SEC_E_INCOMPLETE_MESSAGE) continue;
    // Keep bytes the handshake did not consume (they belong to the data phase).
    if (n_in == 2 && in_buf[1].BufferType == SECBUFFER_EXTRA && in_buf[1].cbBuffer > 0) {
      std::vector<BYTE> extra(in.end() - in_buf[1].cbBuffer, in.end());
      in = extra;
    } else if (st != SEC_E_INCOMPLETE_MESSAGE) {
      in.clear();
    }
    if (st != SEC_E_OK && st != SEC_I_CONTINUE_NEEDED) {
      std::ostringstream o;
      o << "TLS handshake failed (0x" << std::hex << (unsigned)st << ").";
      return o.str();
    }
  }
  r->pending = in;
  QueryContextAttributesW(&r->ctx, SECPKG_ATTR_STREAM_SIZES, &r->sizes);
  SecPkgContext_ApplicationProtocol app{};
  if (QueryContextAttributesW(&r->ctx, SECPKG_ATTR_APPLICATION_PROTOCOL, &app) == SEC_E_OK &&
      app.ProtoNegoStatus == SecApplicationProtocolNegotiationStatus_Success)
    r->protocol.assign(reinterpret_cast<char*>(app.ProtocolId), app.ProtocolIdSize);
  return "";
}

void Pump(Relay* r, SOCKET inbound) {
  std::vector<BYTE> buf(65536);
  std::vector<BYTE> enc;
  while (!r->closing) {
    // Wait for either side; do not wait when decrypted data may be pending.
    fd_set rd;
    FD_ZERO(&rd);
    FD_SET(inbound, &rd);
    FD_SET(r->upstream, &rd);
    timeval tv{0, r->pending.empty() ? 500000 : 0};
    int ready = select(0, &rd, nullptr, nullptr, &tv);
    bool from_app = ready > 0 && FD_ISSET(inbound, &rd);
    bool from_server = ready > 0 && FD_ISSET(r->upstream, &rd);
    if (!from_app && !from_server && r->pending.empty()) continue;

    if (from_app) {  // plain bytes from VerbNest: encrypt and send to the server
      int n = recv(inbound, reinterpret_cast<char*>(buf.data()),
                   (int)std::min<size_t>(buf.size(), r->sizes.cbMaximumMessage), 0);
      if (n <= 0) break;
      enc.assign(r->sizes.cbHeader + n + r->sizes.cbTrailer, 0);
      memcpy(enc.data() + r->sizes.cbHeader, buf.data(), n);
      SecBuffer b[4] = {{r->sizes.cbHeader, SECBUFFER_STREAM_HEADER, enc.data()},
                        {(ULONG)n, SECBUFFER_DATA, enc.data() + r->sizes.cbHeader},
                        {r->sizes.cbTrailer, SECBUFFER_STREAM_TRAILER, enc.data() + r->sizes.cbHeader + n},
                        {0, SECBUFFER_EMPTY, nullptr}};
      SecBufferDesc d{SECBUFFER_VERSION, 4, b};
      if (EncryptMessage(&r->ctx, 0, &d, 0) != SEC_E_OK) break;
      if (!SendAll(r->upstream, enc.data(), (int)(b[0].cbBuffer + b[1].cbBuffer + b[2].cbBuffer))) break;
    }

    if (from_server) {  // TLS records from the server: collect them
      BYTE tmp[16384];
      int got = recv(r->upstream, reinterpret_cast<char*>(tmp), sizeof(tmp), 0);
      if (got <= 0) break;
      r->pending.insert(r->pending.end(), tmp, tmp + got);
    }

    // Decrypt every complete record we hold and hand the plain bytes to VerbNest.
    while (!r->pending.empty()) {
      SecBuffer b[4] = {{(ULONG)r->pending.size(), SECBUFFER_DATA, r->pending.data()}, {}, {}, {}};
      SecBufferDesc d{SECBUFFER_VERSION, 4, b};
      SECURITY_STATUS s = DecryptMessage(&r->ctx, &d, 0, nullptr);
      if (s == SEC_E_INCOMPLETE_MESSAGE) break;
      if (s != SEC_E_OK) { r->closing = true; break; }
      SecBuffer* data = nullptr;
      SecBuffer* extra = nullptr;
      for (auto& x : b) {
        if (x.BufferType == SECBUFFER_DATA) data = &x;
        if (x.BufferType == SECBUFFER_EXTRA) extra = &x;
      }
      if (data && data->cbBuffer && !SendAll(inbound, static_cast<BYTE*>(data->pvBuffer), (int)data->cbBuffer)) {
        r->closing = true;
        break;
      }
      if (extra && extra->cbBuffer) {
        std::vector<BYTE> rest(r->pending.end() - extra->cbBuffer, r->pending.end());
        r->pending = rest;
      } else {
        r->pending.clear();
      }
    }
  }
  closesocket(inbound);
}

std::shared_ptr<Relay> OpenRelay(const std::string& host, int port, const std::string& identity,
                                 const std::vector<std::vector<uint8_t>>& cas, const std::string& min_version,
                                 bool verify, const std::vector<std::string>& protocols) {
  PCCERT_CONTEXT cert = FindIdentity(identity);
  auto r = std::make_shared<Relay>();
  auto t0 = std::chrono::steady_clock::now();
  SCH_CREDENTIALS creds{};
  creds.dwVersion = SCH_CREDENTIALS_VERSION;
  creds.cCreds = 1;
  creds.paCred = &cert;
  creds.dwFlags = SCH_CRED_MANUAL_CRED_VALIDATION | SCH_CRED_NO_DEFAULT_CREDS | SCH_USE_STRONG_CRYPTO;
  TLS_PARAMETERS tls{};
  // Never TLS 1.0 / 1.1 (or SSL); 1.2 too when 1.3 is the minimum.
  tls.grbitDisabledProtocols = SP_PROT_SSL3_CLIENT | SP_PROT_TLS1_0_CLIENT | SP_PROT_TLS1_1_CLIENT;
  if (min_version == "1.3") tls.grbitDisabledProtocols |= SP_PROT_TLS1_2_CLIENT;
  creds.cTlsParameters = 1;
  creds.pTlsParameters = &tls;
  SECURITY_STATUS st = AcquireCredentialsHandleW(nullptr, const_cast<LPWSTR>(UNISP_NAME_W), SECPKG_CRED_OUTBOUND, nullptr,
                                                 &creds, nullptr, nullptr, &r->cred, nullptr);
  CertFreeCertificateContext(cert);
  if (st != SEC_E_OK) {
    std::ostringstream o;
    o << "The identity could not be used for TLS (0x" << std::hex << (unsigned)st << "). Is the card present and unlocked?";
    throw Failure{o.str()};
  }
  r->have_cred = true;
  r->upstream = ConnectTcp(host, port);
  if (r->upstream == INVALID_SOCKET) throw Failure{"Cannot connect to " + host + ":" + std::to_string(port) + "."};
  std::string err = Handshake(r.get(), host, protocols);
  if (!err.empty()) throw Failure{err};
  PCCERT_CONTEXT remote = nullptr;
  if (QueryContextAttributesW(&r->ctx, SECPKG_ATTR_REMOTE_CERT_CONTEXT, &remote) != SEC_E_OK || !remote)
    throw Failure{"The server presented no certificate."};
  r->certificate.assign(remote->pbCertEncoded, remote->pbCertEncoded + remote->cbCertEncoded);
  if (verify) {
    std::string bad = ValidateServer(remote, host, cas);
    if (!bad.empty()) { CertFreeCertificateContext(remote); throw Failure{bad}; }
  }
  CertFreeCertificateContext(remote);
  r->handshake_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();

  r->server = socket(AF_INET, SOCK_STREAM, 0);
  sockaddr_in a{};
  a.sin_family = AF_INET;
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(r->server, reinterpret_cast<sockaddr*>(&a), sizeof(a)) != 0 || listen(r->server, 1) != 0)
    throw Failure{"Could not open the local relay port."};
  int len = sizeof(a);
  getsockname(r->server, reinterpret_cast<sockaddr*>(&a), &len);
  r->port = ntohs(a.sin_port);
  Relay* raw = r.get();
  r->worker = std::thread([raw]() {
    fd_set rd;
    FD_ZERO(&rd);
    FD_SET(raw->server, &rd);
    timeval tv{30, 0};
    if (select(0, &rd, nullptr, nullptr, &tv) > 0) {
      SOCKET c = accept(raw->server, nullptr, nullptr);
      if (c != INVALID_SOCKET) Pump(raw, c);
    }
  });
  return r;
}

// ---- channel ----------------------------------------------------------------

const EncodableMap* Args(const flutter::MethodCall<EncodableValue>& call) {
  return std::get_if<EncodableMap>(call.arguments());
}
std::string Str(const EncodableMap* a, const char* k) {
  if (!a) return "";
  auto it = a->find(EncodableValue(k));
  if (it == a->end()) return "";
  const auto* s = std::get_if<std::string>(&it->second);
  return s ? *s : "";
}

}  // namespace

void VerbnestKeystorePlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "com.omni.verbnest/keystore", &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<VerbnestKeystorePlugin>();
  channel->SetMethodCallHandler([p = plugin.get()](const auto& call, auto result) {
    p->HandleMethodCall(call, std::move(result));
  });
  registrar->AddPlugin(std::move(plugin));
  // The channel lives as long as the registrar's plugin; keep it alive.
  static std::unique_ptr<flutter::MethodChannel<EncodableValue>> keep;
  keep = std::move(channel);
}

void VerbnestKeystorePlugin::HandleMethodCall(const flutter::MethodCall<EncodableValue>& call,
                                              std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& name = call.method_name();
  const EncodableMap* args = Args(call);
  try {
    if (name == "supported") {
      result->Success(EncodableValue(true));
    } else if (name == "identities") {
      result->Success(EncodableValue(Identities()));
    } else if (name == "import") {
      auto it = args ? args->find(EncodableValue("bytes")) : EncodableMap().end();
      const auto* bytes = args && it != args->end() ? std::get_if<std::vector<uint8_t>>(&it->second) : nullptr;
      if (!bytes) throw Failure{"No file bytes."};
      result->Success(EncodableValue(ImportPkcs12(*bytes, Str(args, "passphrase"))));
    } else if (name == "remove") {
      RemoveIdentity(Str(args, "identity"));
      result->Success();
    } else if (name == "close") {
      std::shared_ptr<Relay> r;
      {
        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_sessions.find(Str(args, "session"));
        if (it != g_sessions.end()) { r = it->second; g_sessions.erase(it); }
      }
      result->Success();
    } else if (name == "open") {
      // The handshake blocks; run it off the platform thread and answer when done.
      std::shared_ptr<flutter::MethodResult<EncodableValue>> shared(std::move(result));
      std::string host = Str(args, "host"), identity = Str(args, "identity"), minv = Str(args, "minVersion");
      int port = 443;
      bool verify = true;
      std::vector<std::vector<uint8_t>> cas;
      std::vector<std::string> protocols;
      if (args) {
        auto p = args->find(EncodableValue("port"));
        if (p != args->end()) if (const auto* v = std::get_if<int32_t>(&p->second)) port = *v;
        auto v = args->find(EncodableValue("verify"));
        if (v != args->end()) if (const auto* b = std::get_if<bool>(&v->second)) verify = *b;
        auto c = args->find(EncodableValue("cas"));
        if (c != args->end()) if (const auto* l = std::get_if<EncodableList>(&c->second))
          for (const auto& e : *l) if (const auto* b = std::get_if<std::vector<uint8_t>>(&e)) cas.push_back(*b);
        auto pr = args->find(EncodableValue("protocols"));
        if (pr != args->end()) if (const auto* l = std::get_if<EncodableList>(&pr->second))
          for (const auto& e : *l) if (const auto* s = std::get_if<std::string>(&e)) protocols.push_back(*s);
      }
      std::thread([shared, host, identity, minv, port, verify, cas, protocols]() {
        try {
          auto r = OpenRelay(host, port, identity, cas, minv, verify, protocols);
          r->id = identity + "#" + std::to_string(r->port);
          EncodableMap m;
          m[EncodableValue("session")] = EncodableValue(r->id);
          m[EncodableValue("port")] = EncodableValue(r->port);
          m[EncodableValue("handshakeMs")] = EncodableValue(r->handshake_ms);
          m[EncodableValue("certificate")] = EncodableValue(r->certificate);
          if (!r->protocol.empty()) m[EncodableValue("protocol")] = EncodableValue(r->protocol);
          { std::lock_guard<std::mutex> lock(g_mutex); g_sessions[r->id] = r; }
          shared->Success(EncodableValue(m));
        } catch (const Failure& f) {
          shared->Error("keystore", f.message);
        }
      }).detach();
    } else {
      result->NotImplemented();
    }
  } catch (const Failure& f) {
    if (result) result->Error("keystore", f.message);
  }
}

}  // namespace verbnest_keystore
