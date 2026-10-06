import 'dart:io';

import 'package:verbnest_cli/verbnest_cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args, out: stdout, err: stderr);
}
