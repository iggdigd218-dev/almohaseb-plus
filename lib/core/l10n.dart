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
  String get emailLabel =>
      isEn ? 'Email or Phone Number' : 'البريد الإلكتروني أو رقم الهاتف';
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
    'إدارة المخزون': 'Inventory Management',
    'تعديلات المخزون': 'Stock Adjustments',
    'العملاء': 'Customers',
    'الحسابات': 'Accounts',
    'الموردون': 'Suppliers',
    'العمليات': 'Transactions',
    'الحركات': 'Transactions',
    'عملية': 'New Op',
    'عملية جديدة': 'New Transaction',
    'السندات': 'Vouchers',
    'التقارير': 'Reports',
    'التنبيهات': 'Alerts',
    'التنبيهات والمهام': 'Alerts & Tasks',
    'الإشعارات': 'Notifications',
    'إدارة المجموعة': 'Group Management',
    'أجهزة وأعضاء المجموعة': 'Group Devices & Members',
    'الأجهزة والربط': 'Devices & Pairing',
    'الإعدادات': 'Settings',
    'حول التطبيق': 'About App',
    'حول النظام': 'About System',
    'الميزانية': 'Budget',
    'العملات': 'Currencies',
    'العملات وأسعار الصرف': 'Currencies & Exchange Rates',
    'سجل النشاط': 'Activity Log',
    'النسخ الاحتياطي': 'Backup & Restore',
    'النسخ الاحتياطي (.nexora)': 'Backup & Restore',
    'سلة المحذوفات': 'Recycle Bin',
    'الإحصائيات المتقدمة': 'Advanced Analytics',
    'الدعم والمساعدة': 'Support & Help',
    'إدارة الحساب والاشتراك': 'Account & Subscription',
    'الملف الشخصي والمنشأة': 'Profile & Workspace',
    'إدارة الموظفين': 'Staff Management',
    'المستخدمون والصلاحيات': 'Users & Permissions',
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
    'المزامنة وربط الأجهزة': 'Sync & Device Pairing',
    'تسجيل الخروج': 'Sign Out',
    'حفظ التعديلات': 'Save Changes',
    'تم الحفظ ✅': 'Saved ✅',
    'عميل نقدي': 'Cash Customer',
    'تصفية وفرز': 'Filter & Sort',
    'تصفية وعرض': 'Filter & View',
    'إجمالي المبيعات': 'Total Sales',
    'إجمالي مبيعاتك اليومية': 'Your Daily Sales Total',
    'إجمالي المستحق لنا': 'Total Receivable',
    'إجمالي المستحق علينا': 'Total Payable',
    'صافي الرصيد': 'Net Balance',
    'عليه': 'Owes',
    'له': 'Credit',
    'متزن': 'Settled',
    'وارد': 'Inflow',
    'صادر': 'Outflow',
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
    'البريد الإلكتروني أو رقم الهاتف': 'Email or Phone Number',
    'كلمة المرور': 'Password',
    'إلغاء': 'Cancel',
    'حفظ': 'Save',
    'تأكيد': 'Confirm',
    'بحث': 'Search',
    'إغلاق': 'Close',
    'حذف': 'Delete',
    'تعديل': 'Edit',
    'إضافة': 'Add',
    'مشاركة': 'Share',
    'طباعة': 'Print',
    'معاينة': 'Preview',
    'إزالة من المجموعة': 'Remove from Group',
    'إخراج العضو': 'Remove Member',
    'هل تريد بالتأكيد تسجيل الخروج من الحساب؟':
        'Are you sure you want to sign out of this account?',
    'آخر العمليات': 'Recent Transactions',
    'عرض الكل': 'View All',
    'لا توجد عمليات': 'No transactions found',
    'لا توجد حسابات': 'No accounts found',
    'إضافة حساب': 'Add Account',
    'إضافة عميل': 'Add Customer',
    'إضافة عملة': 'Add Currency',
    'تعديل العملة': 'Edit Currency',
    'تعيين افتراضية': 'Set as Default',
    '✓ الافتراضية': '✓ Default',
    'محلي': 'Local',
    'الاسم التجاري / اسم المؤسسة': 'Business / Organization Name',
    'النشاط التجاري / التخصص': 'Business Activity / Specialty',
    'اسم المدير / المسؤول': 'Manager / Owner Name',
    'رقم الهاتف': 'Phone Number',
    'رقم الواتساب': 'WhatsApp Number',
    'البريد الإلكتروني للمؤسسة': 'Organization Email',
    'العنوان': 'Address',
    'الرقم الضريبي / السجل التجاري': 'Tax ID / Commercial Register',
    'تذييل السندات والتقارير': 'Vouchers & Reports Footer',
    'العملة الافتراضية': 'Default Currency',
    'إدارة العملات وأسعار الصرف': 'Manage Currencies & Exchange Rates',
    'بادئة ترقيم السندات': 'Voucher Numbering Prefix',
    'حد تنبيه نقص المخزون': 'Low Stock Alert Threshold',
    'أيام قفل التدقيق المحاسبي': 'Audit Lock Days',
    'إشعار العميل بعد حفظ السند': 'Notify Customer After Saving Voucher',
    'نقطة البيع العائمة (فقاعة فوق التطبيقات)':
        'Floating POS (Bubble Over Apps)',
    'إظهار التذييل في السندات': 'Show Footer in Vouchers',
    'ختم وتوقيع السندات PDF': 'Stamp & Sign PDF Vouchers',
    'الأصوات التفاعلية': 'Interactive Sounds',
    'الاهتزاز اللمسي': 'Haptic Vibration',
    'قفل التطبيق والبيومتري': 'App Lock & Biometrics',
    'فحص التحديثات': 'Check for Updates',
    'إعادة ضبط المصنع': 'Factory Reset',
    'البيانات والأدوات': 'Data & Tools',
    'النظام': 'System',
    'المبيعات والمخزون': 'Sales & Inventory',
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
