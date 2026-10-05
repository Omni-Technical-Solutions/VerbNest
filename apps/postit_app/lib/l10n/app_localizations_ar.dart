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
}
