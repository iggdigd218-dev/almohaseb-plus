import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// نظام الترجمة وتعدد اللغات الموحّد للتطبيق (العربية `ar` / الإنجليزية `en`).
/// يوفر:
/// - `AppLocalizations.of(context)` للوصول السريع للنصوص المترجمة.
/// - `tr(context, ar, en)` و `context.tr(ar, en)` لترجمة أي نص ثنائي اللغة مباشرةً.
/// - قاموس ترجمة شامل لعناوين الشاشات، القوائم، الأزرار، والإعدادات.
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  bool get isEn => locale.languageCode.toLowerCase().startsWith('en');
  bool get isAr => !isEn;

  TextDirection get textDirection =>
      isEn ? TextDirection.ltr : TextDirection.rtl;

  static AppLocalizations of(BuildContext context) {
    final loc = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (loc != null) return loc;
    final maybeLocale = Localizations.maybeLocaleOf(context);
    return AppLocalizations(maybeLocale ?? const Locale('ar'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('ar'),
    Locale('en'),
  ];

  /// إرجاع النص المناسب حسب اللغة النشطة، أو البحث في القاموس الموحّد.
  String text(String ar, [String? en]) {
    if (!isEn) return ar;
    if (en != null && en.isNotEmpty) return en;
    return _arToEnDictionary[ar] ?? ar;
  }

  // ───────── النصوص الأساسية ─────────
  String get appTitle => isEn ? 'Al-Mohaseb' : 'المحاسب';
  String get languageLabel => isEn ? 'Language / اللغة' : 'اللغة / Language';
  String get languageSubtitle => isEn
      ? 'Switch interface language immediately (Arabic / English)'
      : 'تغيير لغة التطبيق فوراً (العربية / English)';
  String get arabicName => 'العربية';
  String get englishName => 'English';

  // ───────── الشاشات والقوائم ─────────
  String get navDashboard => isEn ? 'Dashboard' : 'الرئيسية';
  String get navPos => isEn ? 'POS & Sales' : 'نقطة البيع';
  String get navSalesInvoices => isEn ? 'Sales Invoices' : 'فواتير المبيعات';
  String get navInventory => isEn ? 'Inventory & Items' : 'المخزون والأصناف';
  String get navAccounts => isEn ? 'Customers' : 'العملاء';
  String get navSuppliers => isEn ? 'Suppliers' : 'الموردون';
  String get navTransactions => isEn ? 'Transactions' : 'العمليات';
  String get navReports => isEn ? 'Reports' : 'التقارير';
  String get navAlerts => isEn ? 'Alerts & Notifications' : 'التنبيهات';
  String get navGroup => isEn ? 'Devices & Sync' : 'إدارة المجموعة';
  String get navSettings => isEn ? 'Settings' : 'الإعدادات';
  String get navAbout => isEn ? 'About' : 'حول التطبيق';

  // ───────── تسجيل الدخول والحساب ─────────
  String get loginScreenTitle =>
      isEn ? 'Sign In & Account Management' : 'تسجيل الدخول وإدارة الحساب';
  String get loginScreenSubtitle => isEn
      ? 'Enter your email to access your workspace or create a new account'
      : 'أدخل بريدك الإلكتروني للدخول إلى منشأتك أو إنشاء حساب جديد';
  String get savedWorkspacesOnDevice =>
      isEn ? 'Saved Workspaces on This Device' : 'المنشآت المحفوظة على هذا الجهاز';
  String get enterBtn => isEn ? 'Enter' : 'دخول';
  String get loginWithoutAccount =>
      isEn ? 'Continue Without Account' : 'الدخول بدون حساب';
  String get emailLabel => isEn ? 'Email Address' : 'البريد الإلكتروني';
  String get passwordLabel => isEn ? 'Password' : 'كلمة المرور';
  String get forgotPassword => isEn ? 'Forgot password?' : 'نسيت كلمة السر؟';
  String get signInBtn => isEn ? 'Sign In' : 'تسجيل الدخول';
  String get registerNewBtn => isEn ? 'New Registration' : 'تسجيل جديد';
  String get googleAccountBtn => isEn ? 'Google Account' : 'حساب Google';

  // ───────── رسائل أخطاء تسجيل الدخول الصريحة ─────────
  static const String errNoInternetAr =
      'لا يوجد اتصال بالإنترنت، يرجى التحقق من الشبكة';
  static const String errInvalidCredentialsAr =
      'خطأ في البريد الإلكتروني / رقم الهاتف أو كلمة المرور';
  static const String errAccountOrWorkspaceNotFoundAr =
      'لم يتم العثور على حسابك أو أي منشأة مرتبطة بهذا الحساب';

  String get errNoInternet => isEn
      ? 'No internet connection, please check your network'
      : errNoInternetAr;
  String get errInvalidCredentials => isEn
      ? 'Incorrect email / phone number or password'
      : errInvalidCredentialsAr;
  String get errAccountOrWorkspaceNotFound => isEn
      ? 'Your account or any workspace linked to this account was not found'
      : errAccountOrWorkspaceNotFoundAr;

  static const Map<String, String> _arToEnDictionary = {
    'المحاسب': 'Al-Mohaseb',
    'الرئيسية': 'Dashboard',
    'نقطة البيع': 'Point of Sale',
    'فواتير المبيعات': 'Sales Invoices',
    'المخزون والأصناف': 'Inventory & Items',
    'العملاء': 'Customers',
    'الحسابات': 'Accounts',
    'الموردون': 'Suppliers',
    'العمليات': 'Transactions',
    'التقارير': 'Reports',
    'التنبيهات': 'Alerts',
    'الإشعارات': 'Notifications',
    'إدارة المجموعة': 'Group Management',
    'الإعدادات': 'Settings',
    'حول التطبيق': 'About App',
    'بيانات المؤسسة': 'Business Profile',
    'الاسم التجاري والنشاط وبيانات التواصل والعنوان':
        'Trade name, business activity, contact info & address',
    'الفواتير والبيع': 'Invoices & POS',
    'العملة والترقيم وخيارات الفاتورة ونقطة البيع':
        'Currency, numbering, invoice & POS options',
    'المظهر والأصوات': 'Appearance & Sounds',
    'الوضع الليلي والنهاري وحجم الخط والأصوات والاهتزاز':
        'Dark/Light theme, font size, sounds & vibration',
    'المساعد الذكي (Gemini)': 'Smart Assistant (Gemini)',
    'محادثة ذكية لإدارة الفواتير والأرصدة والأصناف والأوامر الصوتية':
        'Smart chat for invoices, balances, items & voice commands',
    'الأمان': 'Security',
    'قفل الشاشة والبصمة والنسخ الاحتياطي وإعادة الضبط':
        'Screen lock, biometrics, backup & reset',
    'النظام والمزامنة': 'System & Sync',
    'المزامنة وربط الأجهزة والاشتراك والدعم والتحديث':
        'Cloud sync, device pairing, subscription, support & updates',
    'حفظ التعديلات': 'Save Changes',
    'عميل نقدي': 'Cash Customer',
    'تصفية وفرز': 'Filter & Sort',
    'تصفية وعرض': 'Filter & View',
    'إجمالي المبيعات': 'Total Sales',
    'إجمالي المستحق لنا': 'Total Receivable',
    'إجمالي المستحق علينا': 'Total Payable',
    'صافي الرصيد': 'Net Balance',
    'عليه': 'Owes',
    'له': 'Credit',
    'متزن': 'Settled',
    'يومي': 'Daily',
    'أسبوعي': 'Weekly',
    'شهري': 'Monthly',
    'سنوي': 'Yearly',
    'الكل': 'All',
    'تسجيل الدخول وإدارة الحساب': 'Sign In & Account Management',
    'المنشآت المحفوظة على هذا الجهاز': 'Saved Workspaces on This Device',
    'الدخول بدون حساب': 'Continue Without Account',
    'تسجيل الدخول': 'Sign In',
    'تسجيل جديد': 'New Registration',
    'حساب Google': 'Google Account',
    'نسيت كلمة السر؟': 'Forgot password?',
    'البريد الإلكتروني': 'Email Address',
    'كلمة المرور': 'Password',
    'إلغاء': 'Cancel',
    'حفظ': 'Save',
    'تأكيد': 'Confirm',
    'بحث': 'Search',
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['ar', 'en'].contains(locale.languageCode.toLowerCase());

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension BuildContextL10nExt on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// ترجمة فورية حسب لغة السياق الحالية (العربية افتراضياً).
  String tr(String ar, [String? en]) => AppLocalizations.of(this).text(ar, en);
}
