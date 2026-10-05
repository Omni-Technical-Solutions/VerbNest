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
}
