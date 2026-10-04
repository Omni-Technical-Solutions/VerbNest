import 'dart:typed_data';

import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';
import 'package:test/test.dart';

void main() {
  late WorkspaceDatabase ws;
  late WorkspaceRepository repo;

  setUp(() {
    ws = WorkspaceDatabase.memory();
    repo = WorkspaceRepository(ws);
  });
  tearDown(() => ws.close());

  test('store, read back and describe an attachment', () {
    final id = repo.addAttachment(
      'a.bin',
      Uint8List.fromList([1, 2, 3]),
      mime: 'application/x-test',
    );
    final info = repo.attachment(id)!;
    expect(
      (info.name, info.mime, info.size),
      ('a.bin', 'application/x-test', 3),
    );
    expect(repo.attachmentBytes(id), [1, 2, 3]);
  });

  test('missing attachments are reported', () {
    expect(repo.attachment('nope'), isNull);
    expect(() => repo.attachmentBytes('nope'), throwsA(isA<NotFoundError>()));
  });

  test('delete and prune orphans', () {
    final a = repo.addAttachment('a', Uint8List(1));
    final b = repo.addAttachment('b', Uint8List(1));
    final c = repo.addAttachment('c', Uint8List(1));
    repo.deleteAttachment(a);
    expect(repo.attachment(a), isNull);
    expect(repo.pruneAttachments({b}), 1);
    expect(repo.attachment(b), isNotNull);
    expect(repo.attachment(c), isNull);
  });

  test('prune unreferenced keeps attachments a request still uses', () {
    final col = repo.createCollection('C');
    final keep = repo.addAttachment('keep', Uint8List(1));
    final drop = repo.addAttachment('drop', Uint8List(1));
    repo.createRequest(
      col,
      HttpRequestItem(id: '', name: 'R', body: BinaryBody(keep)),
    );
    expect(repo.pruneUnreferencedAttachments(), 1);
    expect(repo.attachment(keep), isNotNull);
    expect(repo.attachment(drop), isNull);
  });
}
