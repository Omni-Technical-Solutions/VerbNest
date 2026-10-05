import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @navCollections.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get navCollections;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navEnvironments.
  ///
  /// In en, this message translates to:
  /// **'Environments'**
  String get navEnvironments;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @selectOrCreateRequest.
  ///
  /// In en, this message translates to:
  /// **'Select or create a request'**
  String get selectOrCreateRequest;

  /// No description provided for @paletteHint.
  ///
  /// In en, this message translates to:
  /// **'Type a command or request name'**
  String get paletteHint;

  /// No description provided for @paletteNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches'**
  String get paletteNothing;

  /// No description provided for @cmdNewRequest.
  ///
  /// In en, this message translates to:
  /// **'New request'**
  String get cmdNewRequest;

  /// No description provided for @cmdSend.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get cmdSend;

  /// No description provided for @cmdSearch.
  ///
  /// In en, this message translates to:
  /// **'Search workspace…'**
  String get cmdSearch;

  /// No description provided for @cmdToggleSidebar.
  ///
  /// In en, this message translates to:
  /// **'Toggle sidebar'**
  String get cmdToggleSidebar;

  /// No description provided for @cmdCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get cmdCloseTab;

  /// No description provided for @cmdGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to {place}'**
  String cmdGoTo(String place);

  /// No description provided for @closeTab.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get closeTab;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @secretsProtected.
  ///
  /// In en, this message translates to:
  /// **'Secrets are kept in the system secret store'**
  String get secretsProtected;

  /// No description provided for @secretsUnprotected.
  ///
  /// In en, this message translates to:
  /// **'Secrets are stored unencrypted on this device'**
  String get secretsUnprotected;

  /// No description provided for @secretsUnavailableHint.
  ///
  /// In en, this message translates to:
  /// **'The system secret store is not available (on Linux, install and unlock a keyring service).'**
  String get secretsUnavailableHint;

  /// No description provided for @defaultTimeout.
  ///
  /// In en, this message translates to:
  /// **'Default timeout (seconds)'**
  String get defaultTimeout;

  /// No description provided for @verifyTls.
  ///
  /// In en, this message translates to:
  /// **'Verify TLS certificates'**
  String get verifyTls;

  /// No description provided for @verifyTlsHint.
  ///
  /// In en, this message translates to:
  /// **'Turning this off is unsafe on public networks'**
  String get verifyTlsHint;

  /// No description provided for @warnUnresolved.
  ///
  /// In en, this message translates to:
  /// **'Warn before sending with undefined variables'**
  String get warnUnresolved;

  /// No description provided for @followRedirects.
  ///
  /// In en, this message translates to:
  /// **'Follow redirects'**
  String get followRedirects;

  /// No description provided for @appearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance (this device)'**
  String get appearanceSection;

  /// No description provided for @historySection.
  ///
  /// In en, this message translates to:
  /// **'History (this device)'**
  String get historySection;

  /// No description provided for @historyBodies.
  ///
  /// In en, this message translates to:
  /// **'Keep request and response bodies'**
  String get historyBodies;

  /// No description provided for @historyBodiesHint.
  ///
  /// In en, this message translates to:
  /// **'Off stores only URLs, headers and status'**
  String get historyBodiesHint;

  /// No description provided for @historyDays.
  ///
  /// In en, this message translates to:
  /// **'Delete history older than (days, 0 = never)'**
  String get historyDays;

  /// No description provided for @historyMax.
  ///
  /// In en, this message translates to:
  /// **'Keep at most this many entries'**
  String get historyMax;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @rtConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get rtConnect;

  /// No description provided for @rtConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get rtConnecting;

  /// No description provided for @rtDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get rtDisconnect;

  /// No description provided for @rtClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get rtClear;

  /// No description provided for @rtMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get rtMessageHint;

  /// No description provided for @rtSendTooltip.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get rtSendTooltip;

  /// No description provided for @mockTitle.
  ///
  /// In en, this message translates to:
  /// **'Mock server'**
  String get mockTitle;

  /// No description provided for @mockEmpty.
  ///
  /// In en, this message translates to:
  /// **'No request here has a saved example. Save a response as an example first.'**
  String get mockEmpty;

  /// No description provided for @mockPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get mockPort;

  /// No description provided for @mockStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get mockStart;

  /// No description provided for @mockStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get mockStop;

  /// No description provided for @mockServing.
  ///
  /// In en, this message translates to:
  /// **'Serving on {url}'**
  String mockServing(String url);

  /// No description provided for @mockPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'Port must be 0-65535'**
  String get mockPortInvalid;

  /// No description provided for @mockListenFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot listen on port {port}: {error}'**
  String mockListenFailed(int port, String error);

  /// No description provided for @mockRouteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{name}, {count, plural, =1{1 example} other{{count} examples}}'**
  String mockRouteSubtitle(String name, int count);

  /// No description provided for @mockHeaderHint.
  ///
  /// In en, this message translates to:
  /// **'Send an X-PostIt-Example header to pick an example by name.'**
  String get mockHeaderHint;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @noEnvironment.
  ///
  /// In en, this message translates to:
  /// **'No environment'**
  String get noEnvironment;

  /// No description provided for @variablesInEffect.
  ///
  /// In en, this message translates to:
  /// **'Variables in effect'**
  String get variablesInEffect;

  /// No description provided for @noVariablesDefined.
  ///
  /// In en, this message translates to:
  /// **'No variables are defined.'**
  String get noVariablesDefined;

  /// No description provided for @revisionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Earlier versions'**
  String get revisionsTitle;

  /// No description provided for @revisionsNone.
  ///
  /// In en, this message translates to:
  /// **'No earlier versions yet'**
  String get revisionsNone;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @kvChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file…'**
  String get kvChooseFile;

  /// No description provided for @kvTableEdit.
  ///
  /// In en, this message translates to:
  /// **'Table edit'**
  String get kvTableEdit;

  /// No description provided for @kvBulkEdit.
  ///
  /// In en, this message translates to:
  /// **'Bulk edit'**
  String get kvBulkEdit;

  /// No description provided for @kvBulkHint.
  ///
  /// In en, this message translates to:
  /// **'key: value (one per line, // to disable)'**
  String get kvBulkHint;

  /// No description provided for @kvKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get kvKey;

  /// No description provided for @kvValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get kvValue;

  /// No description provided for @kvSwitchToText.
  ///
  /// In en, this message translates to:
  /// **'File (switch to text)'**
  String get kvSwitchToText;

  /// No description provided for @kvSwitchToFile.
  ///
  /// In en, this message translates to:
  /// **'Text (switch to file)'**
  String get kvSwitchToFile;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @asStatusCode.
  ///
  /// In en, this message translates to:
  /// **'Status code'**
  String get asStatusCode;

  /// No description provided for @asHeader.
  ///
  /// In en, this message translates to:
  /// **'Header'**
  String get asHeader;

  /// No description provided for @asJsonPath.
  ///
  /// In en, this message translates to:
  /// **'JSON path'**
  String get asJsonPath;

  /// No description provided for @asResponseTime.
  ///
  /// In en, this message translates to:
  /// **'Response time (ms)'**
  String get asResponseTime;

  /// No description provided for @asBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get asBody;

  /// No description provided for @asSchema.
  ///
  /// In en, this message translates to:
  /// **'JSON schema'**
  String get asSchema;

  /// No description provided for @asAdd.
  ///
  /// In en, this message translates to:
  /// **'Add assertion'**
  String get asAdd;

  /// No description provided for @tokenNeverExpires.
  ///
  /// In en, this message translates to:
  /// **'does not expire'**
  String get tokenNeverExpires;

  /// No description provided for @tokenExpired.
  ///
  /// In en, this message translates to:
  /// **'expired'**
  String get tokenExpired;

  /// No description provided for @tokenExpiresSeconds.
  ///
  /// In en, this message translates to:
  /// **'expires in {n} s'**
  String tokenExpiresSeconds(int n);

  /// No description provided for @tokenExpiresMinutes.
  ///
  /// In en, this message translates to:
  /// **'expires in {n} min'**
  String tokenExpiresMinutes(int n);

  /// No description provided for @tokenExpiresHours.
  ///
  /// In en, this message translates to:
  /// **'expires in {n} h'**
  String tokenExpiresHours(int n);

  /// No description provided for @tokensTitle.
  ///
  /// In en, this message translates to:
  /// **'OAuth 2.0 tokens'**
  String get tokensTitle;

  /// No description provided for @tokensEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tokens yet. They are kept in memory until you quit the app.'**
  String get tokensEmpty;

  /// No description provided for @tokenNoClientId.
  ///
  /// In en, this message translates to:
  /// **'no client id'**
  String get tokenNoClientId;

  /// No description provided for @tokenHasRefresh.
  ///
  /// In en, this message translates to:
  /// **'has refresh token'**
  String get tokenHasRefresh;

  /// No description provided for @tokensDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get tokensDeleteAll;

  /// No description provided for @runTitle.
  ///
  /// In en, this message translates to:
  /// **'Run \"{name}\"'**
  String runTitle(String name);

  /// No description provided for @runNoRows.
  ///
  /// In en, this message translates to:
  /// **'The file has no rows'**
  String get runNoRows;

  /// No description provided for @runReportSaved.
  ///
  /// In en, this message translates to:
  /// **'Report saved'**
  String get runReportSaved;

  /// No description provided for @runNoRequests.
  ///
  /// In en, this message translates to:
  /// **'No requests to run here'**
  String get runNoRequests;

  /// No description provided for @runIterations.
  ///
  /// In en, this message translates to:
  /// **'Iterations'**
  String get runIterations;

  /// No description provided for @runDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay (ms)'**
  String get runDelay;

  /// No description provided for @runStopOnFailure.
  ///
  /// In en, this message translates to:
  /// **'Stop on first failure'**
  String get runStopOnFailure;

  /// No description provided for @runDataFile.
  ///
  /// In en, this message translates to:
  /// **'Data file…'**
  String get runDataFile;

  /// No description provided for @runDataFileRows.
  ///
  /// In en, this message translates to:
  /// **'{name} ({count} rows)'**
  String runDataFileRows(String name, int count);

  /// No description provided for @runRemoveData.
  ///
  /// In en, this message translates to:
  /// **'Remove data file'**
  String get runRemoveData;

  /// No description provided for @runStart.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get runStart;

  /// No description provided for @runProgress.
  ///
  /// In en, this message translates to:
  /// **'Iteration {iteration} of {total}'**
  String runProgress(int iteration, int total);

  /// No description provided for @runResultsHere.
  ///
  /// In en, this message translates to:
  /// **'Results appear here'**
  String get runResultsHere;

  /// No description provided for @runSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get runSkipped;

  /// No description provided for @runEntrySummary.
  ///
  /// In en, this message translates to:
  /// **'{status} · {ms} ms · {passed} passed, {failed} failed'**
  String runEntrySummary(String status, int ms, int passed, int failed);

  /// No description provided for @runIterationSuffix.
  ///
  /// In en, this message translates to:
  /// **'iteration {n}'**
  String runIterationSuffix(int n);

  /// No description provided for @runSummary.
  ///
  /// In en, this message translates to:
  /// **'{requests} requests · {passed} passed · {failed} failed · {errors} errors'**
  String runSummary(int requests, int passed, int failed, int errors);

  /// No description provided for @runStoppedEarly.
  ///
  /// In en, this message translates to:
  /// **'stopped early'**
  String get runStoppedEarly;

  /// No description provided for @runStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get runStop;

  /// No description provided for @histSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search method, URL or status'**
  String get histSearchHint;

  /// No description provided for @histConsole.
  ///
  /// In en, this message translates to:
  /// **'Network console'**
  String get histConsole;

  /// No description provided for @histClear.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get histClear;

  /// No description provided for @histEmpty.
  ///
  /// In en, this message translates to:
  /// **'Requests you send appear here'**
  String get histEmpty;

  /// No description provided for @histNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{query}\"'**
  String histNoMatch(String query);

  /// No description provided for @histClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear history?'**
  String get histClearTitle;

  /// No description provided for @histClearMessage.
  ///
  /// In en, this message translates to:
  /// **'All stored requests and responses on this device are removed.'**
  String get histClearMessage;

  /// No description provided for @histError.
  ///
  /// In en, this message translates to:
  /// **'ERR'**
  String get histError;

  /// No description provided for @histOpenRequest.
  ///
  /// In en, this message translates to:
  /// **'Open request'**
  String get histOpenRequest;

  /// No description provided for @histSavedMasked.
  ///
  /// In en, this message translates to:
  /// **'Saved to \"Imported\". Secrets were masked ({placeholder}); enter them again.'**
  String histSavedMasked(String placeholder);

  /// No description provided for @histSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to \"Imported\"'**
  String get histSaved;

  /// No description provided for @histSaveAsNew.
  ///
  /// In en, this message translates to:
  /// **'Save as new request'**
  String get histSaveAsNew;

  /// No description provided for @histTabRequest.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get histTabRequest;

  /// No description provided for @histTabResponse.
  ///
  /// In en, this message translates to:
  /// **'Response'**
  String get histTabResponse;

  /// No description provided for @histNoBody.
  ///
  /// In en, this message translates to:
  /// **'No response body stored'**
  String get histNoBody;

  /// No description provided for @histTruncated.
  ///
  /// In en, this message translates to:
  /// **'[truncated when stored]'**
  String get histTruncated;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @envNew.
  ///
  /// In en, this message translates to:
  /// **'New environment'**
  String get envNew;

  /// No description provided for @envCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get envCreate;

  /// No description provided for @envExists.
  ///
  /// In en, this message translates to:
  /// **'An environment named \"{name}\" already exists'**
  String envExists(String name);

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @envDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String envDeleteTitle(String name);

  /// No description provided for @cannotUndo.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get cannotUndo;

  /// No description provided for @envGlobals.
  ///
  /// In en, this message translates to:
  /// **'Globals'**
  String get envGlobals;

  /// No description provided for @envVarName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get envVarName;

  /// No description provided for @envSecretValue.
  ///
  /// In en, this message translates to:
  /// **'Secret value'**
  String get envSecretValue;

  /// No description provided for @envInitialValue.
  ///
  /// In en, this message translates to:
  /// **'Initial value'**
  String get envInitialValue;

  /// No description provided for @envHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get envHide;

  /// No description provided for @envShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get envShow;

  /// No description provided for @envCurrentValue.
  ///
  /// In en, this message translates to:
  /// **'Current value (this device)'**
  String get envCurrentValue;

  /// No description provided for @envSecret.
  ///
  /// In en, this message translates to:
  /// **'Secret'**
  String get envSecret;

  /// No description provided for @envMarkSecret.
  ///
  /// In en, this message translates to:
  /// **'Mark as secret'**
  String get envMarkSecret;

  /// No description provided for @envDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Duplicate names: {names}. The last one is used.'**
  String envDuplicates(String names);

  /// No description provided for @envAddVariable.
  ///
  /// In en, this message translates to:
  /// **'Add variable'**
  String get envAddVariable;

  /// No description provided for @consoleTitle.
  ///
  /// In en, this message translates to:
  /// **'Network console'**
  String get consoleTitle;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @consoleEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing sent in this session yet'**
  String get consoleEmpty;

  /// No description provided for @consoleSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get consoleSent;

  /// No description provided for @consoleError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get consoleError;

  /// No description provided for @consoleReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get consoleReceived;

  /// No description provided for @cookiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Cookies'**
  String get cookiesTitle;

  /// No description provided for @cookiesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No cookies saved yet'**
  String get cookiesEmpty;

  /// No description provided for @cookiesDeleteDomain.
  ///
  /// In en, this message translates to:
  /// **'Delete all for {domain}'**
  String cookiesDeleteDomain(String domain);

  /// No description provided for @cookiePath.
  ///
  /// In en, this message translates to:
  /// **'path {path}'**
  String cookiePath(String path);

  /// No description provided for @cookieSession.
  ///
  /// In en, this message translates to:
  /// **'session'**
  String get cookieSession;

  /// No description provided for @cookieExpires.
  ///
  /// In en, this message translates to:
  /// **'expires {when}'**
  String cookieExpires(String when);

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// No description provided for @codeTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate code'**
  String get codeTitle;

  /// No description provided for @codeFillVariables.
  ///
  /// In en, this message translates to:
  /// **'Fill in variable values'**
  String get codeFillVariables;

  /// No description provided for @codeSecretsWarning.
  ///
  /// In en, this message translates to:
  /// **'Secret values will appear in the code'**
  String get codeSecretsWarning;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get codeCopied;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @wsTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get wsTitle;

  /// No description provided for @wsInMemory.
  ///
  /// In en, this message translates to:
  /// **'In memory'**
  String get wsInMemory;

  /// No description provided for @wsRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get wsRename;

  /// No description provided for @wsRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename workspace'**
  String get wsRenameTitle;

  /// No description provided for @wsImport.
  ///
  /// In en, this message translates to:
  /// **'Import…'**
  String get wsImport;

  /// No description provided for @wsImportSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Import snapshot…'**
  String get wsImportSnapshot;

  /// No description provided for @wsExportSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Export snapshot…'**
  String get wsExportSnapshot;

  /// No description provided for @wsExport.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get wsExport;

  /// No description provided for @wsNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New workspace'**
  String get wsNewTitle;

  /// No description provided for @wsCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get wsCreate;

  /// No description provided for @wsNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get wsNew;

  /// No description provided for @wsSnapshotMerged.
  ///
  /// In en, this message translates to:
  /// **'Snapshot merged: {requests} requests, {environments} environments'**
  String wsSnapshotMerged(int requests, int environments);

  /// No description provided for @wsSnapshotKept.
  ///
  /// In en, this message translates to:
  /// **', {count} kept as they were ({first})'**
  String wsSnapshotKept(int count, String first);

  /// No description provided for @settingsTextSize.
  ///
  /// In en, this message translates to:
  /// **'Text size {percent}%'**
  String settingsTextSize(int percent);

  /// No description provided for @settingsCodeFontSize.
  ///
  /// In en, this message translates to:
  /// **'Code font size {size}'**
  String settingsCodeFontSize(int size);

  /// No description provided for @scriptPre.
  ///
  /// In en, this message translates to:
  /// **'Pre-request'**
  String get scriptPre;

  /// No description provided for @scriptPreSet.
  ///
  /// In en, this message translates to:
  /// **'Pre-request •'**
  String get scriptPreSet;

  /// No description provided for @scriptPost.
  ///
  /// In en, this message translates to:
  /// **'Post-response'**
  String get scriptPost;

  /// No description provided for @scriptPostSet.
  ///
  /// In en, this message translates to:
  /// **'Post-response •'**
  String get scriptPostSet;

  /// No description provided for @scriptHelp.
  ///
  /// In en, this message translates to:
  /// **'pm.variables, pm.environment, pm.collectionVariables, pm.globals, pm.request, pm.response, pm.test, pm.expect and console are available. Scripts stop after 5 s; pm.sendRequest is not supported yet.'**
  String get scriptHelp;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get langArabic;

  /// No description provided for @exFavRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get exFavRemove;

  /// No description provided for @exFavAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get exFavAdd;

  /// No description provided for @exTitle.
  ///
  /// In en, this message translates to:
  /// **'Examples'**
  String get exTitle;

  /// No description provided for @exEmpty.
  ///
  /// In en, this message translates to:
  /// **'No examples yet'**
  String get exEmpty;

  /// No description provided for @exSave.
  ///
  /// In en, this message translates to:
  /// **'Save current response'**
  String get exSave;

  /// No description provided for @exClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get exClose;

  /// No description provided for @exSelect.
  ///
  /// In en, this message translates to:
  /// **'Select an example'**
  String get exSelect;

  /// No description provided for @exDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete example'**
  String get exDelete;

  /// No description provided for @nsTitle.
  ///
  /// In en, this message translates to:
  /// **'Network (this device)'**
  String get nsTitle;

  /// No description provided for @nsCookies.
  ///
  /// In en, this message translates to:
  /// **'Cookies ({count})'**
  String nsCookies(int count);

  /// No description provided for @nsCookiesHint.
  ///
  /// In en, this message translates to:
  /// **'Saved from responses and sent automatically'**
  String get nsCookiesHint;

  /// No description provided for @nsUseProxy.
  ///
  /// In en, this message translates to:
  /// **'Use a proxy'**
  String get nsUseProxy;

  /// No description provided for @nsProxyHttp.
  ///
  /// In en, this message translates to:
  /// **'HTTP'**
  String get nsProxyHttp;

  /// No description provided for @nsProxySocks.
  ///
  /// In en, this message translates to:
  /// **'SOCKS5'**
  String get nsProxySocks;

  /// No description provided for @nsProxyHost.
  ///
  /// In en, this message translates to:
  /// **'Proxy host'**
  String get nsProxyHost;

  /// No description provided for @nsProxyPort.
  ///
  /// In en, this message translates to:
  /// **'Proxy port'**
  String get nsProxyPort;

  /// No description provided for @nsProxyUser.
  ///
  /// In en, this message translates to:
  /// **'Proxy user name (optional)'**
  String get nsProxyUser;

  /// No description provided for @nsProxyPassword.
  ///
  /// In en, this message translates to:
  /// **'Proxy password (optional)'**
  String get nsProxyPassword;

  /// No description provided for @nsProxyBypass.
  ///
  /// In en, this message translates to:
  /// **'No proxy for (comma separated hosts)'**
  String get nsProxyBypass;

  /// No description provided for @nsSystemProxy.
  ///
  /// In en, this message translates to:
  /// **'Use HTTP_PROXY / HTTPS_PROXY / NO_PROXY'**
  String get nsSystemProxy;

  /// No description provided for @nsSystemProxyHint.
  ///
  /// In en, this message translates to:
  /// **'Read from the environment when no proxy is set above. The operating system proxy settings are not read.'**
  String get nsSystemProxyHint;

  /// No description provided for @nsCertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Certificates (this device)'**
  String get nsCertsTitle;

  /// No description provided for @nsCaHint.
  ///
  /// In en, this message translates to:
  /// **'Trusted certificate authority'**
  String get nsCaHint;

  /// No description provided for @nsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get nsRemove;

  /// No description provided for @nsClientCertFor.
  ///
  /// In en, this message translates to:
  /// **'Client certificate for {pattern}'**
  String nsClientCertFor(String pattern);

  /// No description provided for @nsAddCa.
  ///
  /// In en, this message translates to:
  /// **'Add trusted CA'**
  String get nsAddCa;

  /// No description provided for @nsAddClientCert.
  ///
  /// In en, this message translates to:
  /// **'Add client certificate'**
  String get nsAddClientCert;

  /// No description provided for @nsClientCertTitle.
  ///
  /// In en, this message translates to:
  /// **'Client certificate'**
  String get nsClientCertTitle;

  /// No description provided for @nsCertHosts.
  ///
  /// In en, this message translates to:
  /// **'Hosts (api.example.com, *.example.com or *)'**
  String get nsCertHosts;

  /// No description provided for @nsChooseCert.
  ///
  /// In en, this message translates to:
  /// **'Choose certificate (.pem, .p12)'**
  String get nsChooseCert;

  /// No description provided for @nsChooseKey.
  ///
  /// In en, this message translates to:
  /// **'Choose private key (.pem)'**
  String get nsChooseKey;

  /// No description provided for @nsPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase (optional)'**
  String get nsPassphrase;

  /// No description provided for @nsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get nsCancel;

  /// No description provided for @nsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get nsAdd;

  /// No description provided for @authInherit.
  ///
  /// In en, this message translates to:
  /// **'Uses the auth of the enclosing folder or collection.'**
  String get authInherit;

  /// No description provided for @authToken.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get authToken;

  /// No description provided for @authUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsername;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get authKey;

  /// No description provided for @authValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get authValue;

  /// No description provided for @authHeader.
  ///
  /// In en, this message translates to:
  /// **'Header'**
  String get authHeader;

  /// No description provided for @authQuery.
  ///
  /// In en, this message translates to:
  /// **'Query'**
  String get authQuery;

  /// No description provided for @authDigestHint.
  ///
  /// In en, this message translates to:
  /// **'The request is sent once without credentials; the server challenge is answered automatically.'**
  String get authDigestHint;

  /// No description provided for @authAccessKey.
  ///
  /// In en, this message translates to:
  /// **'Access key'**
  String get authAccessKey;

  /// No description provided for @authSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Secret key'**
  String get authSecretKey;

  /// No description provided for @authRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get authRegion;

  /// No description provided for @authService.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get authService;

  /// No description provided for @authSessionToken.
  ///
  /// In en, this message translates to:
  /// **'Session token'**
  String get authSessionToken;

  /// No description provided for @authNone.
  ///
  /// In en, this message translates to:
  /// **'No authorization is added.'**
  String get authNone;

  /// No description provided for @authRaw.
  ///
  /// In en, this message translates to:
  /// **'Auth type \"{type}\" is kept but not editable yet.'**
  String authRaw(String type);

  /// No description provided for @authSecret.
  ///
  /// In en, this message translates to:
  /// **'Secret'**
  String get authSecret;

  /// No description provided for @authPayload.
  ///
  /// In en, this message translates to:
  /// **'Payload (JSON)'**
  String get authPayload;

  /// No description provided for @authHeaderPrefix.
  ///
  /// In en, this message translates to:
  /// **'Header prefix'**
  String get authHeaderPrefix;

  /// No description provided for @authJwtHint.
  ///
  /// In en, this message translates to:
  /// **'A token is signed for each send; iat is added if missing.'**
  String get authJwtHint;

  /// No description provided for @oauthClientCredentials.
  ///
  /// In en, this message translates to:
  /// **'Client credentials'**
  String get oauthClientCredentials;

  /// No description provided for @oauthPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get oauthPassword;

  /// No description provided for @oauthAuthCode.
  ///
  /// In en, this message translates to:
  /// **'Authorization code (browser)'**
  String get oauthAuthCode;

  /// No description provided for @oauthImplicit.
  ///
  /// In en, this message translates to:
  /// **'Implicit (browser)'**
  String get oauthImplicit;

  /// No description provided for @oauthAuthUrl.
  ///
  /// In en, this message translates to:
  /// **'Auth URL'**
  String get oauthAuthUrl;

  /// No description provided for @oauthTokenUrl.
  ///
  /// In en, this message translates to:
  /// **'Token URL'**
  String get oauthTokenUrl;

  /// No description provided for @oauthClientId.
  ///
  /// In en, this message translates to:
  /// **'Client ID'**
  String get oauthClientId;

  /// No description provided for @oauthClientSecret.
  ///
  /// In en, this message translates to:
  /// **'Client secret'**
  String get oauthClientSecret;

  /// No description provided for @oauthScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get oauthScope;

  /// No description provided for @oauthPkce.
  ///
  /// In en, this message translates to:
  /// **'Use PKCE'**
  String get oauthPkce;

  /// No description provided for @oauthBrowserHint.
  ///
  /// In en, this message translates to:
  /// **'Sending opens your browser to sign in. The redirect URL is http://127.0.0.1:<port>/callback with a random port; if your provider needs a fixed redirect URL, register the loopback address with a wildcard port.'**
  String get oauthBrowserHint;

  /// No description provided for @oauthTokens.
  ///
  /// In en, this message translates to:
  /// **'Tokens…'**
  String get oauthTokens;

  /// No description provided for @oauthBodyCreds.
  ///
  /// In en, this message translates to:
  /// **'Send client credentials in the body'**
  String get oauthBodyCreds;

  /// No description provided for @gqlLoaded.
  ///
  /// In en, this message translates to:
  /// **'Schema loaded: {count} types'**
  String gqlLoaded(int count);

  /// No description provided for @gqlLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the schema: {message}'**
  String gqlLoadFailed(String message);

  /// No description provided for @gqlImported.
  ///
  /// In en, this message translates to:
  /// **'Schema imported: {count} types'**
  String gqlImported(int count);

  /// No description provided for @gqlReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the schema: {message}'**
  String gqlReadFailed(String message);

  /// No description provided for @gqlFetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch schema'**
  String get gqlFetch;

  /// No description provided for @gqlImportSdl.
  ///
  /// In en, this message translates to:
  /// **'Import SDL…'**
  String get gqlImportSdl;

  /// No description provided for @gqlExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get gqlExplore;

  /// No description provided for @gqlNoSchema.
  ///
  /// In en, this message translates to:
  /// **'No schema loaded'**
  String get gqlNoSchema;

  /// No description provided for @gqlTypeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} types'**
  String gqlTypeCount(int count);

  /// No description provided for @gqlOperation.
  ///
  /// In en, this message translates to:
  /// **'Operation'**
  String get gqlOperation;

  /// No description provided for @gqlQuery.
  ///
  /// In en, this message translates to:
  /// **'Query'**
  String get gqlQuery;

  /// No description provided for @gqlVariables.
  ///
  /// In en, this message translates to:
  /// **'Variables (JSON)'**
  String get gqlVariables;

  /// No description provided for @gqlSdlTitle.
  ///
  /// In en, this message translates to:
  /// **'Import schema (SDL)'**
  String get gqlSdlTitle;

  /// No description provided for @gqlChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose a .graphql file…'**
  String get gqlChooseFile;

  /// No description provided for @gqlCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get gqlCancel;

  /// No description provided for @gqlImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get gqlImport;

  /// No description provided for @gqlSchema.
  ///
  /// In en, this message translates to:
  /// **'Schema'**
  String get gqlSchema;

  /// No description provided for @gqlFindType.
  ///
  /// In en, this message translates to:
  /// **'Find a type'**
  String get gqlFindType;

  /// No description provided for @gqlImplements.
  ///
  /// In en, this message translates to:
  /// **'implements {interfaces}'**
  String gqlImplements(String interfaces);

  /// No description provided for @sbFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get sbFilter;

  /// No description provided for @sbWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get sbWorkspaces;

  /// No description provided for @sbShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get sbShowAll;

  /// No description provided for @sbShowFav.
  ///
  /// In en, this message translates to:
  /// **'Show favourites only'**
  String get sbShowFav;

  /// No description provided for @sbSearch.
  ///
  /// In en, this message translates to:
  /// **'Search workspace'**
  String get sbSearch;

  /// No description provided for @sbImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get sbImport;

  /// No description provided for @sbNewCollection.
  ///
  /// In en, this message translates to:
  /// **'New collection'**
  String get sbNewCollection;

  /// No description provided for @sbNoFav.
  ///
  /// In en, this message translates to:
  /// **'No favourites yet.\nStar a request to pin it here.'**
  String get sbNoFav;

  /// No description provided for @sbNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{filter}\"'**
  String sbNoMatch(String filter);

  /// No description provided for @sbNoCollections.
  ///
  /// In en, this message translates to:
  /// **'No collections yet.\nCreate one to get started.'**
  String get sbNoCollections;

  /// No description provided for @sbActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get sbActions;

  /// No description provided for @sbNewRequest.
  ///
  /// In en, this message translates to:
  /// **'New request'**
  String get sbNewRequest;

  /// No description provided for @sbNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get sbNewFolder;

  /// No description provided for @sbRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get sbRename;

  /// No description provided for @sbRun.
  ///
  /// In en, this message translates to:
  /// **'Run…'**
  String get sbRun;

  /// No description provided for @sbSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get sbSettings;

  /// No description provided for @sbDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get sbDuplicate;

  /// No description provided for @sbMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get sbMoveUp;

  /// No description provided for @sbMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get sbMoveDown;

  /// No description provided for @sbVersions.
  ///
  /// In en, this message translates to:
  /// **'Earlier versions…'**
  String get sbVersions;

  /// No description provided for @sbCopyCurl.
  ///
  /// In en, this message translates to:
  /// **'Copy as cURL'**
  String get sbCopyCurl;

  /// No description provided for @sbFavRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get sbFavRemove;

  /// No description provided for @sbFavAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get sbFavAdd;

  /// No description provided for @sbGenerateCode.
  ///
  /// In en, this message translates to:
  /// **'Generate code…'**
  String get sbGenerateCode;

  /// No description provided for @sbCopyPostman.
  ///
  /// In en, this message translates to:
  /// **'Copy as Postman JSON'**
  String get sbCopyPostman;

  /// No description provided for @sbDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get sbDelete;

  /// No description provided for @sbCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get sbCreate;

  /// No description provided for @sbCurlCopied.
  ///
  /// In en, this message translates to:
  /// **'cURL command copied'**
  String get sbCurlCopied;

  /// No description provided for @sbPostmanCopied.
  ///
  /// In en, this message translates to:
  /// **'Postman collection copied'**
  String get sbPostmanCopied;

  /// No description provided for @sbDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String sbDeleteTitle(String name);

  /// No description provided for @sbDeleteFolderMsg.
  ///
  /// In en, this message translates to:
  /// **'This also deletes everything inside it.'**
  String get sbDeleteFolderMsg;

  /// No description provided for @sbDeleteMsg.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get sbDeleteMsg;

  /// No description provided for @sbImportNotes.
  ///
  /// In en, this message translates to:
  /// **' ({count} notes: {first})'**
  String sbImportNotes(int count, String first);

  /// No description provided for @sbImportHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a cURL command, a Postman collection or environment, an OpenAPI/Swagger file (JSON or YAML) or a HAR capture'**
  String get sbImportHint;

  /// No description provided for @sbCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get sbCancel;

  /// No description provided for @rvOnWire.
  ///
  /// In en, this message translates to:
  /// **'on the wire'**
  String get rvOnWire;

  /// No description provided for @rvSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get rvSave;

  /// No description provided for @rvShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get rvShare;

  /// No description provided for @rvEmpty.
  ///
  /// In en, this message translates to:
  /// **'Send the request to see a response'**
  String get rvEmpty;

  /// No description provided for @rvTabBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get rvTabBody;

  /// No description provided for @rvTabCookies.
  ///
  /// In en, this message translates to:
  /// **'Cookies'**
  String get rvTabCookies;

  /// No description provided for @rvTabCookiesN.
  ///
  /// In en, this message translates to:
  /// **'Cookies ({count})'**
  String rvTabCookiesN(int count);

  /// No description provided for @rvTabHeaders.
  ///
  /// In en, this message translates to:
  /// **'Headers'**
  String get rvTabHeaders;

  /// No description provided for @rvTabSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get rvTabSent;

  /// No description provided for @rvTabTests.
  ///
  /// In en, this message translates to:
  /// **'Tests'**
  String get rvTabTests;

  /// No description provided for @rvTabTestsN.
  ///
  /// In en, this message translates to:
  /// **'Tests ({passed}/{counted})'**
  String rvTabTestsN(int passed, int counted);

  /// No description provided for @rvTiming.
  ///
  /// In en, this message translates to:
  /// **'Timing'**
  String get rvTiming;

  /// No description provided for @rvTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get rvTotal;

  /// No description provided for @rvDns.
  ///
  /// In en, this message translates to:
  /// **'DNS lookup'**
  String get rvDns;

  /// No description provided for @rvTcp.
  ///
  /// In en, this message translates to:
  /// **'TCP connect'**
  String get rvTcp;

  /// No description provided for @rvTlsHandshake.
  ///
  /// In en, this message translates to:
  /// **'TLS handshake'**
  String get rvTlsHandshake;

  /// No description provided for @rvTtfb.
  ///
  /// In en, this message translates to:
  /// **'Waiting (TTFB)'**
  String get rvTtfb;

  /// No description provided for @rvDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get rvDownload;

  /// No description provided for @rvOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get rvOther;

  /// No description provided for @rvClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get rvClose;

  /// No description provided for @rvTlsTitle.
  ///
  /// In en, this message translates to:
  /// **'TLS connection'**
  String get rvTlsTitle;

  /// No description provided for @rvTlsSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject: {value}'**
  String rvTlsSubject(String value);

  /// No description provided for @rvTlsIssuer.
  ///
  /// In en, this message translates to:
  /// **'Issuer: {value}'**
  String rvTlsIssuer(String value);

  /// No description provided for @rvTlsValid.
  ///
  /// In en, this message translates to:
  /// **'Valid: {from} to {to}'**
  String rvTlsValid(String from, String to);

  /// No description provided for @rvTlsProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol: {value}'**
  String rvTlsProtocol(String value);

  /// No description provided for @rvTlsClientCert.
  ///
  /// In en, this message translates to:
  /// **'Client certificate sent: {answer}'**
  String rvTlsClientCert(String answer);

  /// No description provided for @rvYes.
  ///
  /// In en, this message translates to:
  /// **'yes'**
  String get rvYes;

  /// No description provided for @rvNo.
  ///
  /// In en, this message translates to:
  /// **'no'**
  String get rvNo;

  /// No description provided for @rvNoTests.
  ///
  /// In en, this message translates to:
  /// **'No tests ran. Add pm.test() to a post-response script.'**
  String get rvNoTests;

  /// No description provided for @rvScriptError.
  ///
  /// In en, this message translates to:
  /// **'Script error'**
  String get rvScriptError;

  /// No description provided for @rvConsole.
  ///
  /// In en, this message translates to:
  /// **'Console'**
  String get rvConsole;

  /// No description provided for @rvCopyValue.
  ///
  /// In en, this message translates to:
  /// **'Copy value'**
  String get rvCopyValue;

  /// No description provided for @rvHeaderCopied.
  ///
  /// In en, this message translates to:
  /// **'{name} copied'**
  String rvHeaderCopied(String name);

  /// No description provided for @rvPretty.
  ///
  /// In en, this message translates to:
  /// **'Pretty'**
  String get rvPretty;

  /// No description provided for @rvRaw.
  ///
  /// In en, this message translates to:
  /// **'Raw'**
  String get rvRaw;

  /// No description provided for @rvHex.
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get rvHex;

  /// No description provided for @rvPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get rvPreview;

  /// No description provided for @rvSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get rvSearch;

  /// No description provided for @rvCopyBody.
  ///
  /// In en, this message translates to:
  /// **'Copy body'**
  String get rvCopyBody;

  /// No description provided for @rvBodyCopied.
  ///
  /// In en, this message translates to:
  /// **'Body copied'**
  String get rvBodyCopied;

  /// No description provided for @rvFilterJson.
  ///
  /// In en, this message translates to:
  /// **'Filter with JSONPath, e.g. \$.items[*].id'**
  String get rvFilterJson;

  /// No description provided for @rvFilterXml.
  ///
  /// In en, this message translates to:
  /// **'Filter with XPath, e.g. //item/@id'**
  String get rvFilterXml;

  /// No description provided for @rvImageError.
  ///
  /// In en, this message translates to:
  /// **'This image cannot be displayed'**
  String get rvImageError;

  /// No description provided for @rvNoCookies.
  ///
  /// In en, this message translates to:
  /// **'This response set no cookies'**
  String get rvNoCookies;

  /// No description provided for @rvTls.
  ///
  /// In en, this message translates to:
  /// **'TLS'**
  String get rvTls;

  /// No description provided for @rvHttpVersion.
  ///
  /// In en, this message translates to:
  /// **'HTTP/{version}'**
  String rvHttpVersion(String version);

  /// No description provided for @reExamples.
  ///
  /// In en, this message translates to:
  /// **'Examples'**
  String get reExamples;

  /// No description provided for @reUndefined.
  ///
  /// In en, this message translates to:
  /// **'Undefined variables: {names}'**
  String reUndefined(String names);

  /// No description provided for @reResponseSaved.
  ///
  /// In en, this message translates to:
  /// **'Response saved'**
  String get reResponseSaved;

  /// No description provided for @reNotDefined.
  ///
  /// In en, this message translates to:
  /// **'Not defined: {names}'**
  String reNotDefined(String names);

  /// No description provided for @reSendAnyway.
  ///
  /// In en, this message translates to:
  /// **'Send anyway'**
  String get reSendAnyway;

  /// No description provided for @reDontWarn.
  ///
  /// In en, this message translates to:
  /// **'Don\'t warn again'**
  String get reDontWarn;

  /// No description provided for @reCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get reCancel;

  /// No description provided for @reCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get reCustom;

  /// No description provided for @reCustomMethod.
  ///
  /// In en, this message translates to:
  /// **'Custom method'**
  String get reCustomMethod;

  /// No description provided for @reSet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get reSet;

  /// No description provided for @reLiveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open WebSocket, SSE or GraphQL subscription'**
  String get reLiveTooltip;

  /// No description provided for @reLiveWs.
  ///
  /// In en, this message translates to:
  /// **'WebSocket'**
  String get reLiveWs;

  /// No description provided for @reLiveSseTitle.
  ///
  /// In en, this message translates to:
  /// **'Server-sent events'**
  String get reLiveSseTitle;

  /// No description provided for @reLiveSub.
  ///
  /// In en, this message translates to:
  /// **'GraphQL subscription'**
  String get reLiveSub;

  /// No description provided for @reLiveSse.
  ///
  /// In en, this message translates to:
  /// **'SSE stream'**
  String get reLiveSse;

  /// No description provided for @reSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get reSend;

  /// No description provided for @reTabParams.
  ///
  /// In en, this message translates to:
  /// **'Params'**
  String get reTabParams;

  /// No description provided for @reTabHeaders.
  ///
  /// In en, this message translates to:
  /// **'Headers'**
  String get reTabHeaders;

  /// No description provided for @reTabAuth.
  ///
  /// In en, this message translates to:
  /// **'Auth'**
  String get reTabAuth;

  /// No description provided for @reTabBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get reTabBody;

  /// No description provided for @reTabScripts.
  ///
  /// In en, this message translates to:
  /// **'Scripts'**
  String get reTabScripts;

  /// No description provided for @reTabAssertions.
  ///
  /// In en, this message translates to:
  /// **'Assertions'**
  String get reTabAssertions;

  /// No description provided for @reTabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get reTabSettings;

  /// No description provided for @rePathVars.
  ///
  /// In en, this message translates to:
  /// **'Path variables'**
  String get rePathVars;

  /// No description provided for @reValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get reValue;

  /// No description provided for @reGenerated.
  ///
  /// In en, this message translates to:
  /// **'Generated headers ({count})'**
  String reGenerated(int count);

  /// No description provided for @reGeneratedHint.
  ///
  /// In en, this message translates to:
  /// **'Add a header with the same name to override'**
  String get reGeneratedHint;

  /// No description provided for @reNoFile.
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get reNoFile;

  /// No description provided for @reFileInfo.
  ///
  /// In en, this message translates to:
  /// **'{name} ({size} bytes)'**
  String reFileInfo(String name, int size);

  /// No description provided for @reChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file…'**
  String get reChooseFile;

  /// No description provided for @reReplaceFile.
  ///
  /// In en, this message translates to:
  /// **'Replace file…'**
  String get reReplaceFile;

  /// No description provided for @reRemoveFile.
  ///
  /// In en, this message translates to:
  /// **'Remove file'**
  String get reRemoveFile;

  /// No description provided for @reNoBody.
  ///
  /// In en, this message translates to:
  /// **'This request has no body'**
  String get reNoBody;

  /// No description provided for @reHttpVersion.
  ///
  /// In en, this message translates to:
  /// **'HTTP version'**
  String get reHttpVersion;

  /// No description provided for @reHttp2Hint.
  ///
  /// In en, this message translates to:
  /// **'HTTP/2 needs an https:// URL'**
  String get reHttp2Hint;

  /// No description provided for @reHttpAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (HTTP/2 if offered)'**
  String get reHttpAuto;

  /// No description provided for @reHttp11.
  ///
  /// In en, this message translates to:
  /// **'HTTP/1.1 only'**
  String get reHttp11;

  /// No description provided for @reHttp2.
  ///
  /// In en, this message translates to:
  /// **'HTTP/2 only'**
  String get reHttp2;

  /// No description provided for @reTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout (ms), empty = default'**
  String get reTimeout;

  /// No description provided for @reMaxRedirects.
  ///
  /// In en, this message translates to:
  /// **'Max redirects, empty = default'**
  String get reMaxRedirects;

  /// No description provided for @reVerifyTls.
  ///
  /// In en, this message translates to:
  /// **'Verify TLS certificates'**
  String get reVerifyTls;

  /// No description provided for @reFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow redirects'**
  String get reFollow;

  /// No description provided for @reKeepMethod.
  ///
  /// In en, this message translates to:
  /// **'Keep original method on redirect'**
  String get reKeepMethod;

  /// No description provided for @reStripAuth.
  ///
  /// In en, this message translates to:
  /// **'Remove auth on cross-origin redirect'**
  String get reStripAuth;

  /// No description provided for @reCookies.
  ///
  /// In en, this message translates to:
  /// **'Send and save cookies'**
  String get reCookies;

  /// No description provided for @reUseProxy.
  ///
  /// In en, this message translates to:
  /// **'Use the proxy'**
  String get reUseProxy;

  /// No description provided for @reUseProxyHint.
  ///
  /// In en, this message translates to:
  /// **'Turn off to bypass the proxy for this request'**
  String get reUseProxyHint;

  /// No description provided for @reDecompress.
  ///
  /// In en, this message translates to:
  /// **'Decompress responses automatically'**
  String get reDecompress;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
