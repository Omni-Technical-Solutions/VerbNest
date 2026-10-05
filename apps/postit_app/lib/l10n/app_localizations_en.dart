// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navCollections => 'Collections';

  @override
  String get navHistory => 'History';

  @override
  String get navEnvironments => 'Environments';

  @override
  String get navSettings => 'Settings';

  @override
  String get selectOrCreateRequest => 'Select or create a request';

  @override
  String get paletteHint => 'Type a command or request name';

  @override
  String get paletteNothing => 'Nothing matches';

  @override
  String get cmdNewRequest => 'New request';

  @override
  String get cmdSend => 'Send request';

  @override
  String get cmdSearch => 'Search workspace…';

  @override
  String get cmdToggleSidebar => 'Toggle sidebar';

  @override
  String get cmdCloseTab => 'Close tab';

  @override
  String cmdGoTo(String place) {
    return 'Go to $place';
  }

  @override
  String get closeTab => 'Close tab';

  @override
  String get language => 'Language';

  @override
  String get systemDefault => 'System default';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get secretsProtected => 'Secrets are kept in the system secret store';

  @override
  String get secretsUnprotected =>
      'Secrets are stored unencrypted on this device';

  @override
  String get secretsUnavailableHint =>
      'The system secret store is not available (on Linux, install and unlock a keyring service).';

  @override
  String get defaultTimeout => 'Default timeout (seconds)';

  @override
  String get verifyTls => 'Verify TLS certificates';

  @override
  String get verifyTlsHint => 'Turning this off is unsafe on public networks';

  @override
  String get warnUnresolved => 'Warn before sending with undefined variables';

  @override
  String get followRedirects => 'Follow redirects';

  @override
  String get appearanceSection => 'Appearance (this device)';

  @override
  String get historySection => 'History (this device)';

  @override
  String get historyBodies => 'Keep request and response bodies';

  @override
  String get historyBodiesHint => 'Off stores only URLs, headers and status';

  @override
  String get historyDays => 'Delete history older than (days, 0 = never)';

  @override
  String get historyMax => 'Keep at most this many entries';

  @override
  String get close => 'Close';

  @override
  String get rtConnect => 'Connect';

  @override
  String get rtConnecting => 'Connecting…';

  @override
  String get rtDisconnect => 'Disconnect';

  @override
  String get rtClear => 'Clear';

  @override
  String get rtMessageHint => 'Message';

  @override
  String get rtSendTooltip => 'Send message';

  @override
  String get mockTitle => 'Mock server';

  @override
  String get mockEmpty =>
      'No request here has a saved example. Save a response as an example first.';

  @override
  String get mockPort => 'Port';

  @override
  String get mockStart => 'Start';

  @override
  String get mockStop => 'Stop';

  @override
  String mockServing(String url) {
    return 'Serving on $url';
  }

  @override
  String get mockPortInvalid => 'Port must be 0-65535';

  @override
  String mockListenFailed(int port, String error) {
    return 'Cannot listen on port $port: $error';
  }

  @override
  String mockRouteSubtitle(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count examples',
      one: '1 example',
    );
    return '$name, $_temp0';
  }

  @override
  String get mockHeaderHint =>
      'Send an X-PostIt-Example header to pick an example by name.';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get nameLabel => 'Name';

  @override
  String get noEnvironment => 'No environment';

  @override
  String get variablesInEffect => 'Variables in effect';

  @override
  String get noVariablesDefined => 'No variables are defined.';

  @override
  String get revisionsTitle => 'Earlier versions';

  @override
  String get revisionsNone => 'No earlier versions yet';

  @override
  String get restore => 'Restore';

  @override
  String get kvChooseFile => 'Choose file…';

  @override
  String get kvTableEdit => 'Table edit';

  @override
  String get kvBulkEdit => 'Bulk edit';

  @override
  String get kvBulkHint => 'key: value (one per line, // to disable)';

  @override
  String get kvKey => 'Key';

  @override
  String get kvValue => 'Value';

  @override
  String get kvSwitchToText => 'File (switch to text)';

  @override
  String get kvSwitchToFile => 'Text (switch to file)';

  @override
  String get remove => 'Remove';

  @override
  String get add => 'Add';

  @override
  String get asStatusCode => 'Status code';

  @override
  String get asHeader => 'Header';

  @override
  String get asJsonPath => 'JSON path';

  @override
  String get asResponseTime => 'Response time (ms)';

  @override
  String get asBody => 'Body';

  @override
  String get asSchema => 'JSON schema';

  @override
  String get asAdd => 'Add assertion';

  @override
  String get tokenNeverExpires => 'does not expire';

  @override
  String get tokenExpired => 'expired';

  @override
  String tokenExpiresSeconds(int n) {
    return 'expires in $n s';
  }

  @override
  String tokenExpiresMinutes(int n) {
    return 'expires in $n min';
  }

  @override
  String tokenExpiresHours(int n) {
    return 'expires in $n h';
  }

  @override
  String get tokensTitle => 'OAuth 2.0 tokens';

  @override
  String get tokensEmpty =>
      'No tokens yet. They are kept in memory until you quit the app.';

  @override
  String get tokenNoClientId => 'no client id';

  @override
  String get tokenHasRefresh => 'has refresh token';

  @override
  String get tokensDeleteAll => 'Delete all';

  @override
  String runTitle(String name) {
    return 'Run \"$name\"';
  }

  @override
  String get runNoRows => 'The file has no rows';

  @override
  String get runReportSaved => 'Report saved';

  @override
  String get runNoRequests => 'No requests to run here';

  @override
  String get runIterations => 'Iterations';

  @override
  String get runDelay => 'Delay (ms)';

  @override
  String get runStopOnFailure => 'Stop on first failure';

  @override
  String get runDataFile => 'Data file…';

  @override
  String runDataFileRows(String name, int count) {
    return '$name ($count rows)';
  }

  @override
  String get runRemoveData => 'Remove data file';

  @override
  String get runStart => 'Run';

  @override
  String runProgress(int iteration, int total) {
    return 'Iteration $iteration of $total';
  }

  @override
  String get runResultsHere => 'Results appear here';

  @override
  String get runSkipped => 'Skipped';

  @override
  String runEntrySummary(String status, int ms, int passed, int failed) {
    return '$status · $ms ms · $passed passed, $failed failed';
  }

  @override
  String runIterationSuffix(int n) {
    return 'iteration $n';
  }

  @override
  String runSummary(int requests, int passed, int failed, int errors) {
    return '$requests requests · $passed passed · $failed failed · $errors errors';
  }

  @override
  String get runStoppedEarly => 'stopped early';

  @override
  String get runStop => 'Stop';

  @override
  String get histSearchHint => 'Search method, URL or status';

  @override
  String get histConsole => 'Network console';

  @override
  String get histClear => 'Clear history';

  @override
  String get histEmpty => 'Requests you send appear here';

  @override
  String histNoMatch(String query) {
    return 'Nothing matches \"$query\"';
  }

  @override
  String get histClearTitle => 'Clear history?';

  @override
  String get histClearMessage =>
      'All stored requests and responses on this device are removed.';

  @override
  String get histError => 'ERR';

  @override
  String get histOpenRequest => 'Open request';

  @override
  String histSavedMasked(String placeholder) {
    return 'Saved to \"Imported\". Secrets were masked ($placeholder); enter them again.';
  }

  @override
  String get histSaved => 'Saved to \"Imported\"';

  @override
  String get histSaveAsNew => 'Save as new request';

  @override
  String get histTabRequest => 'Request';

  @override
  String get histTabResponse => 'Response';

  @override
  String get histNoBody => 'No response body stored';

  @override
  String get histTruncated => '[truncated when stored]';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get envNew => 'New environment';

  @override
  String get envCreate => 'Create';

  @override
  String envExists(String name) {
    return 'An environment named \"$name\" already exists';
  }

  @override
  String get rename => 'Rename';

  @override
  String envDeleteTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get cannotUndo => 'This cannot be undone.';

  @override
  String get envGlobals => 'Globals';

  @override
  String get envVarName => 'Name';

  @override
  String get envSecretValue => 'Secret value';

  @override
  String get envInitialValue => 'Initial value';

  @override
  String get envHide => 'Hide';

  @override
  String get envShow => 'Show';

  @override
  String get envCurrentValue => 'Current value (this device)';

  @override
  String get envSecret => 'Secret';

  @override
  String get envMarkSecret => 'Mark as secret';

  @override
  String envDuplicates(String names) {
    return 'Duplicate names: $names. The last one is used.';
  }

  @override
  String get envAddVariable => 'Add variable';

  @override
  String get consoleTitle => 'Network console';

  @override
  String get clear => 'Clear';

  @override
  String get consoleEmpty => 'Nothing sent in this session yet';

  @override
  String get consoleSent => 'Sent';

  @override
  String get consoleError => 'Error';

  @override
  String get consoleReceived => 'Received';

  @override
  String get cookiesTitle => 'Cookies';

  @override
  String get cookiesEmpty => 'No cookies saved yet';

  @override
  String cookiesDeleteDomain(String domain) {
    return 'Delete all for $domain';
  }

  @override
  String cookiePath(String path) {
    return 'path $path';
  }

  @override
  String get cookieSession => 'session';

  @override
  String cookieExpires(String when) {
    return 'expires $when';
  }

  @override
  String get deleteAll => 'Delete all';

  @override
  String get codeTitle => 'Generate code';

  @override
  String get codeFillVariables => 'Fill in variable values';

  @override
  String get codeSecretsWarning => 'Secret values will appear in the code';

  @override
  String get codeCopied => 'Code copied';

  @override
  String get copy => 'Copy';

  @override
  String get wsTitle => 'Workspaces';

  @override
  String get wsInMemory => 'In memory';

  @override
  String get wsRename => 'Rename';

  @override
  String get wsRenameTitle => 'Rename workspace';

  @override
  String get wsImport => 'Import…';

  @override
  String get wsImportSnapshot => 'Import snapshot…';

  @override
  String get wsExportSnapshot => 'Export snapshot…';

  @override
  String get wsExport => 'Export…';

  @override
  String get wsNewTitle => 'New workspace';

  @override
  String get wsCreate => 'Create';

  @override
  String get wsNew => 'New';

  @override
  String wsSnapshotMerged(int requests, int environments) {
    return 'Snapshot merged: $requests requests, $environments environments';
  }

  @override
  String wsSnapshotKept(int count, String first) {
    return ', $count kept as they were ($first)';
  }

  @override
  String settingsTextSize(int percent) {
    return 'Text size $percent%';
  }

  @override
  String settingsCodeFontSize(int size) {
    return 'Code font size $size';
  }

  @override
  String get scriptPre => 'Pre-request';

  @override
  String get scriptPreSet => 'Pre-request •';

  @override
  String get scriptPost => 'Post-response';

  @override
  String get scriptPostSet => 'Post-response •';

  @override
  String get scriptHelp =>
      'pm.variables, pm.environment, pm.collectionVariables, pm.globals, pm.request, pm.response, pm.test, pm.expect and console are available. Scripts stop after 5 s; pm.sendRequest is not supported yet.';

  @override
  String get langEnglish => 'English';

  @override
  String get langArabic => 'العربية';

  @override
  String get exFavRemove => 'Remove from favourites';

  @override
  String get exFavAdd => 'Add to favourites';

  @override
  String get exTitle => 'Examples';

  @override
  String get exEmpty => 'No examples yet';

  @override
  String get exSave => 'Save current response';

  @override
  String get exClose => 'Close';

  @override
  String get exSelect => 'Select an example';

  @override
  String get exDelete => 'Delete example';

  @override
  String get nsTitle => 'Network (this device)';

  @override
  String nsCookies(int count) {
    return 'Cookies ($count)';
  }

  @override
  String get nsCookiesHint => 'Saved from responses and sent automatically';

  @override
  String get nsUseProxy => 'Use a proxy';

  @override
  String get nsProxyHttp => 'HTTP';

  @override
  String get nsProxySocks => 'SOCKS5';

  @override
  String get nsProxyHost => 'Proxy host';

  @override
  String get nsProxyPort => 'Proxy port';

  @override
  String get nsProxyUser => 'Proxy user name (optional)';

  @override
  String get nsProxyPassword => 'Proxy password (optional)';

  @override
  String get nsProxyBypass => 'No proxy for (comma separated hosts)';

  @override
  String get nsSystemProxy => 'Use HTTP_PROXY / HTTPS_PROXY / NO_PROXY';

  @override
  String get nsSystemProxyHint =>
      'Read from the environment when no proxy is set above. The operating system proxy settings are not read.';

  @override
  String get nsCertsTitle => 'Certificates (this device)';

  @override
  String get nsCaHint => 'Trusted certificate authority';

  @override
  String get nsRemove => 'Remove';

  @override
  String nsClientCertFor(String pattern) {
    return 'Client certificate for $pattern';
  }

  @override
  String get nsAddCa => 'Add trusted CA';

  @override
  String get nsAddClientCert => 'Add client certificate';

  @override
  String get nsClientCertTitle => 'Client certificate';

  @override
  String get nsCertHosts => 'Hosts (api.example.com, *.example.com or *)';

  @override
  String get nsChooseCert => 'Choose certificate (.pem, .p12)';

  @override
  String get nsChooseKey => 'Choose private key (.pem)';

  @override
  String get nsPassphrase => 'Passphrase (optional)';

  @override
  String get nsCancel => 'Cancel';

  @override
  String get nsAdd => 'Add';
}
