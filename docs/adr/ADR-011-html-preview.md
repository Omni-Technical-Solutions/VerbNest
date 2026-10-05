# ADR-011: HTML preview through a widget renderer; PDF deferred

Status: accepted (v0.33.0)

## Context

Responses of type `text/html` are common, and reading raw markup is slow. The
plan named `webview_flutter` or `flutter_inappwebview` for HTML. A web view
runs scripts and fetches resources unless every case is blocked, and
`webview_flutter` has no Windows or Linux support. For PDF, `pdfrx` and
`printing` ship native PDFium builds per platform.

## Decision

- HTML is shown by `flutter_widget_from_html_core`. It turns the markup into
  Flutter widgets, so scripts never run, `<img>` and stylesheets are not
  fetched, and tapped links are swallowed. It is pure Dart and works on every
  platform the app targets.
- The "Preview" segment appears for `text/html` as it does for images. Pages
  above 2 MB show a message instead (layout of large documents blocks the UI);
  this is lower than the 10 MB first planned.
- The preview is a text rendition, not a browser: layout and CSS support are
  partial. Raw and Pretty stay the source of truth.
- PDF preview is not built. `pdfrx` resolved in a dry run, but it needs a
  PDFium binary fetched at build time and cannot be checked on all platforms
  without CI on those platforms (Phase 2). It stays open and reuses the same
  segment when added.

## Consequences

- No new native code, no web view, no network from the preview.
- Pages that depend on scripts or remote assets look incomplete by design.
