import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'adaptive_scaffold.dart';
import 'state/theme_state.dart';
import 'theme.dart';

class PostItApp extends ConsumerWidget {
  const PostItApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'PostIt',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      home: const AdaptiveScaffold(),
    );
  }
}
