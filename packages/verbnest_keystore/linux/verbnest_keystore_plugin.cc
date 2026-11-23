// Linux keystore bridge (FR-HTTP-013f phase J): PKCS#11 tokens and the NSS /
// p11-kit modules the system knows, through GnuTLS. Channel
// com.omni.verbnest/keystore: supported, identities, import, remove, open,
// close. NOT BUILT OR TESTED YET: see docs/release/keystore-linux-windows.md.
#include "include/verbnest_keystore/verbnest_keystore_plugin.h"

#include <gnutls/gnutls.h>
#include <gnutls/pkcs11.h>
#include <gnutls/x509.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

struct Failure {
  std::string message;
};

std::string sha256_hex(const gnutls_datum_t& der) {
  unsigned char out[32];
  size_t n = sizeof(out);
  gnutls_hash_fast(GNUTLS_DIG_SHA256, der.data, der.size, out);
  (void)n;
  static const char* hex = "0123456789ABCDEF";
  std::string s;
  for (int i = 0; i < 32; i++) {
    if (i) s += ':';
    s += hex[out[i] >> 4];
    s += hex[out[i] & 15];
  }
  return s;
}

// ---- identities -----------------------------------------------------------

struct Identity {
  std::string url;  // pkcs11: URL of the certificate; the key shares its id
  std::string label;
  std::string subject;
  std::string sha256;
};

std::vector<Identity> list_identities() {
  std::vector<Identity> out;
  gnutls_pkcs11_obj_t* objs = nullptr;
  unsigned int n = 0;
  int r = gnutls_pkcs11_obj_list_import_url4(
      &objs, &n, "pkcs11:type=cert",
      GNUTLS_PKCS11_OBJ_FLAG_CRT | GNUTLS_PKCS11_OBJ_FLAG_LOGIN);
  if (r < 0) return out;
  for (unsigned int i = 0; i < n; i++) {
    gnutls_x509_crt_t crt = nullptr;
    if (gnutls_x509_crt_init(&crt) < 0) continue;
    char* url = nullptr;
    if (gnutls_pkcs11_obj_export_url(objs[i], GNUTLS_PKCS11_URL_GENERIC, &url) >= 0 &&
        gnutls_x509_crt_import_pkcs11(crt, objs[i]) >= 0) {
      gnutls_datum_t der{};
      gnutls_datum_t dn{};
      if (gnutls_x509_crt_export2(crt, GNUTLS_X509_FMT_DER, &der) >= 0) {
        gnutls_x509_crt_get_dn3(crt, &dn, 0);
        Identity id;
        id.url = url;
        id.subject = dn.data ? std::string(reinterpret_cast<char*>(dn.data), dn.size) : "";
        char label[256];
        size_t len = sizeof(label);
        id.label = gnutls_pkcs11_obj_get_info(objs[i], GNUTLS_PKCS11_OBJ_LABEL, label, &len) >= 0
                       ? std::string(label)
                       : id.subject;
        id.sha256 = sha256_hex(der);
        out.push_back(id);
        gnutls_free(der.data);
        gnutls_free(dn.data);
      }
    }
    gnutls_free(url);
    gnutls_x509_crt_deinit(crt);
    gnutls_pkcs11_obj_deinit(objs[i]);
  }
  gnutls_free(objs);
  return out;
}

// The key of a certificate URL: same token and id, type=private.
std::string key_url_for(const std::string& cert_url) {
  std::string u = cert_url;
  auto p = u.find("type=cert");
  if (p != std::string::npos) u.replace(p, 9, "type=private");
  else u += ";type=private";
  return u;
}

// ---- relay ----------------------------------------------------------------

struct Relay {
  std::string id;
  gnutls_session_t session = nullptr;
  gnutls_certificate_credentials_t cred = nullptr;
  int upstream = -1;
  int server = -1;
  std::atomic<bool> closing{false};
  std::thread worker;
  std::vector<unsigned char> certificate;
  std::string protocol;
  double handshake_ms = 0;
  int port = 0;

  ~Relay() { shutdown(); }

