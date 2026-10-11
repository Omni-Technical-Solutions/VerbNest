# Changelog

Versioning follows `docs/spec/roadmap.md` (Release workflow): feature = major, minor = minor, fix = patch, chore = no version change. The build number is separate and rises with every build (`BUILD_NUMBER`). One version covers the whole workspace.

## 0.59.0

- Feature: wrap long lines. A Wrap button in the response toolbar breaks long lines of the Pretty and Raw views onto several rows instead of scrolling sideways. Folding, search highlights and copy-path still work. A body over 2000 lines, or with a line over 20000 characters, ignores it and keeps the fast fixed rows. On phones under 360 dp wide the button sits next to the search field, which opens from the search button.
- Feature: swipe between Request and Response. On a phone, swiping left or right on the Request/Response switch moves between the panes (reversed in a right-to-left layout); the switch itself still works as before. The swipe is limited to the switch so it does not compete with scrolling inside the panes.
- Tests: `code_wrap_test.dart` (wrap on and off, folding and search while wrapped, size caps), a swipe test in `phone_fit_test.dart`; compact and phone goldens regenerated for the new toolbar button.

## 0.58.1

- Fix: the iOS launch screen shows the VerbNest icon on a warm off-white background instead of a 1x1 placeholder image (the App Store build warned about the default launch image).
- Fix: the import dialog scrolls when the window is short and the keyboard is up (it overflowed by 16 px on a landscape phone).
- Fix: the environment chips on the Environments page scroll sideways with an edge fade on the smallest phones, so every environment can be reached.
- UI: the variables quick-look opens as a bottom sheet on phones and a dialog with a Close button elsewhere, like timings and TLS.
- Tests: the device matrix now covers the import dialog, examples dialog, and the Environments and Settings pages with the keyboard up; quick-look sheet and dialog tests.

## 0.58.0

- Removed: Arabic. VerbNest is now English only. The Arabic translations, the Language setting and the right-to-left language tests are gone. A workspace that had Arabic selected opens in English; its saved setting is left alone and nothing else changes. Strings stay in ARB files and the layout keeps using directional APIs, so a language (including a right-to-left one) can be added again later.
- Docs: the App Store review notes now explain the `network.server` entitlement (the OAuth redirect receiver and the optional mock server, both loopback only), give reviewer steps to see each feature, and list the macOS release entitlements. The App Store description no longer mentions Arabic.
- Tests: the l10n guard now checks that English is the only shipped language; a test checks that a saved unshipped language falls back to English.

## 0.57.0

- Fix: the Scripts tab's Pre-request / Post-response switch no longer runs off a phone screen (the segments share the width and wrap), and its help text scrolls instead of overflowing.
- Fix: the GraphQL editor scrolls when the window is short or the keyboard is up, instead of squeezing the query and variables fields below a usable height.
- Fix: the collection runner's setup scrolls inside a share of the screen and the Run button is pinned below it, so it is always on screen; on a phone it is full width.
- Fix: large text. Every request tab scrolls when it is given less room than its form needs (the room grows with the text size), so the tabs no longer overflow at 200% or at iOS's largest size (310%), on a small phone, in landscape, or with the keyboard up.
- Tests: the device matrix now also covers every request tab, the GraphQL editor, the runner and the dialogs at every size with and without the keyboard, and large text (200%, 310%) at five sizes, all passing; `scroll_if_short_test.dart`.

## 0.56.0

- UI: scroll cues. A row that scrolls sideways now fades at the edge that has hidden content (the request and response tab bars on phones, where "Scripts" and "Assertions" used to be cut off with no hint). The fade follows the reading direction, shows only where something is hidden, and is invisible to touch and to screen readers.
- UI: the response code view shows a horizontal scrollbar whenever a line runs past the edge.
- UI: key/value tables (params, headers, form bodies) stack the value under the key on screens under 360 dp, so each field is about 270 dp wide instead of 90.
- UI: timings and TLS details open as a draggable bottom sheet on phones (swipe down to dismiss, drag up for more room) and stay a dialog with a Close button on larger windows.
- Not done: soft wrap in the code view (its fixed row height makes it a larger change), a swipe between Request and Response (the segmented switch stays), and the variables quick-look, which is still a dialog.
- Tests: `scroll_cues_test.dart` (the fade, including right-to-left and touch/semantics exclusion, the real tab bars, the scrollbar, stacked tables) and `detail_sheet_test.dart`.

## 0.55.0

- UI: height classes. A window under 480 dp tall (a landscape phone) never gets the list-beside-editor layout, however wide it is: 874x402 and 932x430 now use the one-pane layout with a navigation rail, and no status bar. Windows that are wide and tall enough keep list and detail.
- UI: in a short window the request and response sit side by side (the stacked split left each about 120 dp tall) and the split-direction button is hidden. The toolbar row is gone there: the environment picker and the menu (favourite, examples, WebSocket, SSE, subscription) sit in the URL row beside Send.
- UI: the navigation rail scrolls when the window is too short for its four destinations, and content stays clear of a display cutout (notch) on both sides in landscape.
- Tests: `landscape_test.dart` (height classes, layout choice, side-by-side panes, toolbar in the URL row, the rail scrolling, cutouts). The device matrix has no known failures left.

## 0.54.0

- UI: on a phone the URL bar is pinned at the top of the editor and the toolbar above it gets out of the way. It folds up while the on-screen keyboard is open and while you scroll the response down, and comes back when you scroll up. On wider windows it stays put.
- UI: under 360 dp the toolbar is one row: the environment picker plus a menu (favourite, examples, WebSocket, SSE and, for GraphQL, subscription). The method box and padding are tighter so the URL shows about 16 characters on a 320 pt phone (it showed 11).
- UI: on a phone the response toolbar is one row: Pretty, Raw and Hex, then buttons that open search and the JSONPath filter on demand (an active filter or search stays visible), and Copy. Save is an icon on phones, and the protocol version is dropped from the status line under 360 dp. With the toolbar folded the response body gets about 40% of a 360x640 screen and 35% of a 320x568 one (it was about 15%).
- Fix: the bottom of the response pane no longer needs the keyboard out of the way before you can read it: with the keyboard open the page scrolls, the URL bar stays visible, and Send is reachable at 740x360 landscape.
- Fix: the Pretty/Raw/Hex labels on very narrow phones keep the theme font (an override had dropped the font family).
- Tests: toolbar folding, pinned URL bar, narrow menu, one-row response toolbar and the screen-share targets (`editor_chrome_test.dart`); the device matrix now passes everywhere except three landscape-rail cases recorded for phase 3. Test fakes report the HTTP version as `1.1`, so the status line and the store screenshots read "HTTP/1.1" instead of "HTTP/HTTP/1.1" (the app itself was correct).

## 0.53.1

