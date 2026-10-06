import 'dart:io';
import 'dart:typed_data';

import 'package:verbnest_storage/verbnest_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

HistoryEntry entry(
  String id, {
  String ws = 'w1',
  String url = 'https://api.test/pets',
  String method = 'GET',
  int status = 200,
  required DateTime at,
  Uint8List? body,
}) => HistoryEntry(
  id: id,
  workspaceId: ws,
  method: method,
  url: url,
  sentAt: at,
  status: status,
  totalMs: 12,
  requestJson: '{"headers":[["Authorization","••••••"]]}',
  responseBody: body,
);

void main() {
  late LocalStore store;
  final t0 = DateTime.utc(2026, 1, 1);

  setUp(() => store = LocalStore.memory());
  tearDown(() => store.close());

  group('history', () {
    test('lists newest first and is scoped to the workspace', () {
      store.addHistory(entry('a', at: t0));
      store.addHistory(entry('b', at: t0.add(const Duration(minutes: 1))));
      store.addHistory(entry('c', ws: 'other', at: t0));
      expect(store.listHistory('w1').map((e) => e.id), ['b', 'a']);
      expect(store.listHistory('other').map((e) => e.id), ['c']);
    });

    test('search matches url, method and status; wildcards are literal', () {
      store.addHistory(entry('a', url: 'https://x/pets', at: t0));
      store.addHistory(
        entry(
          'b',
          url: 'https://x/users_1',
          method: 'POST',
          status: 404,
          at: t0,
        ),
      );
      expect(store.listHistory('w1', query: 'pets').map((e) => e.id), ['a']);
      expect(store.listHistory('w1', query: 'POST').map((e) => e.id), ['b']);
      expect(store.listHistory('w1', query: '404').map((e) => e.id), ['b']);
      expect(store.listHistory('w1', query: '%'), isEmpty);
      expect(store.listHistory('w1', query: 'users_1').map((e) => e.id), ['b']);
    });

    test('bodies are capped and flagged', () {
      store.addHistory(
        entry('big', at: t0, body: Uint8List(100)),
        maxBodyBytes: 10,
      );
      final got = store.history('big')!;
      expect(got.responseBody, hasLength(10));
      expect(got.bodyTruncated, isTrue);
    });

    test('storeBodies false keeps no body', () {
      store.addHistory(
        entry('a', at: t0, body: Uint8List(5)),
        storeBodies: false,
      );
      expect(store.history('a')!.responseBody, isNull);
    });

    test('pagination with before', () {
      for (var i = 0; i < 5; i++) {
        store.addHistory(entry('e$i', at: t0.add(Duration(minutes: i))));
      }
      final page = store.listHistory(
        'w1',
        limit: 2,
        before: t0.add(const Duration(minutes: 3)),
      );
      expect(page.map((e) => e.id), ['e2', 'e1']);
    });

    test('retention by count and age', () {
      for (var i = 0; i < 6; i++) {
        store.addHistory(entry('e$i', at: t0.add(Duration(days: i))));
      }
      final now = t0.add(const Duration(days: 6));
      expect(
        store.pruneHistory('w1', maxAge: const Duration(days: 4), now: now),
        2,
      );
      expect(store.listHistory('w1').map((e) => e.id), [
        'e5',
        'e4',
        'e3',
        'e2',
      ]);
      expect(store.pruneHistory('w1', maxEntries: 2), 2);
      expect(store.listHistory('w1').map((e) => e.id), ['e5', 'e4']);
    });

    test('delete one and clear all', () {
      store.addHistory(entry('a', at: t0));
      store.addHistory(entry('b', at: t0));
      store.deleteHistory('a');
      expect(store.history('a'), isNull);
      store.clearHistory('w1');
      expect(store.listHistory('w1'), isEmpty);
    });
  });

  group('current values', () {
    test('set, overwrite, read and clear', () {
      store.setCurrentValue('w1', 'environment', 'e1', 'token', 'abc');
      store.setCurrentValue('w1', 'environment', 'e1', 'token', 'def');
      store.setCurrentValue('w1', 'environment', 'e2', 'token', 'zzz');
      expect(store.currentValues('w1', 'environment', 'e1'), {'token': 'def'});
      store.clearCurrentValue('w1', 'environment', 'e1', 'token');
      expect(store.currentValues('w1', 'environment', 'e1'), isEmpty);
      expect(store.currentValues('w1', 'environment', 'e2'), {'token': 'zzz'});
      store.setCurrentValue('w1', 'current:environment', 'e2', 'k', 'v');
      expect(store.secretOwners('w1'), [('environment', 'e2')]);
    });
  });

  group('recent workspaces', () {
    test('ordered by last opened and forgetting drops local state', () {
      store.touchWorkspace('a', 'A', '/a.verbnest', now: t0);
      store.touchWorkspace(
        'b',
        'B',
        '/b.verbnest',
        now: t0.add(const Duration(hours: 1)),
      );
      store.touchWorkspace(
        'a',
        'A2',
        '/a2.verbnest',
        now: t0.add(const Duration(hours: 2)),
      );
      final recent = store.recentWorkspaces();
      expect(recent.map((w) => w.id), ['a', 'b']);
      expect(recent.first.name, 'A2');
      expect(recent.first.dbPath, '/a2.verbnest');

      store.addHistory(entry('h', ws: 'a', at: t0));
      store.forgetWorkspace('a');
      expect(store.recentWorkspaces().map((w) => w.id), ['b']);
      expect(store.history('h'), isNull);
    });
  });

  group('file lifecycle', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('verbnest_local'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('data persists across reopen', () {
      final path = '${dir.path}/local.db';
      LocalStore.open(path)
        ..addHistory(entry('a', at: t0))
        ..close();
      final again = LocalStore.open(path);
      expect(again.history('a'), isNotNull);
      again.close();
    });

    test(
      'a cache written by a newer app is reset instead of blocking startup',
      () {
        final path = '${dir.path}/local.db';
        LocalStore.open(path).close();
        sqlite3.open(path)
          ..execute('PRAGMA user_version = 99')
          ..close();
        final store = LocalStore.open(path);
        expect(store.listHistory('w1'), isEmpty);
        store.close();
      },
    );
  });

  test('device-local key/value settings per workspace', () {
    final store = LocalStore.memory();
    addTearDown(store.close);
    expect(store.kv('w1', 'k'), isNull);
    store.setKv('w1', 'k', 'a');
    store.setKv('w1', 'k', 'b');
    store.setKv('w2', 'k', 'z');
    expect(store.kv('w1', 'k'), 'b');
    expect(store.kv('w2', 'k'), 'z');
    store.setKv('w1', 'k', null);
    expect(store.kv('w1', 'k'), isNull);
    store.touchWorkspace('w2', 'n', '/p');
    store.forgetWorkspace('w2');
    expect(store.kv('w2', 'k'), isNull);
  });
}
