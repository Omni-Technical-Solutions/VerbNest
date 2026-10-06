import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_http/verbnest_http.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled SQLite supports FTS5 trigram search', (tester) async {
    final s = WorkspaceSession.memory();
    addTearDown(s.close);
    final col = s.repo.createCollection('C');
    s.repo.createRequest(
      col,
      HttpRequestItem(id: '', name: 'R', url: 'http://x.test/needle-xyz'),
    );
    final index = SearchIndex(s.repo)..rebuild();
    expect(index.search('needle'), isNotEmpty);
  });

  testWidgets('engine sends a request to a loopback server', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      final body = await utf8.decodeStream(req);
      req.response
        ..statusCode = 201
        ..write('${req.method} ${req.uri.path} $body');
      await req.response.close();
    });
    final r = await HttpEngine().send(
      HttpRequestSpec(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:${server.port}/p'),
        body: utf8.encode('hi'),
      ),
    );
    expect(r.status, 201);
    expect(utf8.decode(r.body), 'POST /p hi');
  });

  testWidgets('10,000-request workspace opens and searches quickly', (
    tester,
  ) async {
    final dir = await WorkspaceSession.workspacesDir();
    final path =
        '${dir.path}/itest-scale-${DateTime.now().millisecondsSinceEpoch}.verbnest';
    addTearDown(() {
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$path$suffix');
        if (f.existsSync()) f.deleteSync();
      }
    });
    final first = await WorkspaceSession.openFile(path, create: true);
    final col = first.repo.createCollection('Big');
    final fill = Stopwatch()..start();
    for (var i = 0; i < 10000; i++) {
      first.repo.createRequest(
        col,
        HttpRequestItem(
          id: '',
          name: 'Request $i',
          url: 'https://api.test/items/$i?needle=$i',
        ),
      );
    }
    fill.stop();
    first.close();

    final open = Stopwatch()..start();
    final second = await WorkspaceSession.openFile(path);
    final count = second.repo.children(col).length;
    open.stop();
    final build = Stopwatch()..start();
    final index = SearchIndex(second.repo)..rebuild();
    build.stop();
    final find = Stopwatch()..start();
    final hits = index.search('items/9999');
    find.stop();
    // ignore: avoid_print
    print(
      'PERF fill=${fill.elapsedMilliseconds}ms open+list=${open.elapsedMilliseconds}ms '
      'index=${build.elapsedMilliseconds}ms search=${find.elapsedMilliseconds}ms',
    );
    expect(count, 10000);
    expect(hits, isNotEmpty);
    expect(open.elapsedMilliseconds, lessThan(2000));
    expect(find.elapsedMilliseconds, lessThan(300));
    second.close();
  });

  testWidgets('request overhead against a raw HttpClient', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      await req.drain<void>();
      req.response.write('ok');
      await req.response.close();
    });
    final url = Uri.parse('http://127.0.0.1:${server.port}/');
    final engine = HttpEngine();
    final raw = HttpClient();
    addTearDown(raw.close);

    Future<List<int>> time(Future<void> Function() once) async {
      for (var i = 0; i < 20; i++) {
        await once();
      }
      final out = <int>[];
      for (var i = 0; i < 200; i++) {
        final sw = Stopwatch()..start();
        await once();
        out.add(sw.elapsedMicroseconds);
      }
      out.sort();
      return out;
    }

    final rawTimes = await time(() async {
      final r = await (await raw.getUrl(url)).close();
      await r.drain<void>();
    });
    final ours = await time(
      () async =>
          engine.send(HttpRequestSpec(method: 'GET', url: url)).then((_) {}),
    );
    int p95(List<int> l) => l[(l.length * 0.95).floor()];
    final delta = (p95(ours) - p95(rawTimes)) / 1000;
    // ignore: avoid_print
    print('PERF overhead p95 = ${delta.toStringAsFixed(2)} ms');
    // NFR-PERF-002 is 5 ms; debug (JIT) builds are slower, so only release
    // numbers are held to it.
    expect(delta, lessThan(kDebugMode ? 15 : 5));
  });
}
