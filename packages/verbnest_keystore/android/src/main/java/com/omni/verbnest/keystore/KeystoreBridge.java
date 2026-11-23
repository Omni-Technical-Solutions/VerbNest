package com.omni.verbnest.keystore;

import android.app.Activity;
import android.content.Context;
import android.os.Build;
import android.security.KeyChain;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.Principal;
import java.security.PrivateKey;
import java.security.UnrecoverableKeyException;
import java.security.cert.Certificate;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executor;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.KeyManager;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLException;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSession;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509ExtendedKeyManager;
import javax.net.ssl.X509TrustManager;

/**
 * Identities held by the Android KeyStore or the system KeyChain, and loopback
 * relays that open TLS with one of them (FR-HTTP-013f). The private key is
 * used through its handle only: signing happens in the platform.
 */
final class KeystoreBridge {
    private final Map<String, Relay> sessions = new ConcurrentHashMap<>();

    interface Chosen { void done(Map<String, Object> identity, String error); }

    // ---- identities -------------------------------------------------------

    List<Map<String, Object>> identities() throws VerbnestKeystorePlugin.Failure {
        try {
            KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
            ks.load(null);
            List<Map<String, Object>> out = new ArrayList<>();
            for (String alias : Collections.list(ks.aliases())) {
                if (!ks.isKeyEntry(alias)) continue;
                Certificate c = ks.getCertificate(alias);
                if (c instanceof X509Certificate) out.add(describe("ks:" + alias, alias, (X509Certificate) c));
            }
            return out;
        } catch (Exception e) {
            throw new VerbnestKeystorePlugin.Failure("The keystore could not be read: " + e.getMessage());
        }
    }

    /** Imports a PKCS#12 file into the Android KeyStore; the key is then held by the system. */
    Map<String, Object> importPkcs12(byte[] bytes, String pass) throws VerbnestKeystorePlugin.Failure {
        if (bytes == null) throw new VerbnestKeystorePlugin.Failure("No file bytes.");
        try {
            KeyStore p12 = KeyStore.getInstance("PKCS12");
            try {
                p12.load(new ByteArrayInputStream(bytes), pass.toCharArray());
            } catch (IOException e) {
                if (e.getCause() instanceof UnrecoverableKeyException
                        || String.valueOf(e.getMessage()).toLowerCase().contains("password")) {
                    throw new VerbnestKeystorePlugin.Failure("The passphrase is wrong, or the file uses encryption this system does not support.");
                }
                throw new VerbnestKeystorePlugin.Failure("That is not a PKCS#12 file.");
            }
            String found = null;
            for (String a : Collections.list(p12.aliases())) {
                if (p12.isKeyEntry(a)) { found = a; break; }
            }
            if (found == null) throw new VerbnestKeystorePlugin.Failure("The file holds no certificate and key.");
            PrivateKey key = (PrivateKey) p12.getKey(found, pass.toCharArray());
            Certificate[] chain = p12.getCertificateChain(found);
            X509Certificate leaf = (X509Certificate) chain[0];
            String alias = "verbnest-" + fingerprint(leaf.getEncoded()).replace(":", "").substring(0, 16).toLowerCase();
            KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
            ks.load(null);
            ks.setKeyEntry(alias, key, null, chain);
            return describe("ks:" + alias, alias, leaf);
        } catch (VerbnestKeystorePlugin.Failure e) {
            throw e;
        } catch (Exception e) {
            throw new VerbnestKeystorePlugin.Failure("The file could not be imported: " + e.getMessage());
        }
    }

    /** Removes an identity this app imported (system-installed ones are not ours to delete). */
    void remove(String id) throws VerbnestKeystorePlugin.Failure {
        if (id == null || !id.startsWith("ks:")) {
            throw new VerbnestKeystorePlugin.Failure("Only identities imported into VerbNest can be removed here.");
        }
        try {
            KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
            ks.load(null);
            ks.deleteEntry(id.substring(3));
        } catch (Exception e) {
            throw new VerbnestKeystorePlugin.Failure("The identity could not be removed: " + e.getMessage());
        }
    }

