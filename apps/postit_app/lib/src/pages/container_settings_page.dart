import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';
import 'package:postit_storage/postit_storage.dart';

import '../state/session.dart';
import '../state/variables.dart';
import '../widgets/auth_editor.dart';
import '../widgets/synced_field.dart';
import 'environments_page.dart';

/// Description, auth and variables of a collection or folder (FR-COL-002).
/// Children inherit auth and see the variables.
class ContainerSettingsPage extends ConsumerStatefulWidget {
  const ContainerSettingsPage({super.key, required this.containerId});

  final String containerId;

  @override
  ConsumerState<ContainerSettingsPage> createState() =>
      _ContainerSettingsPageState();
}

class _ContainerSettingsPageState extends ConsumerState<ContainerSettingsPage> {
  late Auth _auth;

  @override
  void initState() {
    super.initState();
    _auth = ref.read(repositoryProvider).containerAuth(widget.containerId);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repo = session.repo;
    final node = repo.node(widget.containerId);
    final isCollection = node.parentId == null;
    final owner = isCollection
        ? VariableOwner.collection(node.id)
        : VariableOwner.folder(node.id);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${node.name} settings'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Auth'),
              Tab(text: 'Variables'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SyncedTextField(
                key: const Key('container-description'),
                label: 'Description',
                value: repo.description(node.id),
                maxLines: 8,
                onChanged: (v) => repo.setDescription(node.id, v),
              ),
            ),
            AuthEditor(
              auth: _auth,
              inheritText: isCollection
                  ? 'No auth is added unless a folder or request sets one.'
                  : 'Uses the auth of the parent folder or collection.',
              onChanged: (a) {
                setState(() => _auth = a);
                repo.setContainerAuth(node.id, a);
              },
            ),
            VariablesEditor(
              initial: loadVariables(session, owner),
              onChanged: (vars) => saveVariables(session, owner, vars),
            ),
          ],
        ),
      ),
    );
  }
}
