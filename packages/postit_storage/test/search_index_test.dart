import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';
import 'package:test/test.dart';

void main() {
  late WorkspaceDatabase ws;
  late WorkspaceRepository repo;
  late SearchIndex index;

  setUp(() {
    ws = WorkspaceDatabase.memory();
    repo = WorkspaceRepository(ws);
    final col = repo.createCollection('Billing API');
    final folder = repo.createFolder(col, 'Invoices');
    repo.createRequest(
      folder,
      HttpRequestItem(
        id: '',
        name: 'Create invoice',
        method: 'POST',
        url: 'https://pay.test/v1/invoices',
        headers: const [
          KeyValue(key: 'Authorization', value: 'Bearer hunter2'),
        ],
        body: const RawBody(RawBodyLanguage.json, '{"customer":"acme-corp"}'),
      ),
    );
    repo.createRequest(
      col,
      HttpRequestItem(id: '', name: 'Health', url: '/up'),
    );
    index = SearchIndex(repo)..rebuild();
  });
  tearDown(() {
    index.dispose();
    ws.close();
  });

  test('finds by name, url and body text, with the container path', () {
    final byName = index.search('invoice');
    expect(
      byName.map((h) => h.name),
      containsAll(['Invoices', 'Create invoice']),
    );
    final req = byName.firstWhere((h) => h.name == 'Create invoice');
    expect(req.path, ['Billing API', 'Invoices']);
    expect(req.method, 'POST');
    expect(
      index.search('v1/invoices').map((h) => h.name),
      contains('Create invoice'),
    );
    expect(index.search('acme-corp').single.name, 'Create invoice');
  });

  test('is case-insensitive and short queries match names only', () {
    expect(index.search('HEALTH').single.name, 'Health');
    expect(index.search('he').map((h) => h.name), contains('Health'));
    expect(index.search(''), isEmpty);
  });

  test('header values are not indexed but header names are', () {
    expect(index.search('hunter2'), isEmpty);
    expect(index.search('Authorization').single.name, 'Create invoice');
  });

  test('quotes in the query do not break matching and rebuild sees edits', () {
    expect(index.search('say "hi"'), isEmpty);
    final col = repo.children(null).first.id;
    repo.createRequest(col, HttpRequestItem(id: '', name: 'Brand new thing'));
    expect(index.search('brand new'), isEmpty);
    index.rebuild();
    expect(index.search('brand new').single.name, 'Brand new thing');
  });
}
