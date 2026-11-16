// QA — (3.98.56) تشخيص فشل إنشاء كود الدعوة على جهاز المالك.
//
// العطل المُبلَّغ: عند محاولة إنشاء كود دعوة للأعضاء على **جهاز مدير
// المنشأة** تظهر نافذة «حدث خطأ — ليس لديك الصلاحية لتنفيذ هذا الإجراء،
// يرجى مراجعة مدير النظام». المدير مالك المنشأة، فالبحث عن صلاحية مفقودة
// عبث: السبب الحقيقي واحد من ثلاثة لا علاقة لأي منها بصلاحيات المستخدم:
//
//   ١) لا هوية سحابية فعّالة على الجهاز ⇒ الطلب يُرسل بلا `?auth` ⇒ RTDB
//      يرد 401 (قواعد `auth != null`).
//   ٢) هوية منتهية/مُلغاة ⇒ 401 بعد إعادة المحاولة.
//   ٣) قواعد Firebase Realtime Database لم تُنشر على المشروع ⇒ 403.
//
// وكان `AppErrorMapper` يبتلع كل ما سبق في رسالة «راجع مدير النظام».
//
// العقد بعد الإصلاح:
//  1. رفض السحابة (401/403) يُترجم إلى رسالة سحابية تشخيصية، لا إلى
//     «ليس لديك الصلاحية». 401 (هوية) و403 (قواعد) يُفرَّق بينهما.
//  2. نقص صلاحية حقيقي (`permission denied` من طبقة أخرى بلا سياق سحابي)
//     يبقى يُترجم إلى «ليس لديك الصلاحية» — لم يُكسر السلوك القديم الصحيح.
//  3. `createInvite` يفشل مبكراً برسالة واضحة حين لا توجد هوية سحابية،
//     بدل إرسال طلب عارٍ يُترجم إلى رسالة صلاحيات خاطئة.
//  4. العقدة التشخيصية `_probe` مصرّح بها في ملفَّي قواعد Firebase، حتى لا
//     يكون الفحص التشخيصي نفسه سبباً لرفض 403.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexora_app/core/app_error_mapper.dart';
import 'package:nexora_app/core/database.dart';
import 'package:nexora_app/data/repository.dart';
import 'package:nexora_app/data/sync/cloud_join.dart';
import 'package:nexora_app/data/sync/firebase_auth_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// سحابة وهمية ترفض الكتابة بكود محدد (401/403) لمحاكاة قواعد RTDB.
class _RejectingCloud {
  _RejectingCloud(this.statusCode);
  final int statusCode;
  final List<String> puts = [];

  static http.Response _json(String body, int status) =>
      http.Response.bytes(utf8.encode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  http.Client client() => MockClient((req) async {
        if (req.method == 'POST') {
          // Identity Toolkit / securetoken: هوية صالحة حتى نصل للكتابة.
          if (req.url.host.contains('securetoken')) {
            return _json('{"id_token":"TOK-QA","refresh_token":"REF-QA",'
                '"expires_in":"3600","user_id":"UID-QA"}', 200);
          }
          return _json('{"idToken":"TOK-QA","refreshToken":"REF-QA",'
              '"expiresIn":"3600","localId":"UID-QA"}', 200);
        }
        if (req.method == 'PUT' || req.method == 'PATCH') {
          puts.add(req.url.path);
          return _json('{"error":"Permission denied"}', statusCode);
        }
        if (req.method == 'DELETE') return _json('null', 200);
        return _json('null', 200);
      });
}

const _url = 'https://qa-invite-perm.firebaseio.com';
const _ws = 'WS-QA-INVITE-PERM';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // ── ١) ترجمة الأخطاء: السحابة ليست «صلاحية مستخدم» ─────────────────────
  group('INV-PERM-01 ترجمة رفض السحابة في AppErrorMapper', () {
    test('403 من RTDB يُشرح كقواعد غير منشورة لا كصلاحية مفقودة', () {
      final msg = AppErrorMapper.toUserFriendlyMessage(
          StateError('cloud-auth-failed: 403'));
      expect(msg, isNot(contains('ليس لديك الصلاحية')),
          reason: 'المالك ليس ناقص الصلاحية — القواعد هي المشكلة');
      expect(msg, contains('403'));
      expect(msg, contains('قواعد'));
    });

    test('401 من RTDB يُشرح كهوية منتهية تحتاج تسجيل دخول', () {
      final msg = AppErrorMapper.toUserFriendlyMessage(
          StateError('cloud-auth-failed: 401'));
      expect(msg, isNot(contains('ليس لديك الصلاحية')));
      expect(msg, contains('401'));
      expect(msg, contains('Google'));
    });

    test('رسائل CloudJoin العربية للرفض لا تُترجم إلى صلاحية', () {
      final msg = AppErrorMapper.toUserFriendlyMessage(
          'فشل الرفع إلى السحابة: المصادقة مرفوضة (HTTP 403).');
      expect(msg, isNot(contains('ليس لديك الصلاحية')));
      expect(msg, contains('403'));
    });

    test('نقص صلاحية حقيقي من طبقة داخلية يبقى كما هو', () {
      expect(
        AppErrorMapper.toUserFriendlyMessage('permission denied for table tx'),
        AppErrorMapper.permissionDeniedMessage,
      );
    });

    test('رسالة السحابة العامة موجودة ومفيدة', () {
      expect(AppErrorMapper.cloudAuthRejectedMessage, contains('Google'));
      expect(AppErrorMapper.cloudAuthRejectedMessage,
          isNot(contains('ليس لديك الصلاحية')));
    });
  });