  void shutdown() {
    if (closing.exchange(true)) return;
    if (server >= 0) ::shutdown(server, SHUT_RDWR);
    if (upstream >= 0) ::shutdown(upstream, SHUT_RDWR);
    if (worker.joinable()) worker.join();
    if (session) gnutls_deinit(session);
    if (cred) gnutls_certificate_free_credentials(cred);
    if (server >= 0) ::close(server);
    if (upstream >= 0) ::close(upstream);
    session = nullptr;
    cred = nullptr;
  }
};

std::mutex sessions_mutex;
std::map<std::string, std::shared_ptr<Relay>> sessions;

int connect_tcp(const std::string& host, int port) {
  addrinfo hints{};
  hints.ai_socktype = SOCK_STREAM;
  addrinfo* res = nullptr;
  if (getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &res) != 0) return -1;
  int fd = -1;
  for (addrinfo* a = res; a; a = a->ai_next) {
    fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
    if (fd < 0) continue;
    if (connect(fd, a->ai_addr, a->ai_addrlen) == 0) break;
    ::close(fd);
    fd = -1;
  }
  freeaddrinfo(res);
  return fd;
}

// Copies bytes between the loopback socket and the TLS session until either
// side closes.
void pump(Relay* r, int inbound) {
  unsigned char buf[65536];
  while (!r->closing) {
    pollfd fds[2] = {{inbound, POLLIN, 0}, {r->upstream, POLLIN, 0}};
    bool pending = gnutls_record_check_pending(r->session) > 0;
    if (!pending && poll(fds, 2, 500) <= 0) continue;
    if (fds[0].revents & (POLLIN | POLLHUP)) {
      ssize_t n = ::recv(inbound, buf, sizeof(buf), 0);
      if (n <= 0) break;
      ssize_t off = 0;
      while (off < n) {
        ssize_t w = gnutls_record_send(r->session, buf + off, n - off);
        if (w == GNUTLS_E_AGAIN || w == GNUTLS_E_INTERRUPTED) continue;
        if (w < 0) { off = -1; break; }
        off += w;
      }
      if (off < 0) break;
    }
    if (pending || (fds[1].revents & (POLLIN | POLLHUP))) {
      ssize_t n = gnutls_record_recv(r->session, buf, sizeof(buf));
      if (n == GNUTLS_E_AGAIN || n == GNUTLS_E_INTERRUPTED) continue;
      if (n <= 0) break;
      ssize_t off = 0;
      while (off < n) {
        ssize_t w = ::send(inbound, buf + off, n - off, MSG_NOSIGNAL);
        if (w <= 0) { off = -1; break; }
        off += w;
      }
      if (off < 0) break;
    }
  }
  ::close(inbound);
}

