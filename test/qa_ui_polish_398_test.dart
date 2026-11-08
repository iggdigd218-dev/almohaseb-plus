import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// (3.98.34) حزمة إعادة التصميم: تثبيت القرارات البصرية بقارئ مصدري
/// حتى لا تعود الأزرار العائمة أو التبويبات الأفقية أو تكرار بطاقات المظهر.
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// كل ملفات واجهة المستخدم (بلا ملفات الثيم/الأدوات المشتركة).
  List<File> uiFiles() => Directory('lib/ui')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  group('UI-POLISH — حزمة 3.98.34', () {
    test('UI-01 لا يوجد أي FloatingActionButton في الواجهة', () {
      final offenders = uiFiles()
          .where((f) => read(f.path).contains('FloatingActionButton'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: 'أزرار عائمة متبقية: $offenders');
    });

    test('UI-02 الإعدادات قائمة صفحات بلا تبويبات أفقية', () {
      final s = read('lib/ui/settings_screen.dart');
      expect(s, isNot(contains('DefaultTabController')));
      expect(s, isNot(contains('TabBarView')));
      expect(s, isNot(contains('TabBar(')));
      expect(s, contains('class _SettingsHome'));
      for (final title in const [
        'بيانات المؤسسة',
        'الفواتير والبيع',
        'المظهر والأصوات',
        'الأمان',
        'النظام والمزامنة',
      ]) {
        expect(s, contains(title), reason: 'قسم مفقود: $title');
      }
    });

    test('UI-03 بطاقات المظهر غير مكرّرة في الإعدادات', () {
      final s = read('lib/ui/settings_screen.dart');
      expect(s, isNot(contains('ThemeModeSelectorCard')));
      expect(read('lib/ui/appearance_screen.dart'),
          contains('ThemeModeSelectorCard'));
    });

    test('UI-04 شبكة المنتجات ثلاثة أعمدة على الهاتف', () {
      final s = read('lib/ui/inventory_screen.dart');
      expect(s, contains('w >= 900 ? 5 : (w >= 600 ? 4 : 3)'));
    });

    test('UI-05 دائرة المزامنة بلا إطار وسماكة 1.5', () {
      final s = read('lib/ui/widgets/sync_arrows_indicator.dart');
      expect(s, contains('_kStroke = 1.5'));
      expect(s, isNot(contains('Border.all')));
      expect(s, isNot(contains('BoxDecoration')));
    });

    test('UI-06 بطاقة العملات مقلّصة إلى 156', () {
      expect(read('lib/ui/dashboard_screen.dart'), contains('height: 156'));
    });

    test('UI-07 زر حفظ المنتج ثابت خارج منطقة التمرير', () {
      final s = read('lib/ui/inventory_screen.dart');
      expect(s, contains('SingleChildScrollView'));
      // (3.98.35) حشو ثابت: showDialog يرفع النافذة فوق الكيبورد بنفسه،
      // فإضافة viewInsets داخل البطاقة تُنتج فراغاً أبيض أسفل زر الحفظ.
      expect(s, contains('EdgeInsets.fromLTRB(12, 8, 12, 10)'));
      expect(s, isNot(contains('8 + MediaQuery.viewInsetsOf(context).bottom')));
    });

    test('UI-08 قائمة النواقص صفحة Scaffold مستقلة', () {
      final s = read('lib/ui/inventory_screen.dart');
      expect(s, contains('Future<void> openShortagesListSheet'));
      expect(s, contains('MaterialPageRoute'));
      expect(s, contains('fullPage'));
    });

    test('UI-09 تنظيف محارف التصدير غير المدعومة', () {
      final s = read('lib/core/pdf_fonts.dart');
      expect(s, contains(r'\u2370')); // ⍰
      expect(s, contains(r'\uFFFD'));
      expect(s, contains(r'\uE000'));
      expect(s, contains(r'\u{10000}-\u{10FFFF}'));
    });

    test('UI-10 إشعار إكمال البيانات كل يومين كحد أقصى', () {
      final s = read('lib/ui/widgets/profile_completion_nudge.dart');
      expect(s, contains("prefsKey = 'profileNudge.lastShownAt'"));
      expect(s, contains('Duration(days: 2)'));
      expect(s, contains('إكمال الآن'));
      expect(s, contains('لاحقاً'));
    });

    test('UI-11 قالب إدخال مدمج موحّد في الثيم', () {
      final s = read('lib/core/theme.dart');
      expect(s, contains('insetPadding'));
      expect(s, contains('minWidth: 36'));
    });
  });
}