    /** Shows the system's certificate chooser (installed credentials). */
    void choose(final Activity activity, final Chosen callback, final Executor work) {
        final Context context = activity.getApplicationContext();
        KeyChain.choosePrivateKeyAlias(activity, alias -> {
            if (alias == null) { callback.done(null, "No certificate was chosen."); return; }
            work.execute(() -> {
                try {
                    X509Certificate[] chain = KeyChain.getCertificateChain(context, alias);
                    if (chain == null || chain.length == 0) { callback.done(null, "The certificate is not available."); return; }
                    callback.done(describe("kc:" + alias, alias, chain[0]), null);
                } catch (Exception e) {
                    callback.done(null, "The certificate could not be read: " + e.getMessage());
                }
            });
        }, null, null, null, -1, null);
    }

    private Map<String, Object> describe(String id, String label, X509Certificate c) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        String dn = c.getSubjectX500Principal().getName();
        java.util.regex.Matcher cn = java.util.regex.Pattern.compile("(?:^|,)CN=([^,]+)").matcher(dn);
        m.put("label", cn.find() ? cn.group(1) : label);
        m.put("subject", dn);
        m.put("issuer", c.getIssuerX500Principal().getName());
        m.put("notAfter", isoDate(c.getNotAfter().getTime()));
        try { m.put("sha256", fingerprint(c.getEncoded())); } catch (Exception ignored) { }
        return m;
    }

    private static String isoDate(long millis) {
        java.text.SimpleDateFormat f = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US);
        f.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
        return f.format(new java.util.Date(millis));
    }

    static String fingerprint(byte[] der) throws Exception {
        byte[] d = MessageDigest.getInstance("SHA-256").digest(der);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < d.length; i++) {
            if (i > 0) sb.append(':');
            sb.append(String.format("%02X", d[i]));
        }
        return sb.toString();
    }

    // ---- relay ------------------------------------------------------------

    Map<String, Object> open(
            Context context, String host, int port, String identity, List<byte[]> cas,
            String minVersion, boolean verify, List<String> protocols
    ) throws VerbnestKeystorePlugin.Failure {
        PrivateKey key;
        X509Certificate[] chain;
        try {
            if (identity != null && identity.startsWith("ks:")) {
                KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
                ks.load(null);
                String alias = identity.substring(3);
                key = (PrivateKey) ks.getKey(alias, null);
                Certificate[] raw = ks.getCertificateChain(alias);
                chain = raw == null ? null : toX509(raw);
            } else if (identity != null && identity.startsWith("kc:")) {
                String alias = identity.substring(3);
                key = KeyChain.getPrivateKey(context, alias);
                chain = KeyChain.getCertificateChain(context, alias);
            } else {
                throw new VerbnestKeystorePlugin.Failure("Unknown identity.");
            }
        } catch (VerbnestKeystorePlugin.Failure e) {
            throw e;
        } catch (Exception e) {
            throw new VerbnestKeystorePlugin.Failure("The identity could not be opened: " + e.getMessage());
        }
        if (key == null || chain == null || chain.length == 0) {
            throw new VerbnestKeystorePlugin.Failure("The identity is not in the keystore any more. Choose it again in Settings > Network.");
        }

        long began = System.nanoTime();
        SSLSocket socket = null;
        try {
            SSLContext ctx = SSLContext.getInstance("TLS");
            ctx.init(new KeyManager[]{new FixedKeyManager(key, chain)},
                    new TrustManager[]{verify ? trustWith(cas) : new TrustAll()}, null);
            Socket raw = new Socket();
            raw.connect(new InetSocketAddress(host, port), 15000);
            socket = (SSLSocket) ctx.getSocketFactory().createSocket(raw, host, port, true);
            SSLParameters p = socket.getSSLParameters();
            if ("1.3".equals(minVersion)) {
                p.setProtocols(new String[]{"TLSv1.3"});
            } else {
                List<String> wanted = new ArrayList<>();
                for (String s : socket.getSupportedProtocols()) {
                    if (s.equals("TLSv1.2") || s.equals("TLSv1.3")) wanted.add(s);
                }
                p.setProtocols(wanted.toArray(new String[0]));
            }
            if (Build.VERSION.SDK_INT >= 29 && !protocols.isEmpty()) {
                p.setApplicationProtocols(protocols.toArray(new String[0]));
            }
            socket.setSSLParameters(p);
            socket.setSoTimeout(15000);
            socket.startHandshake();
            socket.setSoTimeout(0);
            SSLSession session = socket.getSession();
            if (verify && !HttpsURLConnection.getDefaultHostnameVerifier().verify(host, session)) {
                throw new VerbnestKeystorePlugin.Failure("The server certificate does not name " + host + ".");
            }
            Certificate[] peer = session.getPeerCertificates();
            String negotiated = null;
            if (Build.VERSION.SDK_INT >= 29) {
                String a = socket.getApplicationProtocol();
                if (a != null && !a.isEmpty()) negotiated = a;
            }
            double ms = (System.nanoTime() - began) / 1e6;
            ServerSocket server = new ServerSocket(0, 1, InetAddress.getByAddress(new byte[]{127, 0, 0, 1}));
            Relay relay = new Relay(server, socket);
            sessions.put(relay.id, relay);
            relay.start(() -> sessions.remove(relay.id));
            Map<String, Object> out = new HashMap<>();
            out.put("session", relay.id);
            out.put("port", server.getLocalPort());
            out.put("certificate", peer[0].getEncoded());
            if (negotiated != null) out.put("protocol", negotiated);
            out.put("handshakeMs", ms);
            return out;
        } catch (VerbnestKeystorePlugin.Failure e) {
            closeQuietly(socket);
            throw e;
        } catch (SSLException e) {
            closeQuietly(socket);
            Throwable c = e;
            while (c.getCause() != null) c = c.getCause();
            if (c instanceof CertificateException) {
                throw new VerbnestKeystorePlugin.Failure("The server certificate is not trusted: " + c.getMessage());
            }
            throw new VerbnestKeystorePlugin.Failure("TLS handshake failed: " + e.getMessage());
        } catch (Exception e) {
            closeQuietly(socket);
            throw new VerbnestKeystorePlugin.Failure("Cannot connect to " + host + ":" + port + ": " + e.getMessage());
        }
    }

    void close(String id) {
        Relay r = id == null ? null : sessions.remove(id);
        if (r != null) r.close();
    }

    void closeAll() {
        for (Relay r : sessions.values()) r.close();
        sessions.clear();
    }

    private static X509Certificate[] toX509(Certificate[] raw) {
        X509Certificate[] out = new X509Certificate[raw.length];
        for (int i = 0; i < raw.length; i++) out[i] = (X509Certificate) raw[i];
        return out;
    }

    private static void closeQuietly(Socket s) {
        if (s != null) try { s.close(); } catch (IOException ignored) { }
    }

    /** The system roots plus the CAs the person added (PEM or DER). */
    private static X509TrustManager trustWith(List<byte[]> cas) throws Exception {
        final X509TrustManager system = defaultTrust(null);
        if (cas.isEmpty()) return system;
        KeyStore extra = KeyStore.getInstance(KeyStore.getDefaultType());
        extra.load(null, null);
        CertificateFactory f = CertificateFactory.getInstance("X.509");
        int n = 0;
        for (byte[] b : cas) {
            Collection<? extends Certificate> certs = f.generateCertificates(new ByteArrayInputStream(b));
            for (Certificate c : certs) extra.setCertificateEntry("ca" + (n++), c);
        }
        final X509TrustManager custom = defaultTrust(extra);
        return new X509TrustManager() {
            @Override public void checkClientTrusted(X509Certificate[] chain, String type) throws CertificateException {
                system.checkClientTrusted(chain, type);
            }
            @Override public void checkServerTrusted(X509Certificate[] chain, String type) throws CertificateException {
                try { system.checkServerTrusted(chain, type); }
                catch (CertificateException first) { custom.checkServerTrusted(chain, type); }
            }
            @Override public X509Certificate[] getAcceptedIssuers() {
                List<X509Certificate> all = new ArrayList<>();
                Collections.addAll(all, system.getAcceptedIssuers());
                Collections.addAll(all, custom.getAcceptedIssuers());
                return all.toArray(new X509Certificate[0]);
            }
        };
    }

    private static X509TrustManager defaultTrust(KeyStore store) throws Exception {
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(store);
        for (TrustManager t : tmf.getTrustManagers()) if (t instanceof X509TrustManager) return (X509TrustManager) t;
        throw new IllegalStateException("No X509TrustManager");
    }

    /** Certificate checking is switched off for the request. */
    private static final class TrustAll implements X509TrustManager {
        @Override public void checkClientTrusted(X509Certificate[] c, String t) { }
        @Override public void checkServerTrusted(X509Certificate[] c, String t) { }
        @Override public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
    }

    /** Presents one key and chain whatever the server asks for. */
    private static final class FixedKeyManager extends X509ExtendedKeyManager {
        private final PrivateKey key;
        private final X509Certificate[] chain;
        FixedKeyManager(PrivateKey key, X509Certificate[] chain) { this.key = key; this.chain = chain; }
        @Override public String chooseClientAlias(String[] t, Principal[] i, Socket s) { return "verbnest"; }
        @Override public String chooseEngineClientAlias(String[] t, Principal[] i, javax.net.ssl.SSLEngine e) { return "verbnest"; }
        @Override public String[] getClientAliases(String t, Principal[] i) { return new String[]{"verbnest"}; }
        @Override public String chooseServerAlias(String t, Principal[] i, Socket s) { return null; }
        @Override public String[] getServerAliases(String t, Principal[] i) { return null; }
        @Override public X509Certificate[] getCertificateChain(String alias) { return chain; }
        @Override public PrivateKey getPrivateKey(String alias) { return key; }
    }

    /** One loopback listener that accepts a single connection and copies bytes both ways. */
    private static final class Relay {
        final String id = UUID.randomUUID().toString();
        private final ServerSocket server;
        private final SSLSocket upstream;
        private Socket inbound;

        Relay(ServerSocket server, SSLSocket upstream) { this.server = server; this.upstream = upstream; }

        void start(final Runnable onEnd) {
            Thread t = new Thread(() -> {
                try {
                    server.setSoTimeout(30000);
                    inbound = server.accept();
                    server.close();
                    Thread back = new Thread(() -> copy(upstream, inbound), "verbnest-relay-in");
                    back.setDaemon(true);
                    back.start();
                    copy(inbound, upstream);
                } catch (IOException ignored) {
                    // no connection came, or it ended
                } finally {
                    close();
                    onEnd.run();
                }
            }, "verbnest-relay");
            t.setDaemon(true);
            t.start();
        }

        private void copy(Socket from, Socket to) {
            byte[] buf = new byte[65536];
            try {
                InputStream in = from.getInputStream();
                OutputStream out = to.getOutputStream();
                int n;
                while ((n = in.read(buf)) >= 0) { out.write(buf, 0, n); out.flush(); }
            } catch (IOException ignored) {
                // closed
            } finally {
                close();
            }
        }

        void close() {
            try { server.close(); } catch (IOException ignored) { }
            closeQuietly(inbound);
            closeQuietly(upstream);
        }
    }
}
