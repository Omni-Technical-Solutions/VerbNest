import 'package:postit_storage/postit_storage.dart';

class SidebarRow {
  const SidebarRow(this.node, this.depth, {this.expanded = false});

  final NodeInfo node;
  final int depth;
  final bool expanded;
}

/// Flattens the tree into the rows the sidebar shows.
///
/// With an empty [filter] only expanded containers are opened. With a filter
/// (FR-COL-003) every node whose name matches is shown together with its
/// ancestors, all expanded.
List<SidebarRow> sidebarRows(
  List<NodeInfo> Function(String? parentId) children,
  Set<String> expanded,
  String filter,
) {
  final query = filter.trim().toLowerCase();
  final rows = <SidebarRow>[];
  if (query.isEmpty) {
    _plain(children, expanded, null, 0, rows);
  } else {
    _filtered(children, query, null, 0, rows);
  }
  return rows;
}

void _plain(
  List<NodeInfo> Function(String?) children,
  Set<String> expanded,
  String? parentId,
  int depth,
  List<SidebarRow> out,
) {
  for (final node in children(parentId)) {
    final open = node.isContainer && expanded.contains(node.id);
    out.add(SidebarRow(node, depth, expanded: open));
    if (open) _plain(children, expanded, node.id, depth + 1, out);
  }
}

/// Returns whether anything under [parentId] matched.
bool _filtered(
  List<NodeInfo> Function(String?) children,
  String query,
  String? parentId,
  int depth,
  List<SidebarRow> out,
) {
  var any = false;
  for (final node in children(parentId)) {
    final mark = out.length;
    out.add(SidebarRow(node, depth, expanded: node.isContainer));
    final childMatch =
        node.isContainer && _filtered(children, query, node.id, depth + 1, out);
    final selfMatch = node.name.toLowerCase().contains(query);
    if (selfMatch || childMatch) {
      any = true;
    } else {
      out.removeRange(mark, out.length);
    }
  }
  return any;
}