- Fix: the request editor no longer overflows when the window is short. The page scrolls: the panes get the space that is left (at least 240 dp) and you scroll past the rest. This fixes the on-screen keyboard on a 360x640 phone and landscape phones up to about 700 wide. Dragging the page dismisses the keyboard.
- Tests: a device size matrix (nine phone sizes, each with and without the keyboard) checks the editor, the URL field and Send above the keyboard, and the other screens; baseline goldens for the editor at five sizes; scroll tests. Known remaining failures are listed per plan phase in the matrix test: landscape phones 874 wide and up overflow the navigation rail (height classes, phase 3), and the URL row on a 740x360 phone sits under the keyboard until it is pinned (phase 2).

## 0.53.0

- UI: Android Material You. A new Settings switch, "Use system colours", takes the colour scheme from the wallpaper on Android 12 and newer. It is off by default, shown only on Android, and the accent picker is dimmed while it is on. Where the system offers no colours the accent colour is used. Flipping the switch keeps you on the Settings page.
- Tests: `dynamic_color_test.dart` (a system scheme is used as is, the preference is remembered, the switch is shown only on Android, the page stays put).
- Not verified on a device: the system colours themselves come from Android's palette API, which tests cannot reach.

## 0.52.0

- UI: bundled fonts. Text is set in Inter and code (the body, headers, URLs, scripts and JSON viewer) in JetBrains Mono, so the app looks and measures the same on every platform instead of depending on what is installed. Scripts the bundled fonts lack, such as Arabic, fall back to the system font. Both fonts are licensed under the SIL Open Font License; their texts ship with the app and appear on the licence page. App size grows by about 2 MB.
- Fix: a second click on a collection row soon after the first (which pins the tab) now uses a timer rather than the wall clock, so it behaves the same under load and in tests.
- Tests: `fonts_test.dart` (fonts and licences declared, present and valid, theme and code use them). Goldens now render with the bundled fonts instead of Roboto; the Roboto test fonts were removed.

## 0.51.0

- UI: windows 1200 dp and wider use a permanent Material 3 navigation drawer (logo, name, and the four destinations with labels beside the icons) instead of the rail. Windows from 840 to 1199 dp keep the rail. In right-to-left languages the drawer sits on the right.
- Tests: drawer tests (shown from 1200, rail below, choosing a destination, right-to-left).

## 0.50.0

