import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:verbnest_core/verbnest_core.dart';

import '../state/editor_state.dart';
import '../state/file_port.dart';
import '../state/graphql_state.dart';
import 'synced_field.dart';
import '../../l10n/l10n.dart';

/// Query and variables editors for a GraphQL body, with schema loading,
/// completion and an explorer (FR-GQL-001/002).
class GraphqlEditor extends ConsumerStatefulWidget {
  const GraphqlEditor({
    super.key,
    required this.body,
    required this.url,
    required this.notifier,
    required this.onChanged,
  });

  final GraphqlBody body;
  final String url;
  final EditorNotifier notifier;
  final ValueChanged<GraphqlBody> onChanged;

  @override
  ConsumerState<GraphqlEditor> createState() => _GraphqlEditorState();
}

class _GraphqlEditorState extends ConsumerState<GraphqlEditor> {
  bool _fetching = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _fetch() async {
    final l10n = context.l10n;
    setState(() => _fetching = true);
    try {
      final schema = await widget.notifier.introspect();
      ref.read(graphqlSchemaProvider(widget.url).notifier).set(schema);
      _say(l10n.gqlLoaded(schema.userTypes.length));
    } on FormatException catch (e) {
      _say(l10n.gqlLoadFailed(e.message));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _importSdl() async {
    final l10n = context.l10n;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _SdlDialog(),
    );
    if (text == null) return;
    try {
      final schema = GraphqlSchema.fromSdl(text);
      ref.read(graphqlSchemaProvider(widget.url).notifier).set(schema);
      _say(l10n.gqlImported(schema.userTypes.length));
    } on FormatException catch (e) {
      _say(l10n.gqlReadFailed(e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.body;
    final schema = ref.watch(graphqlSchemaProvider(widget.url));
    final ops = graphqlOperationNames(body.query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                key: const Key('gql-fetch'),
                icon: _fetching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined, size: 18),
                label: Text(context.l10n.gqlFetch),
                onPressed: _fetching || widget.url.trim().isEmpty
                    ? null
                    : _fetch,
              ),
              TextButton(
                key: const Key('gql-import-sdl'),
                onPressed: _importSdl,
                child: Text(context.l10n.gqlImportSdl),
              ),
              TextButton(
                key: const Key('gql-explore'),
                onPressed: schema == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => GraphqlExplorer(schema: schema),
                      ),
                child: Text(context.l10n.gqlExplore),
              ),
              Text(
                key: const Key('gql-status'),
                schema == null
                    ? context.l10n.gqlNoSchema
                    : context.l10n.gqlTypeCount(schema.userTypes.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (ops.length > 1)
                DropdownMenu<String>(
                  key: const Key('gql-operation'),
                  initialSelection: ops.contains(body.operationName)
                      ? body.operationName
                      : null,
                  hintText: context.l10n.gqlOperation,
                  expandedInsets: EdgeInsets.zero,
                  requestFocusOnTap: false,
                  dropdownMenuEntries: [
                    for (final o in ops) DropdownMenuEntry(value: o, label: o),
                  ],
                  onSelected: (v) =>
                      widget.onChanged(body.copyWith(operationName: v ?? '')),
                ),
              Tooltip(
                message: context.l10n.gqlPersistedHint,
                child: FilterChip(
                  key: const Key('gql-persisted'),
                  label: Text(context.l10n.gqlPersisted),
                  selected: body.persisted,
                  onSelected: (v) =>
                      widget.onChanged(body.copyWith(persisted: v)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: SyncedTextField(
              key: const Key('gql-query'),
              label: context.l10n.gqlQuery,
              value: body.query,
              variables: true,
              monospace: true,
              expands: true,
              completer: schema == null
                  ? null
                  : (text, caret) => graphqlComplete(schema, text, caret),
              onChanged: (v) => widget.onChanged(body.copyWith(query: v)),
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: SyncedTextField(
              key: const Key('gql-variables'),
              label: context.l10n.gqlVariables,
              value: body.variables,
              variables: true,
              monospace: true,
              expands: true,
              onChanged: (v) => widget.onChanged(body.copyWith(variables: v)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SdlDialog extends ConsumerStatefulWidget {
  const _SdlDialog();

  @override
  ConsumerState<_SdlDialog> createState() => _SdlDialogState();
}

class _SdlDialogState extends ConsumerState<_SdlDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await ref.read(filePortProvider).pick();
    if (f != null) {
      setState(
        () => _controller.text = utf8.decode(f.bytes, allowMalformed: true),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.gqlSdlTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              key: const Key('gql-sdl-file'),
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(context.l10n.gqlChooseFile),
              onPressed: _pick,
            ),
            TextField(
              key: const Key('gql-sdl-text'),
              controller: _controller,
              maxLines: 12,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'type Query { … }',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.gqlCancel),
        ),
        FilledButton(
          key: const Key('gql-sdl-ok'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(context.l10n.gqlImport),
        ),
      ],
    );
  }
}

/// Browse the types of a schema: root operations, then fields and their types.
class GraphqlExplorer extends StatefulWidget {
  const GraphqlExplorer({super.key, required this.schema});

  final GraphqlSchema schema;

  @override
  State<GraphqlExplorer> createState() => _GraphqlExplorerState();
}

class _GraphqlExplorerState extends State<GraphqlExplorer> {
  final List<String> _trail = [];
  String _filter = '';

  void _open(String name) {
    if (widget.schema.type(name) != null) setState(() => _trail.add(name));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.schema;
    final current = _trail.isEmpty ? null : s.type(_trail.last);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (_trail.isNotEmpty)
                    IconButton(
                      key: const Key('gql-back'),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(_trail.removeLast),
                    ),
                  Expanded(
                    child: Text(
                      current?.name ?? context.l10n.gqlSchema,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: current == null
                  ? _root(context, s)
                  : _detail(context, current),
            ),
          ],
        ),
      ),
    );
  }

  Widget _root(BuildContext context, GraphqlSchema s) {
    final roots = <(String, String?)>[
      ('Query', s.queryType),
      ('Mutation', s.mutationType),
      ('Subscription', s.subscriptionType),
    ];
    final q = _filter.toLowerCase();
    final types = [
      for (final t in s.userTypes)
        if (q.isEmpty || t.name.toLowerCase().contains(q)) t,
    ];
    return ListView(
      key: const Key('gql-root'),
      children: [
        for (final (label, name) in roots)
          if (name != null && s.type(name) != null)
            ListTile(
              key: Key('gql-root-$label'),
              title: Text(label),
              subtitle: Text(name),
              onTap: () => _open(name),
            ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            key: const Key('gql-type-filter'),
            decoration: InputDecoration(
              isDense: true,
              hintText: context.l10n.gqlFindType,
              prefixIcon: const Icon(Icons.search, size: 18),
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        for (final t in types)
          ListTile(
            key: Key('gql-type-${t.name}'),
            dense: true,
            title: Text(t.name),
            trailing: Text(_kindLabel(t.kind)),
            onTap: () => _open(t.name),
          ),
      ],
    );
  }

  static String _kindLabel(GqlKind k) => switch (k) {
    GqlKind.scalar => 'scalar',
    GqlKind.object => 'type',
    GqlKind.interface => 'interface',
    GqlKind.union => 'union',
    GqlKind.enumeration => 'enum',
    GqlKind.inputObject => 'input',
  };

  Widget _detail(BuildContext context, GqlType t) {
    Widget typeLink(String type) => InkWell(
      onTap: () => _open(namedTypeOf(type)),
      child: Text(
        type,
        style: TextStyle(
          color: widget.schema.type(namedTypeOf(type)) == null
              ? null
              : Theme.of(context).colorScheme.primary,
          fontFamily: 'monospace',
        ),
      ),
    );
    return ListView(
      key: const Key('gql-detail'),
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          _kindLabel(t.kind),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        if (t.description.isNotEmpty) Text(t.description),
        if (t.interfaces.isNotEmpty)
          Text(context.l10n.gqlImplements(t.interfaces.join(', '))),
        const SizedBox(height: 8),
        for (final f in t.fields)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    f.args.isEmpty
                        ? f.name
                        : '${f.name}(${f.args.map((a) => '${a.name}: ${a.type}').join(', ')})',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      decoration: f.deprecated == null
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                  ),
                ),
                const Text(': '),
                typeLink(f.type),
              ],
            ),
            subtitle: f.description.isEmpty ? null : Text(f.description),
          ),
        for (final f in t.inputFields)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Text(f.name, style: const TextStyle(fontFamily: 'monospace')),
                const Text(': '),
                typeLink(f.type),
              ],
            ),
            subtitle: f.description.isEmpty ? null : Text(f.description),
          ),
        for (final v in t.enumValues)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              v.name,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            subtitle: v.description.isEmpty ? null : Text(v.description),
          ),
        if (t.kind == GqlKind.union)
          for (final p in t.possibleTypes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: typeLink(p),
            ),
      ],
    );
  }
}
