# ADR-013: PDF preview with pdfrx

Status: accepted (v0.41.0). Completes the item ADR-011 deferred.

## Context

ADR-011 left PDF preview open because `pdfrx` needs a PDFium binary and there
was no way to check it on every platform. CI on Linux, Windows, macOS, Android
and iOS now exists, so the build can be verified.

## Decision

- `PdfPreview` (`widgets/pdf_preview.dart`) shows `application/pdf` responses
  with `PdfViewer.data`. The bytes stay in memory; nothing is written to disk.
- The "Preview" segment appears for PDFs as it does for images and HTML.
- PDFs above 20 MB show a message instead of opening.
- An unreadable or encrypted file shows "This PDF could not be opened". No
  password prompt is offered.
- `integration_test/pdf_test.dart` renders a hand-built PDF through real
  PDFium and runs in CI on the desktop targets and on mobile.

## Consequences

- A native PDFium binary is fetched at build time on every platform.
- The widget tests cannot load PDFium, so they cover only the size cap and the
  segment; rendering is covered by the integration test.