std::shared_ptr<Relay> open_relay(const std::string& host, int port, const std::string& identity,
                                  const std::vector<std::string>& cas, const std::string& min_version,
                                  bool verify, const std::vector<std::string>& protocols) {
  auto r = std::make_shared<Relay>();
  auto t0 = std::chrono::steady_clock::now();
  int rc = gnutls_certificate_allocate_credentials(&r->cred);
  if (rc < 0) throw Failure{"TLS could not be set up."};
  gnutls_certificate_set_x509_system_trust(r->cred);
  for (const auto& pem : cas) {
    gnutls_datum_t d{reinterpret_cast<unsigned char*>(const_cast<char*>(pem.data())),
                     static_cast<unsigned int>(pem.size())};
    if (gnutls_certificate_set_x509_trust_mem(r->cred, &d, GNUTLS_X509_FMT_PEM) <= 0)
      gnutls_certificate_set_x509_trust_mem(r->cred, &d, GNUTLS_X509_FMT_DER);
  }
  rc = gnutls_certificate_set_x509_key_file(r->cred, identity.c_str(), key_url_for(identity).c_str(),
                                            GNUTLS_X509_FMT_DER);
  if (rc < 0)
    throw Failure{std::string("The identity could not be opened (is the token present and unlocked?): ") +
                  gnutls_strerror(rc)};
  gnutls_init(&r->session, GNUTLS_CLIENT);
  std::string prio = "NORMAL:-VERS-TLS1.0:-VERS-TLS1.1";
  if (min_version == "1.3") prio += ":-VERS-TLS1.2";
  gnutls_priority_set_direct(r->session, prio.c_str(), nullptr);
  gnutls_credentials_set(r->session, GNUTLS_CRD_CERTIFICATE, r->cred);
  gnutls_server_name_set(r->session, GNUTLS_NAME_DNS, host.c_str(), host.size());
  if (verify) gnutls_session_set_verify_cert(r->session, host.c_str(), 0);
  std::vector<gnutls_datum_t> alpn;
  for (const auto& p : protocols)
    alpn.push_back({reinterpret_cast<unsigned char*>(const_cast<char*>(p.data())),
                    static_cast<unsigned int>(p.size())});
  if (!alpn.empty()) gnutls_alpn_set_protocols(r->session, alpn.data(), alpn.size(), 0);
  r->upstream = connect_tcp(host, port);
  if (r->upstream < 0) throw Failure{"Cannot connect to " + host + ":" + std::to_string(port) + "."};
  gnutls_transport_set_int(r->session, r->upstream);
  do {
    rc = gnutls_handshake(r->session);
  } while (rc < 0 && gnutls_error_is_fatal(rc) == 0);
  if (rc < 0) {
    std::string why = gnutls_strerror(rc);
    if (rc == GNUTLS_E_CERTIFICATE_VERIFICATION_ERROR) {
      gnutls_datum_t out{};
      gnutls_certificate_verification_status_print(gnutls_session_get_verify_cert_status(r->session),
                                                   gnutls_certificate_type_get(r->session), &out, 0);
      if (out.data) why = std::string(reinterpret_cast<char*>(out.data), out.size);
      gnutls_free(out.data);
      throw Failure{"The server certificate is not trusted: " + why};
    }
    throw Failure{"TLS handshake failed: " + why};
  }
  unsigned int n = 0;
  const gnutls_datum_t* peer = gnutls_certificate_get_peers(r->session, &n);
  if (peer && n > 0) r->certificate.assign(peer[0].data, peer[0].data + peer[0].size);
  gnutls_datum_t chosen{};
  if (gnutls_alpn_get_selected_protocol(r->session, &chosen) >= 0 && chosen.data)
    r->protocol.assign(reinterpret_cast<char*>(chosen.data), chosen.size);
  r->handshake_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();

  r->server = socket(AF_INET, SOCK_STREAM, 0);
  sockaddr_in a{};
  a.sin_family = AF_INET;
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(r->server, reinterpret_cast<sockaddr*>(&a), sizeof(a)) < 0 || listen(r->server, 1) < 0)
    throw Failure{"Could not open the local relay port."};
  socklen_t len = sizeof(a);
  getsockname(r->server, reinterpret_cast<sockaddr*>(&a), &len);
  r->port = ntohs(a.sin_port);
  Relay* raw = r.get();
  r->worker = std::thread([raw]() {
    pollfd p{raw->server, POLLIN, 0};
    if (poll(&p, 1, 30000) > 0) {
      int c = accept(raw->server, nullptr, nullptr);
      if (c >= 0) pump(raw, c);
    }
  });
  return r;
}

// ---- channel --------------------------------------------------------------

const char* str_arg(FlValue* args, const char* key) {
  FlValue* v = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, key) : nullptr;
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING ? fl_value_get_string(v) : "";
}

FlMethodResponse* failure(const std::string& m) {
  return FL_METHOD_RESPONSE(fl_method_error_response_new("keystore", m.c_str(), nullptr));
}

FlValue* identity_value(const Identity& i) {
  FlValue* m = fl_value_new_map();
  fl_value_set_string_take(m, "id", fl_value_new_string(i.url.c_str()));
  fl_value_set_string_take(m, "label", fl_value_new_string(i.label.c_str()));
  fl_value_set_string_take(m, "subject", fl_value_new_string(i.subject.c_str()));
  fl_value_set_string_take(m, "sha256", fl_value_new_string(i.sha256.c_str()));
  return m;
}

