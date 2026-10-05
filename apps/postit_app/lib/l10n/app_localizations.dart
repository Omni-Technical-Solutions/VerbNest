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
