import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postit_core/postit_core.dart';

import 'session.dart';

/// The schema last loaded for a GraphQL endpoint, kept per URL in the
/// workspace (FR-GQL-002). The key is the URL as typed, so `{{baseUrl}}/graphql`
/// keeps one schema across environments.
class GraphqlSchemaNotifier extends Notifier<GraphqlSchema?> {
  GraphqlSchemaNotifier(this.url);

  final String url;

  String get _key => 'graphql_schema:$url';

  @override
  GraphqlSchema? build() {
    final stored = ref.watch(sessionProvider).repo.meta(_key);
    if (stored == null) return null;
    try {
      return GraphqlSchema.fromSdl(stored);
    } on FormatException {
      return null;
    }
  }

  void set(GraphqlSchema schema) {
    ref.read(sessionProvider).repo.setMeta(_key, schema.toSdl());
    state = schema;
  }
}

final graphqlSchemaProvider =
    NotifierProvider.family<GraphqlSchemaNotifier, GraphqlSchema?, String>(
      GraphqlSchemaNotifier.new,
    );