struct OpenJob {
  FlMethodCall* call;
  std::string host, identity, min_version;
  int port;
  bool verify;
  std::vector<std::string> cas, protocols;
  std::shared_ptr<Relay> relay;
  std::string error;
};

gboolean finish_open(gpointer data) {
  auto* job = static_cast<OpenJob*>(data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (!job->error.empty()) {
    response = failure(job->error);
  } else {
    FlValue* m = fl_value_new_map();
    fl_value_set_string_take(m, "session", fl_value_new_string(job->relay->id.c_str()));
    fl_value_set_string_take(m, "port", fl_value_new_int(job->relay->port));
    fl_value_set_string_take(m, "handshakeMs", fl_value_new_float(job->relay->handshake_ms));
    if (!job->relay->certificate.empty())
      fl_value_set_string_take(m, "certificate",
                               fl_value_new_uint8_list(job->relay->certificate.data(), job->relay->certificate.size()));
    if (!job->relay->protocol.empty())
      fl_value_set_string_take(m, "protocol", fl_value_new_string(job->relay->protocol.c_str()));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(m));
    fl_value_unref(m);
  }
  fl_method_call_respond(job->call, response, nullptr);
  g_object_unref(job->call);
  delete job;
  return G_SOURCE_REMOVE;
}

void method_call_cb(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(name, "supported") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
  } else if (g_strcmp0(name, "identities") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    for (const auto& i : list_identities()) fl_value_append_take(list, identity_value(i));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else if (g_strcmp0(name, "import") == 0 || g_strcmp0(name, "remove") == 0) {
    response = failure(
        "This system's keystore is managed outside VerbNest: add the certificate to your PKCS#11 token or NSS "
        "database (for example with p11tool or pk12util), then choose it here.");
  } else if (g_strcmp0(name, "close") == 0) {
    std::shared_ptr<Relay> r;
    {
      std::lock_guard<std::mutex> lock(sessions_mutex);
      auto it = sessions.find(str_arg(args, "session"));
      if (it != sessions.end()) { r = it->second; sessions.erase(it); }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(name, "open") == 0) {
    auto* job = new OpenJob();
    job->call = FL_METHOD_CALL(g_object_ref(call));
    job->host = str_arg(args, "host");
    job->identity = str_arg(args, "identity");
    FlValue* mv = fl_value_lookup_string(args, "minVersion");
    job->min_version = mv && fl_value_get_type(mv) == FL_VALUE_TYPE_STRING ? fl_value_get_string(mv) : "";
    job->port = static_cast<int>(fl_value_get_int(fl_value_lookup_string(args, "port")));
    job->verify = fl_value_get_bool(fl_value_lookup_string(args, "verify"));
    FlValue* cas = fl_value_lookup_string(args, "cas");
    for (size_t i = 0; cas && i < fl_value_get_length(cas); i++) {
      FlValue* c = fl_value_get_list_value(cas, i);
      job->cas.emplace_back(reinterpret_cast<const char*>(fl_value_get_uint8_list(c)), fl_value_get_length(c));
    }
    FlValue* ps = fl_value_lookup_string(args, "protocols");
    for (size_t i = 0; ps && i < fl_value_get_length(ps); i++)
      job->protocols.emplace_back(fl_value_get_string(fl_value_get_list_value(ps, i)));
    std::thread([job]() {
      try {
        job->relay = open_relay(job->host, job->port, job->identity, job->cas, job->min_version, job->verify,
                                job->protocols);
        job->relay->id = job->identity + "#" + std::to_string(job->relay->port);
        std::lock_guard<std::mutex> lock(sessions_mutex);
        sessions[job->relay->id] = job->relay;
      } catch (const Failure& f) {
        job->error = f.message;
      }
      g_idle_add(finish_open, job);
    }).detach();
    return;  // answered from finish_open
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void verbnest_keystore_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                                                   "com.omni.verbnest/keystore", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr, nullptr);
  g_object_unref(channel);
}
