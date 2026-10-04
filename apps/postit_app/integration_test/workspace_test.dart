import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:postit_app/src/state/session.dart';
import 'package:postit_app/src/workspace_host.dart';
import 'package:postit_core/postit_core.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create, export, import and switch workspaces on disk', (
    tester,
  ) async {
    final dir = await WorkspaceSession.workspacesDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final first = await WorkspaceSession.openFile(
      '${dir.path}/itest-a-$stamp.postit',
      create: true,
    );
    late WidgetRef captured;
    await tester.pumpWidget(
      WorkspaceHost(
        initial: first,
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    WorkspaceSwitcher sw() => captured.read(workspaceSwitcherProvider);
    WorkspaceSession cur() => captured.read(sessionProvider);

    final col = cur().repo.createCollection('Kept');
    cur().repo.createRequest(col, HttpRequestItem(id: '', name: 'R'));
    final bytes = await sw().exportCurrent();
    expect(bytes.length, greaterThan(1000));

    await sw().create('itest b $stamp');
    await tester.pump();
    expect(cur().repo.name, 'itest b $stamp');
    expect(cur().repo.children(null), isEmpty);

    await sw().importBytes('itest-copy-$stamp.postit', bytes);
    await tester.pump();
    expect(cur().repo.children(null).single.name, 'Kept');

    await expectLater(
      sw().importBytes('bad-$stamp.postit', bytes.sublist(0, 200)),
      throwsA(anything),
    );
    await tester.pump();
    expect(cur().repo.children(null).single.name, 'Kept');

    final paths = sw().recent().map((w) => w.dbPath).toList();
    final a = paths.firstWhere((p) => p.contains('itest-a-$stamp'));
    await sw().open(a);
    await tester.pump();
    expect(cur().repo.children(null).single.name, 'Kept');
    expect(cur().db.path, a);

    // Leave the app's recent list as it was.
    for (final w in sw().recent()) {
      if (w.dbPath.contains('itest')) {
        cur().local.forgetWorkspace(w.id);
        if (w.dbPath != a) File(w.dbPath).deleteSync();
      }
    }
    final aFile = File(a);
    await sw().create('itest cleanup');
    await tester.pump();
    aFile.deleteSync();
    final cleanup = sw().recent().firstWhere((w) => w.name == 'itest cleanup');
    cur().local.forgetWorkspace(cleanup.id);
    // The last workspace file is left in the test container.
  });
}
