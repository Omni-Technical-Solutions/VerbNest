import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postit_app/src/state/editor_state.dart';
import 'package:postit_app/src/state/file_port.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/widgets/request_editor.dart';
import 'package:postit_core/postit_core.dart';

import 'editor_test.dart' show FakeEngine;

class FakePort implements FilePort {
  PickedFile? next;
  (String, Uint8List)? saved;

  @override
  bool get savesBySharing => false;

  @override
  Future<PickedFile?> pick() async => next;

  @override
  Future<bool> save(String name, Uint8List bytes, {String? mime}) async {
    saved = (name, bytes);
    return true;
  }
}

({ProviderContainer c, WorkspaceSession s, FakeEngine e, FakePort p, String id})
setup() {
  final s = WorkspaceSession.memory();
  final e = FakeEngine();
  final p = FakePort();
  final c = ProviderContainer(
    overrides: [
      sessionProvider.overrideWithValue(s),
      engineProvider.overrideWithValue(e),
      filePortProvider.overrideWithValue(p),
    ],
  );
  final col = s.repo.createCollection('C');
  final id = s.repo.createRequest(
    col,
    HttpRequestItem(id: '', name: 'R', url: 'http://x.test/up'),
  );
  addTearDown(() {
    c.dispose();
    s.close();
  });
  return (c: c, s: s, e: e, p: p, id: id);
}

Future<void> mount(WidgetTester tester, ProviderContainer c, String id) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(body: RequestEditor(requestId: id)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('file helpers', () {
    expect(safeFileName(r'C:\x\a"b.txt'), 'a_b.txt');
    expect(attachmentIdOf(attachmentRef('ID1', 'a b.txt')), 'ID1');
    expect(attachmentRef('ID1', 'a b.txt'), 'attachment:ID1/a b.txt');
    expect(attachmentIdOf('/tmp/x'), isNull);
    final url = Uri.parse('https://h.test/files/report');
    expect(
      responseFileName([
        ('Content-Disposition', 'attachment; filename="r 1.pdf"'),
      ], url),
      'r 1.pdf',
    );
    expect(responseFileName([], Uri.parse('https://h.test/a/b.csv')), 'b.csv');
    expect(
      responseFileName([], url, contentType: 'application/json; charset=utf-8'),
      'report.json',
    );
  });

  test(
    'send reads form-data and binary attachments from the workspace',
    () async {
      final t = setup();
      final f = t.s.repo.addAttachment(
        'hello.txt',
        Uint8List.fromList(utf8.encode('HELLO')),
      );
      final n = t.c.read(editorProvider(t.id).notifier);
      n.edit(
        (i) => i.copyWith(
          method: 'POST',
          body: FormDataBody([
            KeyValue(
              key: 'file',
              value: attachmentRef(f, 'hello.txt'),
              type: KeyValueType.file,
            ),
          ]),
        ),
      );
      await n.send();
      final sent = utf8.decode(t.e.last!.body!.toList(), allowMalformed: true);
      expect(sent, contains('filename="hello.txt"'));
      expect(sent, contains('HELLO'));

      n.edit((i) => i.copyWith(body: BinaryBody(f)));
      await n.send();
      expect(utf8.decode(t.e.last!.body!.toList()), 'HELLO');

      n.edit((i) => i.copyWith(body: const BinaryBody('missing')));
      await n.send();
      expect(t.c.read(editorProvider(t.id)).error, contains('Cannot read'));
    },
  );

  testWidgets('binary body picker stores the file in the workspace', (
    tester,
  ) async {
    final t = setup();
    t.p.next = PickedFile('d.bin', Uint8List.fromList([1, 2, 3]));
    await mount(tester, t.c, t.id);
    await tester.tap(find.text('Body'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('body-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('binary').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('binary-pick')));
    await tester.pumpAndSettle();
    expect(find.textContaining('d.bin (3 bytes)'), findsOneWidget);
    final body = t.c.read(editorProvider(t.id)).item.body as BinaryBody;
    expect(t.s.repo.attachmentBytes(body.attachmentId!), [1, 2, 3]);
    await tester.pump(EditorNotifier.saveDelay);
  });

  testWidgets('saving a response passes name and bytes to the port', (
    tester,
  ) async {
    final t = setup();
    await mount(tester, t.c, t.id);
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('response-save')));
    await tester.pump();
    expect(t.p.saved!.$1, 'up.json');
    expect(utf8.decode(t.p.saved!.$2), '{"ok":true}');
    await tester.pump(const Duration(seconds: 5));
  });
}