- Accessibility: the main screens (collections, request, response, history, environments, settings) pass Flutter's accessibility guidelines on a phone: every tappable element has a label, touch targets are at least 48 dp (Android) and 44 dp (iOS), and text meets WCAG AA contrast in light and dark. The sidebar's right-click detector no longer shows up to screen readers as an unlabelled button (its actions are in the labelled row menu). The response timing chip is 48 dp tall on touch screens.
- Accessibility: the app copes with very large text. The main screens are tested at 200% and 310% (iOS Dynamic Type's largest accessibility size) with no overflow; the response status line, body toolbar and empty states scroll when large text leaves them no room.
- iOS: a light haptic tap on Send and on Copy (response body, generated code) on touch platforms; none on desktop. iOS and macOS keep the Cupertino swipe-back transition (the page transition theme now lists every platform).
- Android: edge to edge with a transparent system navigation bar whose icons follow the theme, and predictive back (the back gesture previews the page underneath).
- Tests: `accessibility_test.dart` (labels, 48 and 44 dp targets, text contrast in both themes, 200% and 310% text) and `platform_polish_test.dart` (haptics, transitions, navigation bar style).
- Not verified on devices: VoiceOver and TalkBack walkthroughs, predictive back and edge to edge on a real Android 14+ device, and haptics on hardware. These are covered by automated semantics and unit tests only. Android Material You colour was not added (it was an optional decision).

## 0.49.0

- UI: a status bar along the bottom of windows 840 dp and wider: workspace name, the environment in use, whether the open request is saved ("Saved" or "Saving…"), cookie count (opens the cookie manager), a warning when certificate checks are off, a proxy indicator, and the network console with its entry count.
- UI: preview and pinned tabs. A single click on a request opens it in an italic preview tab that the next single click replaces; a second click on the same row, a double-click on the tab, or any edit pins it. Tabs can be dragged to reorder.
- UI: the macOS menu bar is native: VerbNest, File, Edit, Request, View and Window menus with the app's shortcuts (New request, Close tab, Search, Send, Toggle sidebar, Command palette, Keyboard shortcuts), the standard application and window items, and Cut, Copy, Paste, Select All, Undo and Redo that act on whatever has focus.
- UI: environments can be switched from the command palette ("Switch environment to …", "Use no environment"), so the whole send flow works from the keyboard.
- Tests: tabs (preview, pin, move, drag), status bar, a keyboard-only pass (palette, environment, tab switch, send) and the macOS menu structure.
- Not verified on a real Mac window: the native menu bar. A check with the running app was blocked by a macOS Accessibility prompt, so it is covered by unit tests of the menu structure only.

## 0.48.0

- UI: the app follows the five Material 3 window size classes (compact under 600, medium 600 to 839, expanded 840 to 1199, large 1200 to 1599, extra large 1600 and up). The collection list now sits beside the editor from 840 dp (it used to need 1024), so an iPad in portrait or a narrow desktop window gets list and detail.
- UI: on a phone the request and response are no longer stacked. After Send, a Request | Response switch gives the result the whole screen; both stay mounted, so the selected request tab and what you typed are kept.
- UI: on a wide editor (1100 dp or more) the response sits beside the request by default, as a supporting pane. Once you pick a direction with the toggle, that choice wins. Saved layouts without a choice follow the width.
- UI: the command palette and workspace search are full screen on a phone and a box near the top on a wide window. Generate code, Workspaces and Examples use a new shared adaptive dialog: full screen with a close button and a bottom action bar on a phone, a centred dialog otherwise. Examples stack the list above the detail on a phone.
- UI: the History page is a readable column (up to 960 dp) on wide windows.
- Tests: `adaptive_layout_test.dart` (size-class breakpoints, dialog forms, pane direction, list beside editor at 840), and the overflow matrix now also opens the palette and search at every width.

## 0.47.0

- UI: Material 3 visual system. The accent now follows the icon's orange (seed `#EB6A1A` with the `vibrant` scheme variant, which keeps the colour orange where the default turned it brown and `expressive` turned it purple). Text roles meet WCAG AA in light and dark for every accent; the light-theme orange for POST, warnings and numbers was darkened because it was under 4.5:1.
- UI: shape, elevation and motion follow Material 3. Corner radii are steps of the shape scale (4, 8, 12, 16, 28; dialogs use 28), buttons are fully rounded again, cards are tonal instead of outlined, the sidebar and navigation rail use the low surface-container tone, and animation durations and easing come from the Material 3 tokens. The response panel uses secondary tabs. Timings, sizes and status pills use tabular figures. The empty state shows the app logo.
- Tests: new `material3_theme_test.dart` (contrast for every accent in both themes, method and status colours, the shape scale, motion tokens, and a check that no colour literal appears outside the tokens file). Goldens now render with real Roboto and Material icons from `test/fonts/` (about 2 MB, Apache 2.0 licence included) and a 0.5% comparison tolerance for cross-OS text smoothing. New `layout_goldens_test.dart`: the workspace at phone, tablet and desktop widths, light and dark, plus Arabic right to left.
- Fix: the sidebar background no longer hides list-row highlights.

## 0.46.1

- UI: the request editor now fits a phone. Method and URL share one row with an icon-only Send button (the URL gets about 20 characters on a 402 pt screen instead of 3), the favourite, examples, live and environment controls sit in one wrapping toolbar, and the environment picker shrinks to the available width. The response pane stays out of the way until you send, response tabs scroll instead of cutting labels, and the view toggle, search and copy button stack on narrow screens. Environment variables stack name, value and current value on phones. The split-direction button no longer floats over the request tabs on phones.
- UI: keyboard shortcut hints (the Send badge and "Ctrl/Cmd + Enter") only show on macOS, Windows and Linux.
- Tests: `phone_fit_test.dart` pumps the request editor and environments page at 320, 360, 402 and 599 pt and fails on any overflow, a URL field under 110 pt, or lost request-tab selection.

## 0.46.0

- Rename: the product name is now written **VerbNest** (capital N) everywhere it is shown: window titles on every platform, the Android, iOS and macOS app names (the macOS bundle is `VerbNest.app`), Windows file properties, the OAuth sign-in page, error messages, CLI help, store listings, README and docs. Identifiers stay as they were: package and binary names (`verbnest_*`), bundle id `com.omni.verbnest`, the `X-Verbnest-Example` and `X-Verbnest-Delay` headers, and the `Verbnest` workspace folder, so existing workspaces and scripts keep working. The User-Agent is now `VerbNest/<version>`.

## 0.45.0

- UI: new design foundation. Theme tokens (spacing, radii, motion) and an `AppColors` extension replace the hard-coded colours for HTTP methods, status classes, syntax and highlights, so they follow light and dark mode. Rounded inputs, dialogs, menus, tabs and tooltips, with a visible focus ring. Animations respect the system "reduce motion" setting.
- UI: the request editor has a draggable divider between request and response (stacked or side by side, remembered per device), count badges on the Params, Headers and Assertions tabs, a coloured method selector, a Send button that shows its shortcut and swaps with Cancel, and an animated banner for warnings. The response pane shows a slim progress bar while sending, a status pill, a timing chip that looks tappable, and proper empty and error states.
- UI: editor tabs show the HTTP method and a close button that appears on hover; middle-click closes a tab. The sidebar can be resized (double-click the handle to reset), rows have a right-click menu, and Search, Import and Workspaces moved into one menu. Pages fade between sections.
- UI: deleting a collection, folder or request and moving or dragging an item offer Undo in a toast (restores the subtree, container variables and saved examples; version history is not restored). The sidebar collapses with a slide animation. The command palette groups entries (Commands, Go to, Requests) and highlights matches in subtitles too. Settings gain an accent colour picker and a compact layout toggle. Hovering a JSON line in the response viewer offers "Copy JSON path" (for example `$.items[0].id`). The runner shows a progress ring with a percentage, and key/value rows fade in when added. Monospaced text prefers JetBrains Mono, SF Mono, Menlo or Consolas when installed.
- UI: closing a tab shows an Undo toast, the command palette bolds the matching letters, the response pane shows a pulsing skeleton while loading, folders have an animated chevron, and Settings and Environments sit in a centred column (Settings in cards). Code text uses one shared monospace style.
- UI: the command palette shows shortcuts, and a new "Keyboard shortcuts" sheet opens from the palette or with Ctrl/Cmd+/. Toasts have an icon; empty screens (history, console, runner, collections) explain what to do next.

## Unreleased

- Security: a `-v name=value` override of a secret variable is now treated as secret (masked in reports and history, and subject to approved hosts). GraphQL SDL and introspection type references nested deeper than 64 levels are rejected with a format error instead of overflowing the stack.

- Chore: the script JS prelude moved to `packages/verbnest_script/assets/prelude.js` (generated into Dart by `tool/gen_prelude.dart`, checked by a test); GraphQL lexer and completion split into helpers; storage rows read through typed accessors that name the column on a bad value (`StorageFormatError`).

- Security: workspaces start with scripts off. Turn on "Run scripts in this workspace" in Settings for workspaces you trust. Scripts no longer receive secret variables, `pm.sendRequest` cannot reach link-local or cloud metadata addresses, and the CLI runs Node with `--permission` where available.
- Security: on a cross-origin redirect only a short list of safe headers is kept (it was a denylist). Header values with CR, LF or NUL are refused. The OAuth sign-in callback is accepted only with the right `state`, the authorize URL must be http(s), and token requests never follow redirects.
- Security: cURL export quotes the method and uses `--form-string` for text fields. Snapshot writes reject backslash, drive-letter and symlink paths.
- Security: response bodies and decompressed bodies are capped at 512 MiB, YAML imports are limited in size and depth (alias bombs), and the mock server limits request bodies to 1 MiB and refuses non-loopback Host headers. The masker also hides percent-encoded and JSON-escaped secrets. Release signing can be made mandatory with `VERBNEST_REQUIRE_RELEASE_SIGNING=1`. CI actions are pinned by commit SHA.
- Security: WebSocket messages and SSE lines are capped at 16 MiB, HTTP/2 bodies at 512 MiB. Cookies with control characters, over 4096 bytes, or for common public suffixes (such as `co.uk`) are refused, and Max-Age is capped at 400 days. Assertion and JSON Schema regular expressions that are invalid, over 500 characters or have nested quantifiers are refused instead of run. Dependabot now watches Actions and pub dependencies.
- Security: the CLI no longer runs workspace scripts by default. Pass `--allow-scripts` to run them (only for workspaces you trust). `--no-scripts` is still accepted.
- Security: exporting a snapshot refuses paths inside `.git` directories (no git hooks can be written).
- Security: secret variables are only sent to hosts you approved for them. The first send of a secret to a new host stops with a banner ("Always allow and send" or Cancel); approvals are kept in the secret store, not in the workspace file, so a tampered copy of a workspace cannot send your secrets elsewhere. The CLI with `--vault` refuses unapproved hosts; approve them in the app or pass `--allow-secret-host NAME=HOST` (`*` works for either side).

- Security: on a cross-origin redirect the Authorization, Proxy-Authorization and Cookie headers are now always dropped, even for requests that turned off auth stripping. Run reports (CLI stdout, JSON, JUnit, HTML) mask secrets that ended up in the resolved URL. Snapshot exports blank literal credentials in auth fields (variable references are kept), and snapshot imports ignore `verifyTls` and proxy settings from the file.

## 0.44.0

- All dropdowns converted from `DropdownButton` to `DropdownMenu` (Material 3). The old `DropdownButton` had a hardcoded 300ms menu overlay animation that caused a visible fade when selecting an item. `DropdownMenu` uses `MenuAnchor` with `animated: false` by default, so menus open and close instantly. Affected: auth type, JWT algorithm, OAuth2 grant, HTTP method, body mode, HTTP version, language, GraphQL operation, code language, environment, assertion target, assertion operator.

## 0.43.0

- Renamed the app from PostIt to Verbnest (ADR-015, `docs/spec/rename-plan.md`). Packages are `verbnest_*`, the CLI is `verbnest` (and `vn`), workspace files are `.verbnest`, the bundle id is `com.omni.verbnest`, env vars are `VERBNEST_*`, mock headers are `X-Verbnest-*`.
- Old data keeps working: `.postit` files open, `postit.yaml` snapshots import, `POSTIT_VAR_*`/`POSTIT_HISTORY_DB` and `X-PostIt-*` are still read, secrets under the old keychain key move to the new one, and the old app-data folder is copied on first start.
- Not carried over: the `postit` command (use `verbnest` or `vn`). Android installs under a new package id, so it is a new app to the stores.

## 0.42.0

- CLI: `postit run --history <db>` records sent requests in a history database (same format as the app, secrets masked, `--no-history-bodies` to skip bodies); `postit history <workspace> --db <db>` lists, shows, searches and clears them. `POSTIT_HISTORY_DB` sets the path.
- CLI: `postit run --vault` reads secret variables from the system secret store (macOS Keychain, Linux libsecret). Not available on Windows. ADR-014.

## 0.41.0

- Response: PDF preview. `application/pdf` responses get a "Preview" segment that renders the pages with PDFium (`pdfrx`). PDFs above 20 MB, and unreadable ones, show a message. ADR-013.

## 0.40.0

- GraphQL: persisted queries (Apollo APQ). Turn on the "Persisted query" chip and the request sends only `extensions.persistedQuery.sha256Hash` (in the body, or in the URL for GET). If the server answers `PersistedQueryNotFound`, the full query goes out once. Curl and code export include both the query and the hash.

## 0.39.0

- Scripts: `pm.sendRequest(url | request, callback)` and `pm.cookies.get/has/toObject`, in the app, the runner and the CLI. Requests go through the engine's cookie jar, proxy and certificates, at most 10 per script. The script is replayed after each answer (ADR-012), so keep scripts repeatable. Promises and `pm.cookies.jar()` are not supported; the CLI has no cookie jar, so `pm.cookies` is empty there.

## 0.38.0

- WebSocket: the live dialog can send binary frames. Tick "Hex" and type bytes such as `0a ff 10` (`parseHexBytes` in `postit_http`). Bad input shows an error and sends nothing.

## 0.37.0

- GraphQL over GET: with method GET the operation is sent as `query`, `variables` (JSON) and `operationName` URL parameters and the request has no body. cURL and code export follow the same rule. Persisted queries are not supported yet.

## 0.36.0

- Live dialog: "Save log…" writes the session as a text file (`formatRealtimeLog` in `postit_http`: UTC time, direction `>` `<` `*`, SSE event name). The Arabic text needs review.

## 0.35.0

- SSE: the live dialog reconnects when the server ends the stream. It waits for the server's `retry:` delay (3 s by default, at most 60 s), sends `Last-Event-ID`, and gives up after 5 failed attempts in a row. Closing the dialog stops it. `connectSse(reconnect: true)` in `postit_http`.

## 0.34.0

- Mock server: routes now pin the query parameters (a fixed value, or presence only when the saved value is empty or a variable) and the raw body (JSON compared by value) of the saved request. The most specific match wins; if nothing matches exactly, the least specific route on that method and path answers. `X-PostIt-Delay: <ms>` delays one reply and `postit mock --delay <ms>` sets a default (capped at 30 s).

## 0.33.0

- Response view: a "Preview" segment for `text/html` responses. The page is rendered as static widgets (no scripts, no network, links ignored); pages above 2 MB show a message. PDF preview is not included yet (ADR-011).

## 0.32.10

- UI strings: the request editor (URL bar, tabs, settings, banners) now uses ARB (English and Arabic). Every screen file is migrated; `l10n_guard_test.dart` has an empty pending list and fails when a new hard-coded `Text` literal appears. Arabic texts still need a native review.

## 0.32.9

- UI strings: the response view (tabs, timing, TLS, tests, body tools) now uses ARB (English and Arabic). One file remains in `l10n_guard_test.dart`.

## 0.32.8

- UI strings: the collections sidebar (menus, empty states, import dialog) now uses ARB (English and Arabic). Two files remain in `l10n_guard_test.dart`.

## 0.32.7

- UI strings: the GraphQL editor, SDL import dialog and schema explorer now use ARB (English and Arabic). Three files remain in `l10n_guard_test.dart`.

## 0.32.6

- UI strings: the authorization editor (all auth types and OAuth 2.0) now uses ARB (English and Arabic). Four files remain in `l10n_guard_test.dart`.

## 0.32.5

- UI strings: network settings (proxy, certificates), the client certificate dialog, favourites and examples now use ARB (English and Arabic). Five files remain in `l10n_guard_test.dart`.

## 0.32.4

- UI strings: the workspaces dialog, settings page and script editor now use ARB (English and Arabic). Seven files remain in `l10n_guard_test.dart`. Arabic texts still need a native review.

## 0.32.3

- UI strings: the network console, cookie manager and code generation dialog now use ARB (English and Arabic). Arabic texts still need a native review.

## 0.32.2

- UI strings: the collection runner, history (list and detail) and environments pages now use ARB (English and Arabic). Arabic texts still need a native review. The remaining files are listed in `l10n_guard_test.dart`.

## 0.32.1

- UI strings: name and confirm dialogs, the environment picker, version history, the key-value table, the assertions builder and the OAuth token manager now use ARB (English and Arabic). Arabic texts still need a native review. 16 files still hold hard-coded text (see `l10n_guard_test.dart`).

## 0.32.0

- Scripts in the CLI: `postit run` now runs pre-request and post-response scripts, tests (`pm.test`, `pm.expect`), `pm.execution.setNextRequest` and `skipRequest`. Scripts run in `node` (change with `--js-runtime`, switch off with `--no-scripts`). Variables a script sets are kept for the run and never written to the workspace. Without a runtime, requests with scripts still run and are listed on stderr as not scripted. See ADR-010.
- New package `postit_script` (no Flutter code): the script contract, `pm` runtime, phase runner and request mapping moved out of the app. The app keeps its embedded engine behind the same interface and its tests are unchanged.
- Not done: `pm.sendRequest` and `pm.cookies` (unsupported in the app too). Node differs from QuickJS in rare language edge cases. Windows and Linux are not verified.

## 0.31.1

- UI strings: the realtime and mock-server dialogs now use ARB (English and Arabic). New guard test `l10n_guard_test.dart` lists the files that still hold hard-coded `Text` literals (22 files) and fails when a migrated file regains one, a pending file is already clean, or the Arabic file lacks a key. Found that `context.l10n` already falls back to English in bare-`MaterialApp` widget tests, so migrating needs no test changes. The Arabic texts need review by a native speaker.
- New `docs/spec/remaining-work-plan.md`: the remaining work in five phases (ARB migration, Windows/Linux verification, HTML/PDF preview, CLI scripts, follow-ups).

## 0.31.0

- GraphQL subscriptions: with a graphql body, the live button offers "GraphQL subscription". It connects over the `graphql-transport-ws` protocol, waits for the server's acknowledgement, subscribes with the request's query and variables, and shows each result. Close sends `complete`. The older `subscriptions-transport-ws` protocol is not supported.
- WebSocket, SSE and subscriptions now follow the manual HTTP proxy and the system proxy setting (with Basic credentials). SOCKS5 proxies are refused with a clear message; `dart:io` cannot tunnel them for these connections.
- Collection runs skip `ws://` and `wss://` requests with a note instead of failing, in both the app and the CLI.
- Mock server in the app: the runner page has a "Mock server" button that starts and stops the mock on a chosen port and lists its routes.
- Scale check: a test builds 5,000 requests and times listing and search. On this Mac: build 1.2 s, list 20 ms, index 120 ms, search 3 ms. No change needed.
- Still not done: moving the remaining UI strings to ARB, HTML and PDF preview, scripts in the CLI, a first CI run, Windows and Linux checks.

## 0.30.0

- Mock server: `postit mock <workspace.postit>` serves the saved examples (FR-COL-005) of a collection or folder over HTTP until Ctrl+C. Each request with examples answers on its method and URL path (variables resolved from the workspace, `--env` and `--var`; `:id` and `{{var}}` segments match anything). The first example answers; an `X-PostIt-Example: <name>` header picks another. Other requests get a 404 listing the routes. Options: `--collection`, `--env`, `--var`, `--port` (default 3000).
- Built in `postit_runner` (`MockServer`, `workspaceScopes`) so the app can offer it later with no new logic. Query strings, request-body matching, response delays and templating are not done. Listens on 127.0.0.1 only. Tested against a local client; Windows and Linux are not verified.

## 0.29.0

- Command-line runner: `postit run <workspace.postit>` runs a collection or folder and exits 0 when every request and test passed, 1 on any failure, 2 on a usage or file error. Options: `--collection` (name, id or `Collection/Folder`), `--env`, `--var name=value` (also `POSTIT_VAR_<name>` in the environment), `--data` (CSV or JSON), `--iterations`, `--delay`, `--bail`, `--insecure`, and `--reporter cli|json|junit|html` with `--out`.
- New packages `postit_runner` and `postit_cli`, both without Flutter code. The run loop (iterations, data rows, delays, `setNextRequest` jumps, stop rules) moved out of the app into `postit_runner` (`executeRun`); the app's runner now calls it, so the app and CLI cannot drift apart. `HeadlessSender` sends one request with variables, auth chain, assertions and OAuth 2.0 non-interactive grants.
- Not in the CLI: pre-request and post-response scripts (no JavaScript runtime outside the app; the CLI names the requests whose scripts it skipped), browser OAuth sign-in, secret values kept in the app's secret store (pass them with `--var`), request history. Tested against the local test server; Windows and Linux are not verified.

## 0.28.0

- WebSocket and server-sent events: the new live button next to Send in the URL bar opens a message log for the request's URL. WebSocket connects with the request's headers and auth, lets you send text and shows text and binary frames, and reports the close code and reason. SSE shows each event with its name and id. Both use the request's TLS, certificate and timeout settings.
- Built as ADR-009 says: `RealtimeConnection`, `connectWebSocket`, `connectSse` and `SseParser` are in `postit_http` with no Flutter code, so the CLI can reuse them. Tested against local servers.
- Not done: saving messages with the request, binary sends, automatic reconnect with `Last-Event-ID`, proxy support for live connections (they connect directly), GraphQL subscriptions, collection runs do not skip live requests (a `ws://` URL in a run fails like any unsupported scheme). Windows and Linux are not verified.

## 0.27.0

- GraphQL (FR-GQL-001/002): a new "graphql" body mode with a query editor and a JSON variables editor. The request is sent as a JSON POST (`{"query", "variables", "operationName"}`); `{{variables}}` work in the query and variables. Choosing the mode on a GET request switches it to POST. When the query holds several operations, a picker sets `operationName`.
- Schema: "Fetch schema" sends the introspection query to the request's URL with its headers, auth and environment (no scripts run). "Import SDL…" reads a pasted schema or a `.graphql` file. The schema is kept in the workspace per URL as typed, so `{{baseUrl}}/graphql` keeps it across environments.
- Completion: with a schema, chips under the query editor suggest fields (inside selection sets, inline fragments and unions) and argument names, filtered by what you typed. Choosing an object field also opens its selection set.
- Schema explorer: "Explore" browses root operations and types, follows field types, and filters by name.
- Postman graphql bodies import and export (they were kept as an unsupported body before). cURL and code generation (JavaScript, Python, Dart) send the JSON payload. A script sees the payload as `pm.request.body`; if it rewrites it, that send uses a plain JSON body.
- Built as ADR-009 says: the body model, payload builder, SDL parser and introspection model, and completion are in `postit_core` with no Flutter code, so the future CLI and runner reuse them.
- Not done: subscriptions (need WebSocket, next), GraphQL over GET, persisted queries, query formatting, `@directive` and variable-name completion, `extend schema`, SDL features beyond what is listed (`interface implements interface` is read but not shown). Introspection does not run pre-request scripts, so APIs that need a script-made token must have it in a variable. Tested with unit and widget tests against hand-made schemas, not against real servers. Windows and Linux are not verified.

## 0.26.0

- HTTP/2 (FR-HTTP-007): HTTPS requests offer `h2` and `http/1.1` through ALPN and use HTTP/2 when the server picks it. Request Settings has a new "HTTP version" choice: Auto, HTTP/1.1 only, HTTP/2 only. The response shows the protocol. Built on the `http2` package (ADR-008). The "Sent" view for HTTP/2 lists the pseudo-headers and lower-case fields as encoded, not raw bytes. Not done: HTTP/2 over plain `http://`, connection reuse, server push.
- Timing breakdown (FR-RES-005): tap the time in the response status line to see DNS, TCP connect, TLS handshake, waiting (TTFB), download and other time. The engine already measured these; they were not shown before.
- Response filter: JSON bodies take a JSONPath, XML bodies take an XPath. A bad expression shows the reason and keeps the body. Uses the existing JSONPath subset and the `xml` package's XPath.
- Hex view of the response body (first 64 KB).
- Import safety: a file or pasted text over 64 MB is refused with a clear message. New fuzz tests feed mutated Postman, OpenAPI, HAR and cURL input to the importers; they found no crashes.
- CI now runs package tests on Linux, Windows and macOS, and app tests on Linux and Windows. The workflow has still never run.
- New test server listener for HTTP/2 (`test_server/lib/h2_server.dart`).
- Not done: moving the remaining UI strings to ARB (tests build the widgets without localisation delegates, so each screen needs its tests changed too), HTML preview, PDF preview, profiling very large workspaces. Checked with unit and widget tests on macOS, and by hand against `nghttp2.org` and `cloudflare.com` over HTTP/2. Windows and Linux are not verified.

## 0.25.2

- Fix: in right-to-left languages, code and JSON in the response, code generator and similar views, and fields for URLs, headers and variables, were mirrored. They now always read left to right.
- Added `scripts/screenshots_macos.sh`, which renders 18 App Store screenshots (2880x1800) from sample data, and the listing copy in `docs/release/app-store-post.md`.

## 0.25.1

- Security: the OAuth 2.0 sign-in only opens http and https links, so an imported collection cannot make PostIt open a `file:` or app-link URL.
- Security: when a redirect goes to another origin, headers that look like credentials (`X-Api-Key`, `X-Auth-Token`, anything with auth, token, secret, key, session or cookie in its name) are now removed as well, not just `Authorization` and `Cookie`. The existing "strip on cross-origin redirect" setting still controls this.
- Security: writing a snapshot refuses file names that are absolute or contain `..`; reading a snapshot folder does not follow links and refuses files over 256 MB.
- Speed: a response body is decoded once instead of on every screen update, and a large pretty-printed JSON body is formatted once per response instead of on every keystroke in the search box.
- Speed: workspaces get an index on saved examples (schema 2, applied when a workspace is opened), which makes deleting requests and folders faster. Cleaning up unused attachments at open is now one pass over the data instead of one search per attachment.
- Reviewed and unchanged: database queries all use bound parameters; scripts have no file or network access and are limited to 64 MB and 5 s; the OAuth redirect listener binds to the local machine only and checks `state`; secrets stay masked in history and the console.
- Not done: no fuzzing of the importers, no limit on the size of an imported file in the UI, and no profiling with very large workspaces (tested with unit tests only).

## 0.25.0

- Language setting (FR-APP-005): Settings, "Language" picks System default, English or Arabic, and is remembered in the workspace. The Settings page text is translated; other screens still have fixed English text, and the Arabic is a draft that a native speaker has not reviewed.
- Postman saved responses are now imported as examples and written back on export (they were dropped before).
- Script editor: JavaScript syntax colours (keywords, strings, numbers, comments, `pm` and `console`) and `pm.` / `console.` completion chips while typing. No full parser, so it only colours and suggests.
- Internal clean-up with no behaviour change: snapshot import, cURL parsing, the collection runner loop and request sending were split into smaller steps.
- Checked with unit and widget tests on macOS; not tried by hand.

## 0.24.0

- Favourites (FR-COL-004): star a request in the editor or from its menu; starred requests show a star in the tree, and a header button shows only favourites.
- Saved examples (FR-COL-005): "Examples" in the request editor saves the current response (status, headers, body) with the request, and lists, shows and deletes them.
- Command palette (FR-APP-003): Ctrl/Cmd+K, type to find commands or any request. Workspace search is now Ctrl/Cmd+Shift+F.
- YAML snapshot export and import (FR-WS-006), desktop only: Workspaces, "Export snapshot…" writes a folder of YAML files that gives the same bytes every time, so it diffs cleanly in git. "Import snapshot…" merges by id into the open workspace and keeps anything already there.
- Localisation-ready strings (FR-APP-005): ARB files and generated code are set up with English and an Arabic first draft for the navigation and palette. Layout paddings and alignments now follow the text direction, so right-to-left languages mirror.
- Not done: most screens still have fixed English text, there is no language setting (the device language is used), the Arabic draft has not been reviewed by a native speaker, and snapshots cannot be imported or exported on phones. Checked with unit and widget tests on macOS; the folder picker was not used by hand.

## 0.23.0

- Import OpenAPI 3.0/3.1 and Swagger 2.0 (JSON or YAML) (FR-IO-004): one folder per tag, a `baseUrl` variable from the server, query, header and path parameters, request bodies with example values built from the schema, and the first security scheme (basic, bearer, API key) as the collection's auth. Optional parameters are listed but switched off.
- Import HAR captures: one request per entry.
- Import a single JSON file with `collections` and `environments` lists (Postman backup shape).
- Generate code (request menu, "Generate code…"): cURL, JavaScript (fetch), Python (requests) and Dart (http). Variables stay as `{{names}}` unless you switch on "Fill in variable values".
- Not done: references to other files, per-operation security, OAuth 2.0 schemes, Postman's zip data dump (unzip it and import the files), OpenAPI and HTML docs export. Tested with unit tests only; not tried on large real specs.

## 0.22.0

- Cookie jar (FR-HTTP-011): cookies from `Set-Cookie` are saved per workspace on this device and sent to matching requests, also across redirects. Domain, path, Secure, Max-Age and Expires are honoured. Manage them in Settings, Cookies: delete one, a domain or all. A request can turn this off in its Settings tab.
- Proxy (FR-HTTP-012): HTTP proxy (plain requests and CONNECT tunnels for HTTPS) and SOCKS5, both with optional user name and password, plus a no-proxy host list. Optionally read `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY` from the environment. A request can bypass the proxy. With SOCKS5 the proxy resolves the host name.
- Certificates (FR-HTTP-013): add trusted CA certificates and client certificates (PEM with key, or PKCS#12) for chosen hosts. Private keys, passphrases and the proxy password go to the secret store. After a secure response, tap TLS to see the subject, issuer, validity, protocol and whether a client certificate was sent.
- Not done: HTTP/2, the operating system's own proxy settings, PAC files, NTLM/Kerberos proxies. Checked with `dart test` on macOS only; the Settings screens were not tried by hand. Windows and Linux are not verified.

## 0.21.0

- OAuth 2.0 authorization code (with or without PKCE S256) and implicit grants through the system browser (FR-AUTH-003). The redirect is `http://127.0.0.1:<random port>/callback`, received by a short-lived local listener; the state value is checked, the sign-in can be cancelled, and it times out after 5 minutes.
- Refresh tokens: an expired token with a refresh token is renewed without the browser; if the server refuses it, the browser sign-in runs again.
- Token manager ("Tokens…" in the OAuth 2.0 auth editor) lists the tokens kept for this session and deletes them. Token values are never shown. Tokens are not saved to disk.
- Digest auth (MD5 and SHA-256 families, `auth` and `auth-int`): the request is sent once, then re-sent with the computed header after a 401 challenge (FR-AUTH-004).
- JWT bearer with HS256, HS384 and HS512; the payload may use variables, `iat` is added when missing.
- AWS Signature V4 (header signing, optional session token). Checked against the AWS test-suite vectors.
- Postman import/export covers digest, awsv4, jwt, authorization code (PKCE or not) and implicit.
- Authorization, `X-Amz-Security-Token` and secrets stay masked in the console, history and sent view.
- New dependency: `url_launcher` (opens the browser) and `crypto`. Checked to build and run the loopback tests on macOS, the iOS 18 simulator and the Android x86_64 emulator.
- Not done: JWT with RS/ES algorithms, a fixed redirect URL option and the mobile custom-scheme redirect (loopback is used on all platforms), query-string SigV4 and chunked S3 payload signing, device code flow. The real browser launch and a real identity provider were not tested; the sign-in tests drive the redirect in-process. Windows and Linux are not verified.

## 0.20.0

- No-code assertions (FR-SCR-006): status, header, JSON path, response time, body and JSON schema checks with equals, comparison, exists, contains and regex operators. Built in the new Assertions tab; values may use `{{variables}}`. Results show in the Tests tab with `pm.test` results.
- JSONPath subset (`$`, `.key`, `['key']`, `[n]`, `[-1]`, `[*]`, `.*`, `..key`) and a JSON Schema subset; unsupported syntax gives a clear error.
- Collection runner (FR-RUN-001/002): "Run…" on a collection or folder. Pick and reorder requests, set iterations and delay, stop on first failure, stop at any time, and use a CSV or JSON data file (one row per iteration, available as `{{name}}` and `pm.iterationData`). Results appear live.
- `pm.execution.setNextRequest(name | null)` and `pm.execution.skipRequest()` (pre-request only) control a run; `pm.iterationData` is read only. A jump to an unknown name ends the run with an error; a run stops after 10,000 steps.
- Run reports (FR-RUN-003): export JSON, JUnit XML and HTML.
- Assertions are evaluated in Dart, not compiled to JavaScript, so they work and are tested without the script engine.
- Not done: saved run history, parallel runs, running from the command line, cookie jar between iterations. The runner UI was not exercised by widget tests or by hand; the logic is covered by unit tests and the new `pm.execution` script test passes on macOS only (not re-run on iOS or Android). Windows and Linux are not verified.

## 0.19.0

- Scripting: pre-request and post-response scripts on requests, folders and collections, run collection → folder → request (FR-SCR-001). Engine: QuickJS through `fjs` (ADR-002).
- `pm` API: `pm.variables`, `pm.environment`, `pm.collectionVariables`, `pm.globals` (get/set/unset/has/replaceIn/toObject), `pm.request` (method, url, headers, body; editable before sending), `pm.response` (code, status, headers, text(), json(), responseTime, `to.have.status/header`, `to.be.ok`...), `pm.info`, `pm.test`, `pm.test.skip`, `pm.expect` with a Chai subset, `console.*`, and the old `postman.*` and `tests[]` forms.
- Not supported yet, and reported by name: `pm.sendRequest`, `pm.cookies`, `pm.visualizer`, `pm.execution`, `pm.iterationData`, `require`.
- Variable changes made by scripts are stored as current values, so initial (shared) values stay unchanged; new names are created in the scope.
- Sandbox: no files, sockets, `fetch` or timers; 5 s timeout and 64 MB memory cap per script; an infinite loop is stopped.
- Scripts tab on requests and on collection/folder settings; Tests tab in the response (pass/fail counts, messages, script errors, console output).
- A failing pre-request script stops the send; a failing post-response script keeps the response and shows the error.
- CI installs Rust for the builds that compile the script engine.
- Not done: script editor highlighting and `pm.` completion, snippets panel, no-code assertions, `pm.sendRequest`, async scripts, runner reports. Windows and Linux are not verified.

## 0.18.0

- Android: INTERNET permission and cleartext HTTP allowed (an API client must reach `http://` hosts); release APK builds (debug-signed, 61 MB, all ABIs).
- iOS: local network usage description; unsigned release/debug build works.
- macOS release binary is universal (x86_64 + arm64).
- CI: build matrix for Linux, Windows, macOS, Android and iOS, with integration tests on desktop (not run yet; the workflow has never executed).
- Test server can listen on TLS (self-signed localhost certificate made with openssl at test time; those tests skip without it); engine tests cover rejecting and accepting it.
- Integration tests `platform_test.dart`: FTS5 search, loopback request, 10,000-request workspace timings, request overhead.
- Not done: Windows and Linux were not built or run; iOS only ran in the simulator; no physical devices. This is not the 1.0.0 release.

## 0.17.0

- Console page: the last 200 requests of this session with the sent and received headers (secrets masked), cleared on exit.
- History is grouped by day and pruned by age and count; settings for days kept, maximum entries, and whether bodies are recorded (FR-HIS-001..004).
- Appearance settings: interface text scale and code font size, stored on this device.
- Shortcuts: Ctrl/Cmd+N new request, +S save now, +\\ toggle sidebar, Ctrl+Tab / Ctrl+Shift+Tab switch tab (plus Send, Search, Close tab from before).
- Open tabs are restored after a restart.
- Pasting a cURL command into the URL bar fills in the whole request.
- Not tested on a device: shortcuts on Windows/Linux, text scale with system accessibility settings on mobile.

## 0.16.0

- Workspace search (Ctrl/Cmd+K or the search button): names, URLs, methods, descriptions, header names and bodies; header values are not searched (FR-COL-003).
- Drag and drop in the sidebar (long press to drag): move into a folder or collection, drop before a request, reorder collections (FR-COL-001).
- Workspaces: switch between recent workspaces, create, rename, import and export `.postit` files (FR-WS-002..007). Imported copies get their own id.
- Earlier versions of a request can be listed and restored (FR-WS-008).
- Unsaved edits are saved when a tab or workspace closes.
- Not yet tested on touch devices or non-macOS platforms.

## 0.15.0

- Response body viewer rewritten: line numbers, JSON colours, fold/unfold of objects and arrays, search highlight, selectable text, virtualised so large bodies scroll (FR-RES-001..003).
- Image preview for PNG/JPEG/GIF/WebP responses.
- Response size shows the size on the wire when it differs from the decoded size.
- Response headers list with a copy-value button per header.
- Not yet: streaming bodies over 10 MB to disk, XML/HTML colours, hex view; render speed on a real 5 MB body was not measured.

## 0.14.0

- Files in requests: form-data file parts and a binary body mode with a file picker. Files are stored inside the workspace, so they travel with it (FR-HTTP-005/006).
- Save the response body to a file (desktop) or share it (mobile) (FR-RES-005).
- Attachment storage API; unused attachments are cleaned up at startup.
- macOS: user-selected file access entitlement.
- Not yet tested: the picker, save dialog and share sheet on any platform; very large files are held in memory.

## 0.13.0

- `{{variables}}` are highlighted in the URL, params, headers, form fields and raw body: defined ones in the theme colour, undefined ones underlined in red (FR-VAR-004).
- With the caret in a variable, a line shows its resolved value and scope (secrets stay hidden); typing `{{` offers matching variable names.
- Header name and Content-Type value suggestions.
- Bulk edit (`key: value` lines, `//` disables) for params, headers and url-encoded bodies.
- Headers tab lists the headers PostIt adds itself; adding the same header overrides it.
- The Sent tab now shows the request body as sent (masked, capped at 64 KB) (FR-HTTP-010).
- Not yet: hover tooltips, code-editor features (folding, line numbers).

## 0.12.0

- Secrets are stored in the system secret store (macOS Keychain verified; other platforms not yet tested) through `flutter_secure_storage`. Existing secrets move over on first start. If the store is unavailable, PostIt falls back to the old unencrypted device store and Settings says so.
- Plain variables have a device-local Current value next to the shared Initial value; requests use Current when it is set (FR-VAR-002).
- Show/hide toggle on secret values.
- Fix: collection and folder secret variables now resolve when sending.
- Not yet: `.env` import.

## 0.11.0

- Collection and folder settings page: description, auth, variables (FR-COL-002).
- Warning before send when variables are unresolved, with "Send anyway" and "Don't warn again" (setting) (FR-VAR-006).
- Custom HTTP method entry (FR-HTTP-001).
- Request settings: max redirects, keep method on redirect, strip auth cross-origin, auto-decompress (FR-HTTP-007).
- Duplicate variable names warn in the editor (last wins).
- Not yet: scripts on containers, variable highlighting.

## 0.10.0

- Response viewer: Pretty/Raw toggle, search with match count and highlight, read-only Cookies tab, copy body (FR-RES).
- History: open the original request or save an entry as a new request (secrets stay masked) (FR-HIS-002).
- Theme setting: system, light or dark, saved with the workspace (FR-APP-004).
- Not yet: save/share to file, image preview, FTS5 search, drag and drop.

## 0.9.0

- OAuth 2.0 client credentials and password grants (FR-AUTH-002): `OAuth2Auth` model, token fetch with Basic or body client auth, in-memory token cache, Postman import/export, editor UI.
- Workspace HTTP defaults in Settings (timeout, TLS verification, redirects), stored in the workspace and applied to every request.
- `SecretStore` interface in `postit_storage` with an interim local-database implementation (not encrypted; keychain adapters still to do).
- Keyboard shortcuts: Ctrl/Cmd+Enter sends, Ctrl/Cmd+W closes the tab.
- ADR-001, 002 (proposed), 004, 005; GitHub Actions CI (format, analyze, tests; not yet run on GitHub).
- Not yet: OAuth authorization code/PKCE, OS keychain, theme setting, history retention UI, Phase 0 spikes (scripting engine, platform builds).

## 0.8.0

- New `postit_import` package (FR-IO-001..003):
  - cURL import (`-X -H -d --data-raw --data-binary -F -u -b -k -L -I -G -A -e -m --url`, bundled short flags, quotes, line continuations) and export; unknown options are reported, not fatal.
  - Postman v2.1/v2.0 collection import and export: folders, auth, variables, per-request scripts, raw/urlencoded/form bodies, disabled rows, path variables; unsupported bodies and auth types are kept verbatim and written back. Postman environments and globals import and export (secrets omitted on export by default).
- App: Import dialog (paste cURL or Postman JSON), Copy as cURL, Copy as Postman JSON.
- Not yet: file pickers (import/export use paste and clipboard), `.postit` copy export in the UI (storage `exportCopy` exists), folder/collection scripts and saved examples (dropped with a warning), OpenAPI/HAR (P1).

## 0.7.0

- Environments and history (FR-VAR-002..004, FR-HIS-001/002):
  - Environments and globals page with a variables table; secret variables are never written to the workspace file (values kept in the device-local store until the OS secret store lands).
  - Environment selector and variables quick-look in the request editor; the active environment is remembered per workspace.
  - Every send (and engine failure) is recorded in local history with secrets masked; history page with search, detail view and clear.
- Desktop sidebar now shows only for Collections.
- Not yet: separate current vs initial values for non-secret variables, history retention settings UI.

## 0.6.0

- Request editor (FR-REQ, FR-HTTP-001..007, FR-RES):
  - Method, URL bar, Params (synced with the URL query and `:path` variables), Headers, Auth (inherit/none/bearer/basic/API key), Body (raw languages, urlencoded, form; binary kept but not editable), per-request Settings.
  - Debounced autosave of drafts; renames made in the tree are never overwritten.
  - Send and cancel; variables resolved from global, collection and folder scopes; undefined-variable and unsupported-auth banners.
  - Response viewer: status, time, size, pretty-printed JSON, headers and the masked request as sent.
  - Open-request tab strip on desktop; full-screen editor on phone and tablet.
- Not yet: environments, history recording, multipart file picking, scripts.

## 0.5.0

- App foundations (FR-COL-001/003, FR-WS-001):
  - Riverpod state, default workspace opened in app storage at start-up.
  - Collections sidebar: tree with filter, new collection/folder/request, rename, duplicate, move up/down, delete with confirmation; open-request tabs state.
  - Adaptive layout hosts the tree (sidebar on desktop, full page on phone and tablet).
  - `NodeInfo.method` in storage so the tree shows request methods cheaply.
- Request editor is the next step; selecting a request shows only its name for now.

## 0.4.0

- `postit_http` request pipeline (FR-HTTP-002..007, FR-VAR-006, FR-AUTH-001/006):
  - `RequestBuilder` turns a stored request into a sendable spec: variable substitution, `:path` variables, bearer/basic/API key auth (header or query), raw/urlencoded/multipart/binary bodies, default Content-Type that the user can override, workspace-default plus per-request settings.
  - Reports unresolved variables and unsupported auth types without failing; empty or invalid URLs are build errors.
  - `Masker` hides secret values and sensitive headers in heads, bodies and stored records.

## 0.3.0

- New `postit_storage` package implementing ADR-007 (FR-WS-001, 002, 004, 007, 008; part of FR-HIS-001..003, FR-VAR-002).
  - Workspace database (`.postit`): collection tree with ordering, move (cycle-safe), duplicate and cascading delete; requests with unknown-key preservation; environments, globals, collection/folder variables (secret values never stored); per-request revisions with cap and restore; auth inheritance chain; `VACUUM INTO` export.
  - Safety: application id check, newer-schema rejection without modification, pre-migration backup, exclusive single-writer lock, re-entrant transactions with full rollback.
  - Local database: history with search, body cap, retention; current variable values; recent workspaces.
- `Ulid` generator in `postit_core`.
- Built on `sqlite3` directly rather than drift (see architecture.md §3.3).

## 0.2.0

- `postit_core` domain models: `KeyValue`, `Auth` (inherit, none, API key, bearer, basic, raw passthrough), `RequestBody` (raw languages, urlencoded, form, binary), `HttpRequestItem`, `RequestSettings`, `Scripts`, `Environment`.
- URL helpers for query params and `:path` variables that never decode or rewrite user text (FR-HTTP-003, FR-HTTP-004).
- Auth inheritance resolution (FR-COL-002). Unknown keys and auth types round-trip.

## 0.1.0

- Monorepo scaffold: `postit_core` (variable resolver), `postit_http` (HTTP/1.1 engine), `test_server`, `postit_app` (adaptive shell).
- Spec kit with SQLite workspace storage (ADR-007, proposed).
