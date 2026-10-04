import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/state/session.dart';
import 'src/workspace_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await WorkspaceSession.openDefault();
  runApp(WorkspaceHost(initial: session, child: const PostItApp()));
}
