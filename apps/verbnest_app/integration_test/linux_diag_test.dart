// A step-by-step probe for the Linux CI job. It is not in the normal list of
// integration tests: scripts/ci_integration.sh runs it only after a test file
// failed, so the last "DIAG" line printed shows where the app process ends.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:verbnest_app/src/state/secure_vault.dart';
import 'package:verbnest_app/src/state/session.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

// ignore_for_file: avoid_print

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('where the app process ends', (tester) async {
    print('DIAG 1 documents directory');
    final docs = await getApplicationDocumentsDirectory();
    print('DIAG 2 documents = ${docs.path}');
    final support = await getApplicationSupportDirectory();
    print('DIAG 3 support = ${support.path}');
    final dir = await WorkspaceSession.workspacesDir();
    print('DIAG 4 workspaces = ${dir.path}');
    final path = '${dir.path}/diag-${DateTime.now().millisecondsSinceEpoch}.db';
    final db = WorkspaceDatabase.open(path, create: true);
    print('DIAG 5 workspace file opened');
    db.close();
    print('DIAG 6 workspace file closed');
    final local = LocalStore.open('${support.path}/diag-local.db');
    print('DIAG 7 local store opened');
    local.close();
    print('DIAG 8 secret vault check starts');
    final ok = await vaultWorks(PlatformSecretVault());
    print('DIAG 9 secret vault works = $ok');
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$path$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  });
}
