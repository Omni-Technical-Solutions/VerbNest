import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/state/session.dart';
import 'src/workspace_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final session = await WorkspaceSession.openDefault();
    runApp(WorkspaceHost(initial: session, child: const VerbnestApp()));
  } on Object catch (e) {
    runApp(StartupErrorApp(message: '$e', retry: main));
  }
}

/// Shown when the workspace cannot be opened at launch, instead of a blank
/// window.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    super.key,
    required this.message,
    required this.retry,
  });

  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VerbNest',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'VerbNest could not open your workspace',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(message, key: const Key('startup-error')),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: retry,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
