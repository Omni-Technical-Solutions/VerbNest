import 'dart:convert';
import 'dart:io';

import 'byte_reader.dart';
import 'errors.dart';
import 'proxy.dart';

/// `Basic` credentials for a proxy's `Proxy-Authorization` header.
String basicProxyAuth(ProxyConfig p) =>
    'Basic ${base64Encode(utf8.encode('${p.username}:${p.password}'))}';

String hostPort(String host, int port) =>
    '${host.contains(':') ? '[$host]' : host}:$port';

/// Opens a tunnel through an HTTP proxy with CONNECT.
Future<void> httpConnectTunnel(
  Socket socket,
  ByteReader reader,
  ProxyConfig proxy,
  String host,
  int port,
) async {
  final hp = hostPort(host, port);
  socket.add(
    utf8.encode(
      'CONNECT $hp HTTP/1.1\r\nHost: $hp\r\n'
      '${proxy.hasAuth ? 'Proxy-Authorization: ${basicProxyAuth(proxy)}\r\n' : ''}'
      '\r\n',
    ),
  );
  await socket.flush();
  final head = await reader.readHead();
  if (head == null) {
    throw const NetworkError('The proxy closed the connection');
  }
  final line = latin1.decode(head).split('\r\n').first;
  final parts = line.split(' ');
  final code = parts.length > 1 ? int.tryParse(parts[1]) : null;
  if (code == null || code < 200 || code >= 300) {
    throw NetworkError('The proxy refused the tunnel: $line');
  }
}

/// SOCKS5 handshake (RFC 1928, user/password per RFC 1929). The proxy
/// resolves [host], so DNS does not leak.
Future<void> socks5Handshake(
  Socket socket,
  ByteReader reader,
  ProxyConfig proxy,
  String host,
  int port,
) async {
  socket.add(proxy.hasAuth ? [5, 2, 0, 2] : [5, 1, 0]);
  await socket.flush();
  final choice = await reader.readExact(2);
  if (choice[0] != 5) throw const NetworkError('Not a SOCKS5 proxy');
  if (choice[1] == 0xFF) {
    throw const NetworkError(
      'The SOCKS5 proxy accepts none of our log-in methods',
    );
  }
  if (choice[1] == 2) {
    if (!proxy.hasAuth) {
      throw const NetworkError(
        'The SOCKS5 proxy needs a user name and password',
      );
    }
    final user = utf8.encode(proxy.username);
    final pass = utf8.encode(proxy.password);
    if (user.length > 255 || pass.length > 255) {
      throw const NetworkError('The proxy user name or password is too long');
    }
    socket.add([1, user.length, ...user, pass.length, ...pass]);
    await socket.flush();
    final ok = await reader.readExact(2);
    if (ok[1] != 0) {
      throw const NetworkError(
        'The SOCKS5 proxy rejected the user name or password',
      );
    }
  }
  final ip = InternetAddress.tryParse(host);
  final addr = ip != null
      ? [ip.type == InternetAddressType.IPv4 ? 1 : 4, ...ip.rawAddress]
      : [3, utf8.encode(host).length, ...utf8.encode(host)];
  if (ip == null && utf8.encode(host).length > 255) {
    throw const NetworkError('The host name is too long for SOCKS5');
  }
  socket.add([5, 1, 0, ...addr, port >> 8, port & 0xFF]);
  await socket.flush();
  final reply = await reader.readExact(4);
  if (reply[1] != 0) {
    const reasons = {
      1: 'general failure',
      2: 'not allowed by the proxy rules',
      3: 'network unreachable',
      4: 'host unreachable',
      5: 'connection refused',
      6: 'TTL expired',
      7: 'command not supported',
      8: 'address type not supported',
    };
    throw NetworkError(
      'The SOCKS5 proxy could not connect: ${reasons[reply[1]] ?? 'error ${reply[1]}'}',
    );
  }
  final skip = switch (reply[3]) {
    1 => 4,
    4 => 16,
    3 => (await reader.readExact(1))[0],
    _ => throw const NetworkError('Unexpected SOCKS5 reply'),
  };
  await reader.readExact(skip + 2);
}
