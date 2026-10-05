import 'dart:io';

import 'package:postit_cli/postit_cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args, out: stdout, err: stderr);
}
