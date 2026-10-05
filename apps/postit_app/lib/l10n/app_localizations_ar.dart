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
}
