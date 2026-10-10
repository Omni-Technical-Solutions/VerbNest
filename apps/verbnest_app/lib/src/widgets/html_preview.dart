import 'package:material_ui/material_ui.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../l10n/l10n.dart';

/// Responses above this size are not rendered; layout of large documents
/// would freeze the UI.
const maxHtmlPreviewBytes = 2 * 1024 * 1024;

/// Renders a response as a static page. The renderer builds widgets from the
/// markup: scripts never run, nothing is fetched from the network, and links
/// are ignored.
class HtmlPreview extends StatelessWidget {
  const HtmlPreview({super.key, required this.html, required this.size});

  final String html;
  final int size;

  @override
  Widget build(BuildContext context) {
    if (size > maxHtmlPreviewBytes) {
      return Center(
        key: const Key('html-too-large'),
        child: Text(context.l10n.rvHtmlTooLarge),
      );
    }
    return SingleChildScrollView(
      key: const Key('html-preview'),
      padding: const EdgeInsets.all(8),
      child: HtmlWidget(html, onTapUrl: (_) async => true),
    );
  }
}
