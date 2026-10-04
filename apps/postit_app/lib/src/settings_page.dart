import 'package:flutter/material.dart';

/// Stub; real settings (FR-APP-004) arrive with persistence.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        ListTile(
          leading: Icon(Icons.brightness_6_outlined),
          title: Text('Theme'),
          subtitle: Text('Follows system'),
        ),
        ListTile(
          leading: Icon(Icons.timer_outlined),
          title: Text('Default timeout'),
          subtitle: Text('30 s'),
        ),
        ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Verify TLS certificates'),
          subtitle: Text('On'),
        ),
      ],
    );
  }
}
