import 'package:flutter_test/flutter_test.dart';
import 'package:verbnest_app/src/state/import_actions.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_import/verbnest_import.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

void main() {
  late WorkspaceSession s;
  setUp(() => s = WorkspaceSession.memory());
  tearDown(() => s.close());

  test('cURL import creates a request in "Imported"', () {
    final r = importText(s, "curl -X POST https://a.test/x -d '{\"a\":1}'");
    final col = s.repo.children(null).single;
    expect(col.name, 'Imported');
    final req = s.repo.getRequest(r.nodeId!);
    expect(req.method, 'POST');
    expect(req.url, 'https://a.test/x');
    importText(s, 'curl https://a.test/y');
    expect(s.repo.children(null), hasLength(1));
    expect(s.repo.children(col.id), hasLength(2));
  });

  test('Postman collection and environment import', () {
    importText(
      s,
      '{"info":{"name":"P","schema":"x"},"item":[{"name":"r",'
      '"request":{"method":"GET","url":"http://h.test"}}]}',
    );
    expect(s.repo.children(null).single.name, 'P');
    importText(s, '{"name":"E","values":[{"key":"a","value":"1"}]}');
    importText(s, '{"name":"E","values":[{"key":"a","value":"2"}]}');
    expect(s.repo.environments().map((e) => e.name), ['E', 'E (2)']);
  });

  test('exports and copies as cURL', () {
    final r = importText(s, 'curl -H "X-A: 1" https://a.test/x');
    expect(requestAsCurl(s, r.nodeId!), contains("-H 'X-A: 1'"));
    final colId = s.repo.children(null).single.id;
    expect(exportCollectionJson(s, colId), contains('v2.1.0'));
  });

  test('unrecognised text is a friendly error', () {
    expect(() => importText(s, 'hello'), throwsFormatException);
    expect(() => importText(s, '{"a":1}'), throwsFormatException);
    expect(() => importText(s, '  '), throwsFormatException);
  });

  test('an oversized import is refused before parsing', () {
    final big = 'a' * (maxImportChars + 1);
    expect(() => importText(s, big), throwsFormatException);
  });

  test('OpenAPI YAML, HAR and a Postman dump import', () {
    final r = importText(s, '''
openapi: 3.0.0
info: {title: Y}
servers: [{url: "https://y.test"}]
paths:
  /a:
    get: {summary: Get a, tags: [t]}
''');
    final id = r.nodeId!;
    expect(s.repo.node(id).name, 'Y');
    final tag = s.repo.children(id).single;
    expect(tag.name, 't');
    expect(
      s.repo.getRequest(s.repo.children(tag.id).single.id).url,
      '{{baseUrl}}/a',
    );
    expect(
      s.repo.variables(VariableOwner.collection(id)).single.value,
      'https://y.test',
    );

    importText(
      s,
      '{"log":{"entries":[{"request":{"method":"GET","url":"http://h.test/z","headers":[]}}]}}',
    );
    expect(
      s.repo.children(null).map((n) => n.name),
      contains(startsWith('HAR import')),
    );

    final dump = importText(
      s,
      '{"collections":[{"info":{"name":"D","schema":"x"},"item":[]}],'
      '"environments":[{"name":"DE","values":[]}]}',
    );
    expect(dump.message, 'Imported 1 collections and 1 environments');
  });

  test('generates code from a saved request, resolving on request', () {
    final r = importText(s, 'curl -H "X-A: 1" https://a.test/x');
    final plain = requestAsCode(s, r.nodeId!, CodeLanguage.pythonRequests);
    expect(plain, contains("'https://a.test/x'"));
    expect(plain, contains("'X-A': '1'"));
    expect(
      requestAsCode(s, r.nodeId!, CodeLanguage.curl, resolve: true),
      contains('curl'),
    );
  });
}
