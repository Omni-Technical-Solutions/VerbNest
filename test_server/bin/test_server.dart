import 'package:test_server/test_server.dart';

Future<void> main() async {
  final server = await TestServer.start();
  print('VerbNest test server listening on ${server.baseUrl}');
}