  // ── ٢) createInvite يفشل مبكراً برسالة صحيحة ───────────────────────────
  group('INV-PERM-02 إنشاء الدعوة على جهاز المالك', () {
    late Directory tmp;
    late Database db;
    late Repo repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('nexora_invite_perm_');
      db = await databaseFactory.openDatabase('${tmp.path}/i.db',
          options: OpenDatabaseOptions(
              onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON')));
      await AppDatabase.createSchema(db);
      repo = Repo(databaseProvider: () async => db);
      await repo.initSyncInfra();
      await repo.setSetting('cloudBackendUrl', _url);
      await db.delete('workspaces');
      await db.insert('workspaces', {
        'id': _ws,
        'name': 'منشأة التحقق',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await repo.setSetting('sync.workspaceId', _ws);
      await repo.refreshWorkspaceId();
    });

    tearDown(() async {
      FirebaseAuthRest.clearMockForTest();
      await db.close();
      await tmp.delete(recursive: true);
    });

    test('403 من السحابة يعطي رسالة قواعد واضحة بلا ذكر «صلاحية»', () async {
      FirebaseAuthRest.setMockTokenForTest();
      final cloud = _RejectingCloud(403);
      await expectLater(
        http.runWithClient(() => CloudJoin.createInvite(repo), cloud.client),
        throwsA(isA<CloudJoinException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('403'),
            contains('قواعد'),
            isNot(contains('ليس لديك الصلاحية')),
            isNot(contains('مراجعة مدير النظام')),
          ),
        )),
      );
      // الفحص التشخيصي نفسه جرى قبل أي كتابة حقيقية للدعوة.
      expect(cloud.puts.any((p) => p.contains('/_probe/')), isTrue,
          reason: 'يجب فحص صلاحية الكتابة قبل توليد الرمز');
      expect(cloud.puts.any((p) => p.contains('/invites/')), isFalse,
          reason: 'لا تُكتب دعوة أبداً على مساحة ترفض الكتابة');
    });

    test('401 من السحابة يعطي رسالة هوية منتهية لا صلاحية', () async {
      FirebaseAuthRest.setMockTokenForTest();
      final cloud = _RejectingCloud(401);
      await expectLater(
        http.runWithClient(() => CloudJoin.createInvite(repo), cloud.client),
        throwsA(isA<CloudJoinException>().having(
          (e) => e.message,
          'message',
          allOf(contains('401'), isNot(contains('ليس لديك'))),
        )),
      );
    });
  });

  // ── ٣) العقدة التشخيصية مصرّح بها في القواعد المنشورة ──────────────────
  group('INV-PERM-03 قواعد Firebase تحوي عقدة الفحص _probe', () {
    for (final path in const [
      'firebase/database.rules.json',
      'firebase/rules.license-hardened.json',
    ]) {
      test('INV-PERM-03 $path يسمح بكتابة _probe داخل مساحة العمل', () {
        final rules = jsonDecode(File(path).readAsStringSync()) as Map;
        final ws = rules['rules']['workspaces'][r'$ws'] as Map;
        expect(ws.containsKey('_probe'), isTrue,
            reason: 'الفحص التشخيصي يحتاج عقدة مصرّحاً بها وإلا صار 403 بنفسه');
        final probe = ws['_probe'] as Map;
        expect('${probe['.write']}', isNot(isEmpty));
        // نفس شرط الكتابة المعتمد لبقية عقد المساحة (ملكية/email/عضوية).
        expect('${probe['.write']}', contains('auth != null'));
      });
    }
  });
}
