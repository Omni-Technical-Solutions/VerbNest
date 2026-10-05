// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get navCollections => 'المجموعات';

  @override
  String get navHistory => 'السجل';

  @override
  String get navEnvironments => 'البيئات';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get selectOrCreateRequest => 'اختر طلبًا أو أنشئ طلبًا جديدًا';

  @override
  String get paletteHint => 'اكتب أمرًا أو اسم طلب';

  @override
  String get paletteNothing => 'لا توجد نتائج';

  @override
  String get cmdNewRequest => 'طلب جديد';

  @override
  String get cmdSend => 'إرسال الطلب';

  @override
  String get cmdSearch => 'البحث في مساحة العمل…';

  @override
  String get cmdToggleSidebar => 'إظهار أو إخفاء الشريط الجانبي';

  @override
  String get cmdCloseTab => 'إغلاق التبويب';

  @override
  String cmdGoTo(String place) {
    return 'الانتقال إلى $place';
  }

  @override
  String get closeTab => 'إغلاق التبويب';

  @override
  String get language => 'اللغة';

  @override
  String get systemDefault => 'افتراضي النظام';

  @override
  String get themeSystem => 'النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get secretsProtected => 'الأسرار محفوظة في مخزن أسرار النظام';

  @override
  String get secretsUnprotected => 'الأسرار مخزنة دون تشفير على هذا الجهاز';

  @override
  String get secretsUnavailableHint =>
      'مخزن أسرار النظام غير متاح (على لينكس ثبّت خدمة سلسلة المفاتيح وافتح قفلها).';

  @override
  String get defaultTimeout => 'المهلة الافتراضية (بالثواني)';

  @override
  String get verifyTls => 'التحقق من شهادات TLS';

  @override
  String get verifyTlsHint => 'إيقاف هذا غير آمن على الشبكات العامة';

  @override
  String get warnUnresolved => 'تحذير قبل الإرسال مع متغيرات غير معرّفة';

  @override
  String get followRedirects => 'اتباع إعادة التوجيه';

  @override
  String get appearanceSection => 'المظهر (هذا الجهاز)';

  @override
  String get historySection => 'السجل (هذا الجهاز)';

  @override
  String get historyBodies => 'الاحتفاظ بمحتوى الطلبات والاستجابات';

  @override
  String get historyBodiesHint =>
      'عند الإيقاف تُحفظ العناوين والرؤوس والحالة فقط';

  @override
  String get historyDays => 'حذف السجل الأقدم من (أيام، 0 = أبدًا)';

  @override
  String get historyMax => 'الحد الأقصى لعدد المدخلات';

  @override
  String get close => 'إغلاق';

  @override
  String get rtConnect => 'اتصال';

  @override
  String get rtConnecting => 'جارٍ الاتصال…';

  @override
  String get rtDisconnect => 'قطع الاتصال';

  @override
  String get rtClear => 'مسح';

  @override
  String get rtMessageHint => 'رسالة';

  @override
  String get rtSendTooltip => 'إرسال الرسالة';

  @override
  String get mockTitle => 'خادم تجريبي';

  @override
  String get mockEmpty =>
      'لا يوجد هنا طلب له مثال محفوظ. احفظ استجابة كمثال أولًا.';

  @override
  String get mockPort => 'المنفذ';

  @override
  String get mockStart => 'بدء';

  @override
  String get mockStop => 'إيقاف';

  @override
  String mockServing(String url) {
    return 'يعمل على $url';
  }

  @override
  String get mockPortInvalid => 'يجب أن يكون المنفذ بين 0 و65535';

  @override
  String mockListenFailed(int port, String error) {
    return 'تعذر الاستماع على المنفذ $port: $error';
  }

  @override
  String mockRouteSubtitle(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مثالًا',
      few: '$count أمثلة',
      two: 'مثالان',
      one: 'مثال واحد',
    );
    return '$name، $_temp0';
  }

  @override
  String get mockHeaderHint =>
      'أرسل الترويسة X-PostIt-Example لاختيار مثال بالاسم.';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get delete => 'حذف';

  @override
  String get nameLabel => 'الاسم';

  @override
  String get noEnvironment => 'بلا بيئة';

  @override
  String get variablesInEffect => 'المتغيرات السارية';

  @override
  String get noVariablesDefined => 'لا توجد متغيرات معرّفة.';

  @override
  String get revisionsTitle => 'الإصدارات السابقة';

  @override
  String get revisionsNone => 'لا توجد إصدارات سابقة بعد';

  @override
  String get restore => 'استعادة';

  @override
  String get kvChooseFile => 'اختر ملفًا…';

  @override
  String get kvTableEdit => 'تحرير كجدول';

  @override
  String get kvBulkEdit => 'تحرير نصي';

  @override
  String get kvBulkHint => 'مفتاح: قيمة (واحد في كل سطر، // للتعطيل)';

  @override
  String get kvKey => 'المفتاح';

  @override
  String get kvValue => 'القيمة';

  @override
  String get kvSwitchToText => 'ملف (التبديل إلى نص)';

  @override
  String get kvSwitchToFile => 'نص (التبديل إلى ملف)';

  @override
  String get remove => 'إزالة';

  @override
  String get add => 'إضافة';

  @override
  String get asStatusCode => 'رمز الحالة';

  @override
  String get asHeader => 'ترويسة';

  @override
  String get asJsonPath => 'مسار JSON';

  @override
  String get asResponseTime => 'زمن الاستجابة (مللي ثانية)';

  @override
  String get asBody => 'المحتوى';

  @override
  String get asSchema => 'مخطط JSON';

  @override
  String get asAdd => 'إضافة تحقق';

  @override
  String get tokenNeverExpires => 'لا تنتهي صلاحيته';

  @override
  String get tokenExpired => 'منتهي الصلاحية';

  @override
  String tokenExpiresSeconds(int n) {
    return 'تنتهي خلال $n ث';
  }

  @override
  String tokenExpiresMinutes(int n) {
    return 'تنتهي خلال $n د';
  }

  @override
  String tokenExpiresHours(int n) {
    return 'تنتهي خلال $n س';
  }

  @override
  String get tokensTitle => 'رموز OAuth 2.0';

  @override
  String get tokensEmpty =>
      'لا توجد رموز بعد. تُحفظ في الذاكرة حتى تغلق التطبيق.';

  @override
  String get tokenNoClientId => 'بلا معرّف عميل';

  @override
  String get tokenHasRefresh => 'لديه رمز تحديث';

  @override
  String get tokensDeleteAll => 'حذف الكل';

  @override
  String runTitle(String name) {
    return 'تشغيل \"$name\"';
  }

  @override
  String get runNoRows => 'الملف لا يحتوي على صفوف';

  @override
  String get runReportSaved => 'تم حفظ التقرير';

  @override
  String get runNoRequests => 'لا توجد طلبات للتشغيل هنا';

  @override
  String get runIterations => 'التكرارات';

  @override
  String get runDelay => 'التأخير (مللي ثانية)';

  @override
  String get runStopOnFailure => 'التوقف عند أول فشل';

  @override
  String get runDataFile => 'ملف بيانات…';

  @override
  String runDataFileRows(String name, int count) {
    return '$name ($count صفوف)';
  }

  @override
  String get runRemoveData => 'إزالة ملف البيانات';

  @override
  String get runStart => 'تشغيل';

  @override
  String runProgress(int iteration, int total) {
    return 'التكرار $iteration من $total';
  }

  @override
  String get runResultsHere => 'تظهر النتائج هنا';

  @override
  String get runSkipped => 'تم التخطي';

  @override
  String runEntrySummary(String status, int ms, int passed, int failed) {
    return '$status · $ms مللي ثانية · نجح $passed، فشل $failed';
  }

  @override
  String runIterationSuffix(int n) {
    return 'التكرار $n';
  }

  @override
  String runSummary(int requests, int passed, int failed, int errors) {
    return '$requests طلبات · نجح $passed · فشل $failed · أخطاء $errors';
  }

  @override
  String get runStoppedEarly => 'توقف مبكرًا';

  @override
  String get runStop => 'إيقاف';

  @override
  String get histSearchHint => 'بحث بالطريقة أو العنوان أو الحالة';

  @override
  String get histConsole => 'وحدة الشبكة';

  @override
  String get histClear => 'مسح السجل';

  @override
  String get histEmpty => 'تظهر الطلبات التي ترسلها هنا';

  @override
  String histNoMatch(String query) {
    return 'لا شيء يطابق \"$query\"';
  }

  @override
  String get histClearTitle => 'مسح السجل؟';

  @override
  String get histClearMessage =>
      'ستُحذف جميع الطلبات والاستجابات المخزنة على هذا الجهاز.';

  @override
  String get histError => 'خطأ';

  @override
  String get histOpenRequest => 'فتح الطلب';

  @override
  String histSavedMasked(String placeholder) {
    return 'تم الحفظ في \"Imported\". أُخفيت الأسرار ($placeholder); أدخلها من جديد.';
  }

  @override
  String get histSaved => 'تم الحفظ في \"Imported\"';

  @override
  String get histSaveAsNew => 'حفظ كطلب جديد';

  @override
  String get histTabRequest => 'الطلب';

  @override
  String get histTabResponse => 'الاستجابة';

  @override
  String get histNoBody => 'لا يوجد محتوى استجابة محفوظ';

  @override
  String get histTruncated => '[قُطع عند الحفظ]';

  @override
  String get today => 'اليوم';

  @override
  String get yesterday => 'أمس';

  @override
  String get envNew => 'بيئة جديدة';

  @override
  String get envCreate => 'إنشاء';

  @override
  String envExists(String name) {
    return 'توجد بيئة باسم \"$name\" بالفعل';
  }

  @override
  String get rename => 'إعادة تسمية';

  @override
  String envDeleteTitle(String name) {
    return 'حذف \"$name\"؟';
  }

  @override
  String get cannotUndo => 'لا يمكن التراجع عن هذا.';

  @override
  String get envGlobals => 'العامة';

  @override
  String get envVarName => 'الاسم';

  @override
  String get envSecretValue => 'قيمة سرية';

  @override
  String get envInitialValue => 'القيمة الأولية';

  @override
  String get envHide => 'إخفاء';

  @override
  String get envShow => 'إظهار';

  @override
  String get envCurrentValue => 'القيمة الحالية (هذا الجهاز)';

  @override
  String get envSecret => 'سري';

  @override
  String get envMarkSecret => 'تعيين كسر';

  @override
  String envDuplicates(String names) {
    return 'أسماء مكررة: $names. يُستخدم الأخير.';
  }

  @override
  String get envAddVariable => 'إضافة متغير';

  @override
  String get consoleTitle => 'وحدة الشبكة';

  @override
  String get clear => 'مسح';

  @override
  String get consoleEmpty => 'لم يُرسل شيء في هذه الجلسة بعد';

  @override
  String get consoleSent => 'المُرسل';

  @override
  String get consoleError => 'خطأ';

  @override
  String get consoleReceived => 'المُستلم';

  @override
  String get cookiesTitle => 'ملفات الارتباط';

  @override
  String get cookiesEmpty => 'لا توجد ملفات ارتباط محفوظة بعد';

  @override
  String cookiesDeleteDomain(String domain) {
    return 'حذف الكل لـ $domain';
  }

  @override
  String cookiePath(String path) {
    return 'المسار $path';
  }

  @override
  String get cookieSession => 'جلسة';

  @override
  String cookieExpires(String when) {
    return 'تنتهي $when';
  }

  @override
  String get deleteAll => 'حذف الكل';

  @override
  String get codeTitle => 'توليد الشيفرة';

  @override
  String get codeFillVariables => 'ملء قيم المتغيرات';

  @override
  String get codeSecretsWarning => 'ستظهر القيم السرية في الشيفرة';

  @override
  String get codeCopied => 'تم نسخ الشيفرة';

  @override
  String get copy => 'نسخ';

  @override
  String get wsTitle => 'مساحات العمل';

  @override
  String get wsInMemory => 'في الذاكرة';

  @override
  String get wsRename => 'إعادة تسمية';

  @override
  String get wsRenameTitle => 'إعادة تسمية مساحة العمل';

  @override
  String get wsImport => 'استيراد…';

  @override
  String get wsImportSnapshot => 'استيراد لقطة…';

  @override
  String get wsExportSnapshot => 'تصدير لقطة…';

  @override
  String get wsExport => 'تصدير…';

  @override
  String get wsNewTitle => 'مساحة عمل جديدة';

  @override
  String get wsCreate => 'إنشاء';

  @override
  String get wsNew => 'جديد';

  @override
  String wsSnapshotMerged(int requests, int environments) {
    return 'تم دمج اللقطة: $requests طلبات، $environments بيئات';
  }

  @override
  String wsSnapshotKept(int count, String first) {
    return '، تم إبقاء $count كما هي ($first)';
  }

  @override
  String settingsTextSize(int percent) {
    return 'حجم النص $percent%';
  }

  @override
  String settingsCodeFontSize(int size) {
    return 'حجم خط الشيفرة $size';
  }

  @override
  String get scriptPre => 'قبل الطلب';

  @override
  String get scriptPreSet => 'قبل الطلب •';

  @override
  String get scriptPost => 'بعد الاستجابة';

  @override
  String get scriptPostSet => 'بعد الاستجابة •';

  @override
  String get scriptHelp =>
      'تتوفر pm.variables وpm.environment وpm.collectionVariables وpm.globals وpm.request وpm.response وpm.test وpm.expect وconsole. تتوقف السكربتات بعد 5 ثوانٍ؛ pm.sendRequest غير مدعوم بعد.';

  @override
  String get langEnglish => 'English';

  @override
  String get langArabic => 'العربية';

  @override
  String get exFavRemove => 'إزالة من المفضلة';

  @override
  String get exFavAdd => 'إضافة إلى المفضلة';

  @override
  String get exTitle => 'الأمثلة';

  @override
  String get exEmpty => 'لا توجد أمثلة بعد';

  @override
  String get exSave => 'حفظ الاستجابة الحالية';

  @override
  String get exClose => 'إغلاق';

  @override
  String get exSelect => 'اختر مثالاً';

  @override
  String get exDelete => 'حذف المثال';

  @override
  String get nsTitle => 'الشبكة (هذا الجهاز)';

  @override
  String nsCookies(int count) {
    return 'ملفات الارتباط ($count)';
  }

  @override
  String get nsCookiesHint => 'تُحفظ من الاستجابات وتُرسل تلقائياً';

  @override
  String get nsUseProxy => 'استخدام وكيل';

  @override
  String get nsProxyHttp => 'HTTP';

  @override
  String get nsProxySocks => 'SOCKS5';

  @override
  String get nsProxyHost => 'مضيف الوكيل';

  @override
  String get nsProxyPort => 'منفذ الوكيل';

  @override
  String get nsProxyUser => 'اسم مستخدم الوكيل (اختياري)';

  @override
  String get nsProxyPassword => 'كلمة مرور الوكيل (اختياري)';

  @override
  String get nsProxyBypass => 'بلا وكيل لـ (مضيفون مفصولون بفواصل)';

  @override
  String get nsSystemProxy => 'استخدام HTTP_PROXY / HTTPS_PROXY / NO_PROXY';

  @override
  String get nsSystemProxyHint =>
      'تُقرأ من البيئة عند عدم تعيين وكيل أعلاه. لا تُقرأ إعدادات وكيل نظام التشغيل.';

  @override
  String get nsCertsTitle => 'الشهادات (هذا الجهاز)';

  @override
  String get nsCaHint => 'جهة إصدار شهادات موثوقة';

  @override
  String get nsRemove => 'إزالة';

  @override
  String nsClientCertFor(String pattern) {
    return 'شهادة العميل لـ $pattern';
  }

  @override
  String get nsAddCa => 'إضافة جهة موثوقة';

  @override
  String get nsAddClientCert => 'إضافة شهادة عميل';

  @override
  String get nsClientCertTitle => 'شهادة العميل';

  @override
  String get nsCertHosts => 'المضيفون (api.example.com أو *.example.com أو *)';

  @override
  String get nsChooseCert => 'اختر الشهادة (.pem, .p12)';

  @override
  String get nsChooseKey => 'اختر المفتاح الخاص (.pem)';

  @override
  String get nsPassphrase => 'عبارة المرور (اختياري)';

  @override
  String get nsCancel => 'إلغاء';

  @override
  String get nsAdd => 'إضافة';

  @override
  String get authInherit => 'يستخدم مصادقة المجلد أو المجموعة الحاوية.';

  @override
  String get authToken => 'الرمز';

  @override
  String get authUsername => 'اسم المستخدم';

  @override
  String get authPassword => 'كلمة المرور';

  @override
  String get authKey => 'المفتاح';

  @override
  String get authValue => 'القيمة';

  @override
  String get authHeader => 'الترويسة';

  @override
  String get authQuery => 'الاستعلام';

  @override
  String get authDigestHint =>
      'يُرسل الطلب مرة دون بيانات اعتماد، ويُجاب على تحدي الخادم تلقائياً.';

  @override
  String get authAccessKey => 'مفتاح الوصول';

  @override
  String get authSecretKey => 'المفتاح السري';

  @override
  String get authRegion => 'المنطقة';

  @override
  String get authService => 'الخدمة';

  @override
  String get authSessionToken => 'رمز الجلسة';

  @override
  String get authNone => 'لا تتم إضافة أي تفويض.';

  @override
  String authRaw(String type) {
    return 'نوع المصادقة \"$type\" محفوظ لكنه غير قابل للتحرير بعد.';
  }

  @override
  String get authSecret => 'السر';

  @override
  String get authPayload => 'الحمولة (JSON)';

  @override
  String get authHeaderPrefix => 'بادئة الترويسة';

  @override
  String get authJwtHint =>
      'يُوقَّع رمز عند كل إرسال؛ وتُضاف iat إن لم تكن موجودة.';

  @override
  String get oauthClientCredentials => 'بيانات اعتماد العميل';

  @override
  String get oauthPassword => 'كلمة المرور';

  @override
  String get oauthAuthCode => 'رمز التفويض (المتصفح)';

  @override
  String get oauthImplicit => 'ضمني (المتصفح)';

  @override
  String get oauthAuthUrl => 'عنوان التفويض';

  @override
  String get oauthTokenUrl => 'عنوان الرمز';

  @override
  String get oauthClientId => 'معرّف العميل';

  @override
  String get oauthClientSecret => 'سر العميل';

  @override
  String get oauthScope => 'النطاق';

  @override
  String get oauthPkce => 'استخدام PKCE';

  @override
  String get oauthBrowserHint =>
      'يفتح الإرسال المتصفح لتسجيل الدخول. عنوان إعادة التوجيه هو http://127.0.0.1:<port>/callback بمنفذ عشوائي؛ إن احتاج مزودك إلى عنوان ثابت فسجّل عنوان الحلقة المحلية بمنفذ عام.';

  @override
  String get oauthTokens => 'الرموز…';

  @override
  String get oauthBodyCreds => 'إرسال بيانات اعتماد العميل في المتن';

  @override
  String gqlLoaded(int count) {
    return 'تم تحميل المخطط: $count أنواع';
  }

  @override
  String gqlLoadFailed(String message) {
    return 'تعذّر تحميل المخطط: $message';
  }

  @override
  String gqlImported(int count) {
    return 'تم استيراد المخطط: $count أنواع';
  }

  @override
  String gqlReadFailed(String message) {
    return 'تعذّرت قراءة المخطط: $message';
  }

  @override
  String get gqlFetch => 'جلب المخطط';

  @override
  String get gqlImportSdl => 'استيراد SDL…';

  @override
  String get gqlExplore => 'استكشاف';

  @override
  String get gqlNoSchema => 'لم يتم تحميل مخطط';

  @override
  String gqlTypeCount(int count) {
    return '$count أنواع';
  }

  @override
  String get gqlOperation => 'العملية';

  @override
  String get gqlQuery => 'الاستعلام';

  @override
  String get gqlVariables => 'المتغيرات (JSON)';

  @override
  String get gqlSdlTitle => 'استيراد المخطط (SDL)';

  @override
  String get gqlChooseFile => 'اختر ملف .graphql…';

  @override
  String get gqlCancel => 'إلغاء';

  @override
  String get gqlImport => 'استيراد';

  @override
  String get gqlSchema => 'المخطط';

  @override
  String get gqlFindType => 'ابحث عن نوع';

  @override
  String gqlImplements(String interfaces) {
    return 'ينفّذ $interfaces';
  }

  @override
  String get sbFilter => 'تصفية';

  @override
  String get sbWorkspaces => 'مساحات العمل';

  @override
  String get sbShowAll => 'عرض الكل';

  @override
  String get sbShowFav => 'عرض المفضلة فقط';

  @override
  String get sbSearch => 'البحث في مساحة العمل';

  @override
  String get sbImport => 'استيراد';

  @override
  String get sbNewCollection => 'مجموعة جديدة';

  @override
  String get sbNoFav => 'لا توجد مفضلة بعد.\nضع نجمة على طلب لتثبيته هنا.';

  @override
  String sbNoMatch(String filter) {
    return 'لا شيء يطابق \"$filter\"';
  }

  @override
  String get sbNoCollections => 'لا توجد مجموعات بعد.\nأنشئ واحدة للبدء.';

  @override
  String get sbActions => 'الإجراءات';

  @override
  String get sbNewRequest => 'طلب جديد';

  @override
  String get sbNewFolder => 'مجلد جديد';

  @override
  String get sbRename => 'إعادة تسمية';

  @override
  String get sbRun => 'تشغيل…';

  @override
  String get sbSettings => 'الإعدادات';

  @override
  String get sbDuplicate => 'تكرار';

  @override
  String get sbMoveUp => 'نقل لأعلى';

  @override
  String get sbMoveDown => 'نقل لأسفل';

  @override
  String get sbVersions => 'الإصدارات السابقة…';

  @override
  String get sbCopyCurl => 'نسخ كـ cURL';

  @override
  String get sbFavRemove => 'إزالة من المفضلة';

  @override
  String get sbFavAdd => 'إضافة إلى المفضلة';

  @override
  String get sbGenerateCode => 'توليد الشيفرة…';

  @override
  String get sbCopyPostman => 'نسخ كـ Postman JSON';

  @override
  String get sbDelete => 'حذف';

  @override
  String get sbCreate => 'إنشاء';

  @override
  String get sbCurlCopied => 'تم نسخ أمر cURL';

  @override
  String get sbPostmanCopied => 'تم نسخ مجموعة Postman';

  @override
  String sbDeleteTitle(String name) {
    return 'حذف \"$name\"؟';
  }

  @override
  String get sbDeleteFolderMsg => 'سيؤدي هذا أيضاً إلى حذف كل ما بداخله.';

  @override
  String get sbDeleteMsg => 'لا يمكن التراجع عن هذا.';

  @override
  String sbImportNotes(int count, String first) {
    return ' ($count ملاحظات: $first)';
  }

  @override
  String get sbImportHint =>
      'الصق أمر cURL أو مجموعة أو بيئة Postman أو ملف OpenAPI/Swagger (JSON أو YAML) أو تسجيل HAR';

  @override
  String get sbCancel => 'إلغاء';

  @override
  String get rvOnWire => 'على الشبكة';

  @override
  String get rvSave => 'حفظ';

  @override
  String get rvShare => 'مشاركة';

  @override
  String get rvEmpty => 'أرسل الطلب لرؤية الاستجابة';

  @override
  String get rvTabBody => 'المتن';

  @override
  String get rvTabCookies => 'ملفات الارتباط';

  @override
  String rvTabCookiesN(int count) {
    return 'ملفات الارتباط ($count)';
  }

  @override
  String get rvTabHeaders => 'الترويسات';

  @override
  String get rvTabSent => 'المُرسل';

  @override
  String get rvTabTests => 'الاختبارات';

  @override
  String rvTabTestsN(int passed, int counted) {
    return 'الاختبارات ($passed/$counted)';
  }

  @override
  String get rvTiming => 'التوقيت';

  @override
  String get rvTotal => 'الإجمالي';

  @override
  String get rvDns => 'استعلام DNS';

  @override
  String get rvTcp => 'اتصال TCP';

  @override
  String get rvTlsHandshake => 'مصافحة TLS';

  @override
  String get rvTtfb => 'الانتظار (TTFB)';

  @override
  String get rvDownload => 'التنزيل';

  @override
  String get rvOther => 'أخرى';

  @override
  String get rvClose => 'إغلاق';

  @override
  String get rvTlsTitle => 'اتصال TLS';

  @override
  String rvTlsSubject(String value) {
    return 'الموضوع: $value';
  }

  @override
  String rvTlsIssuer(String value) {
    return 'المُصدر: $value';
  }

  @override
  String rvTlsValid(String from, String to) {
    return 'صالحة: من $from إلى $to';
  }

  @override
  String rvTlsProtocol(String value) {
    return 'البروتوكول: $value';
  }

  @override
  String rvTlsClientCert(String answer) {
    return 'أُرسلت شهادة العميل: $answer';
  }

  @override
  String get rvYes => 'نعم';

  @override
  String get rvNo => 'لا';

  @override
  String get rvNoTests =>
      'لم يتم تشغيل أي اختبار. أضف pm.test() إلى سكربت ما بعد الاستجابة.';

  @override
  String get rvScriptError => 'خطأ في السكربت';

  @override
  String get rvConsole => 'وحدة التحكم';

  @override
  String get rvCopyValue => 'نسخ القيمة';

  @override
  String rvHeaderCopied(String name) {
    return 'تم نسخ $name';
  }

  @override
  String get rvPretty => 'منسّق';

  @override
  String get rvRaw => 'خام';

  @override
  String get rvHex => 'سداسي عشري';

  @override
  String get rvPreview => 'معاينة';

  @override
  String get rvSearch => 'بحث';

  @override
  String get rvCopyBody => 'نسخ المتن';

  @override
  String get rvBodyCopied => 'تم نسخ المتن';

  @override
  String get rvFilterJson => 'صفِّ باستخدام JSONPath، مثل \$.items[*].id';

  @override
  String get rvFilterXml => 'صفِّ باستخدام XPath، مثل //item/@id';

  @override
  String get rvImageError => 'تعذّر عرض هذه الصورة';

  @override
  String get rvNoCookies => 'لم تضبط هذه الاستجابة أي ملفات ارتباط';

  @override
  String get rvTls => 'TLS';

  @override
  String rvHttpVersion(String version) {
    return 'HTTP/$version';
  }

  @override
  String get reExamples => 'الأمثلة';

  @override
  String reUndefined(String names) {
    return 'متغيرات غير معرّفة: $names';
  }

  @override
  String get reResponseSaved => 'تم حفظ الاستجابة';

  @override
  String reNotDefined(String names) {
    return 'غير معرّف: $names';
  }

  @override
  String get reSendAnyway => 'أرسل على أي حال';

  @override
  String get reDontWarn => 'لا تحذّر مجدداً';

  @override
  String get reCancel => 'إلغاء';

  @override
  String get reCustom => 'مخصص…';

  @override
  String get reCustomMethod => 'طريقة مخصصة';

  @override
  String get reSet => 'تعيين';

  @override
  String get reLiveTooltip => 'فتح WebSocket أو SSE أو اشتراك GraphQL';

  @override
  String get reLiveWs => 'WebSocket';

  @override
  String get reLiveSseTitle => 'أحداث مرسلة من الخادم';

  @override
  String get reLiveSub => 'اشتراك GraphQL';

  @override
  String get reLiveSse => 'بث SSE';

  @override
  String get reSend => 'إرسال';

  @override
  String get reTabParams => 'المعاملات';

  @override
  String get reTabHeaders => 'الترويسات';

  @override
  String get reTabAuth => 'المصادقة';

  @override
  String get reTabBody => 'المتن';

  @override
  String get reTabScripts => 'السكربتات';

  @override
  String get reTabAssertions => 'التأكيدات';

  @override
  String get reTabSettings => 'الإعدادات';

  @override
  String get rePathVars => 'متغيرات المسار';

  @override
  String get reValue => 'القيمة';

  @override
  String reGenerated(int count) {
    return 'الترويسات المولّدة ($count)';
  }

  @override
  String get reGeneratedHint => 'أضف ترويسة بالاسم نفسه لتجاوزها';

  @override
  String get reNoFile => 'لم يتم اختيار ملف';

  @override
  String reFileInfo(String name, int size) {
    return '$name ($size بايت)';
  }

  @override
  String get reChooseFile => 'اختر ملفاً…';

  @override
  String get reReplaceFile => 'استبدل الملف…';

  @override
  String get reRemoveFile => 'إزالة الملف';

  @override
  String get reNoBody => 'ليس لهذا الطلب متن';

  @override
  String get reHttpVersion => 'إصدار HTTP';

  @override
  String get reHttp2Hint => 'يحتاج HTTP/2 إلى عنوان https://';

  @override
  String get reHttpAuto => 'تلقائي (HTTP/2 إن عُرض)';

  @override
  String get reHttp11 => 'HTTP/1.1 فقط';

  @override
  String get reHttp2 => 'HTTP/2 فقط';

  @override
  String get reTimeout => 'المهلة (مللي ثانية)، فارغ = الافتراضي';

  @override
  String get reMaxRedirects =>
      'أقصى عدد لعمليات إعادة التوجيه، فارغ = الافتراضي';

  @override
  String get reVerifyTls => 'التحقق من شهادات TLS';

  @override
  String get reFollow => 'اتباع عمليات إعادة التوجيه';

  @override
  String get reKeepMethod => 'الإبقاء على الطريقة الأصلية عند إعادة التوجيه';

  @override
  String get reStripAuth => 'إزالة المصادقة عند إعادة التوجيه إلى أصل آخر';

  @override
  String get reCookies => 'إرسال ملفات الارتباط وحفظها';

  @override
  String get reUseProxy => 'استخدام الوكيل';

  @override
  String get reUseProxyHint => 'أوقفه لتجاوز الوكيل لهذا الطلب';

  @override
  String get reDecompress => 'فك ضغط الاستجابات تلقائياً';

  @override
  String get rvHtmlTooLarge =>
      'هذه الصفحة كبيرة جداً للمعاينة. استخدم الخام أو احفظها.';

  @override
  String get rtSave => 'حفظ السجل…';

  @override
  String get rtHex => 'سداسي عشري';

  @override
  String get rtHexHint => 'بايتات بالنظام السداسي عشري، مثل 0a ff 10';
}
