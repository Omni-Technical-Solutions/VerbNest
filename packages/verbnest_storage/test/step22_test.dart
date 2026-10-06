import 'dart:typed_data';

import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_storage/verbnest_storage.dart';
import 'package:test/test.dart';

void main() {
  late WorkspaceRepository repo;
  late String req;
  setUp(() {
    repo = WorkspaceRepository(WorkspaceDatabase.memory());
    final c = repo.createCollection('C');
    req = repo.createRequest(c, const HttpRequestItem(id: '', name: 'r'));
  });

  test('favourite flag round trips and survives a save', () {
    expect(repo.isFavourite(req), isFalse);
    repo.setFavourite(req, true);
    expect(repo.favourites(), [req]);
    repo.saveRequest(repo.getRequest(req).copyWith(name: 'renamed'));
    expect(repo.isFavourite(req), isTrue);
    repo.setFavourite(req, false);
    expect(repo.favourites(), isEmpty);
  });

  test('examples keep order and body bytes, and go with the request', () {
    final a = repo.addExample(req, 'ok', {
      'status': 200,
    }, Uint8List.fromList([1, 2]));
    final b = repo.addExample(req, 'bad', {'status': 400}, Uint8List(0));
    expect(repo.examples(req).map((e) => e.name), ['ok', 'bad']);
    expect(repo.example(a).body, [1, 2]);
    repo.renameExample(b, 'not found');
    expect(repo.example(b).name, 'not found');
    repo.deleteExample(a);
    expect(repo.examples(req), hasLength(1));
    repo.delete(req);
    expect(repo.examples(req), isEmpty);
  });
}
