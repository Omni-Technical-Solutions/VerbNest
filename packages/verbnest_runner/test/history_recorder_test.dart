import 'package:test/test.dart';
import 'package:verbnest_core/verbnest_core.dart';
import 'package:verbnest_runner/verbnest_runner.dart';
import 'package:verbnest_storage/verbnest_storage.dart';

/// History is best-effort, but a failing history must be visible
/// (security review S9).
void main() {
  test(
    'a failed write is counted and kept, and the request is not affected',
    () {
      final local = LocalStore.memory();
      final recorder = HistoryRecorder(local: local, workspaceId: 'w');
      final item = HttpRequestItem(id: 'r', name: 'n', url: 'https://x.test/');
      recorder.record(requestId: 'r', item: item);
      expect(recorder.recorded, 1);
      expect(recorder.failed, 0);
      expect(recorder.lastError, isNull);

      local.close();
      recorder.record(requestId: 'r', item: item);
      expect(recorder.recorded, 1);
      expect(recorder.failed, 1);
      expect(recorder.lastError, isNotNull);
    },
  );
}
