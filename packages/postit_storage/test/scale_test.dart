import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';
import 'package:test/test.dart';

/// Timings for a large workspace. Limits are generous; the printed numbers
/// are what to watch.
void main() {
  test('5,000 requests: build, list, search stay interactive', () {
    final repo = WorkspaceRepository(WorkspaceDatabase.memory());
    final watch = Stopwatch()..start();
    final col = repo.createCollection('Big');
    for (var f = 0; f < 50; f++) {
      final folder = repo.createFolder(col, 'Folder $f');
      for (var r = 0; r < 100; r++) {
        repo.createRequest(
          folder,
          HttpRequestItem(
            id: '',
            name: 'Request $f-$r',
            url: 'https://api.example.com/v1/items/$f/$r?x={{x}}',
            method: r.isEven ? 'GET' : 'POST',
          ),
        );
      }
    }
    final build = watch.elapsedMilliseconds;

    watch
      ..reset()
      ..start();
    var listed = 0;
    for (final f in repo.children(col)) {
      listed += repo.children(f.id).length;
    }
    final list = watch.elapsedMilliseconds;

    watch
      ..reset()
      ..start();
    final index = SearchIndex(repo)..rebuild();
    final rebuild = watch.elapsedMilliseconds;
    watch
      ..reset()
      ..start();
    final hits = index.search('Request 49-99');
    final search = watch.elapsedMilliseconds;
    index.dispose();

    // ignore: avoid_print
    print(
      'scale: build ${build}ms, list ${list}ms, index ${rebuild}ms, '
      'search ${search}ms (${hits.length} hits)',
    );
    expect(listed, 5000);
    expect(hits, isNotEmpty);
    expect(list, lessThan(2000));
    expect(search, lessThan(500));
    expect(rebuild, lessThan(10000));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
