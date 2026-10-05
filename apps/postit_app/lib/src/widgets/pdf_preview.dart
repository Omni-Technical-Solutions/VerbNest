import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../l10n/l10n.dart';

/// PDFs above this size are not opened; rendering them in the preview pane
/// would be slow and memory heavy.
const maxPdfPreviewBytes = 20 * 1024 * 1024;

/// Shows a PDF response with PDFium. The bytes stay in memory: nothing is
/// written to disk and the document is never fetched again.
class PdfPreview extends StatelessWidget {
  const PdfPreview({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    if (bytes.length > maxPdfPreviewBytes) {
      return Center(
        key: const Key('pdf-too-large'),
        child: Text(context.l10n.rvPdfTooLarge),
      );
    }
    return PdfViewer.data(
      bytes,
      key: const Key('pdf-preview'),
      sourceName: 'response.pdf',
      params: PdfViewerParams(
        errorBannerBuilder: (context, error, stackTrace, documentRef) =>
            Center(child: Text(context.l10n.rvPdfError)),
      ),
    );
  }
}
