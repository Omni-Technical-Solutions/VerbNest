import 'package:flutter/material.dart';

import 'adaptive_scaffold.dart';
import 'theme.dart';

class PostItApp extends StatelessWidget {
  const PostItApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PostIt',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const AdaptiveScaffold(),
    );
  }
}
