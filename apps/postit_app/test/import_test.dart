import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/state/import_actions.dart';
import 'package:postit_app/src/state/session.dart';

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
}
