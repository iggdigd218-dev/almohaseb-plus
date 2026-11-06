// انحدار: قاعدة بيانات ويندوز قديمة تحتوي جدول workspaces (وجداول مزامنة)
// لكن دون كل الجداول الأساسية يجب أن تُفتح دون خطأ
// "table workspaces already exists".
//
// يحاكي أيضًا سكربت المزامنة القديم (CREATE TABLE بدون IF NOT EXISTS) ويتحقق
// أن الطبقة المحصّنة execSchemaScript تتجاوز "already exists" ولا تنهار.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nexora_app/core/database.dart';
import 'package:nexora_app/data/sync/account_workspace.dart';
import 'package:nexora_app/data/sync/models.dart';
import 'package:nexora_app/data/sync/recorder.dart';
import 'package:nexora_app/data/sync/smart_support_recovery_service.dart';

void main() {
  test('فتح قاعدة فيها workspaces مسبقاً لا يرمي "already exists"', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('nexora_dbtest');
    final path = p.join(dir.path, 'nexora.db');

    // قاعدة قديمة فيها جداول المزامنة فقط بنسخة قديمة.
    var db = await factory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, v) async {
            await d.execute('''CREATE TABLE workspaces (
              id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
              owner_google_id TEXT DEFAULT '', owner_email TEXT DEFAULT '',
              owner_name TEXT DEFAULT '', created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL)''');
            await d.execute(
                'CREATE TABLE devices (id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL)');
          },
        ));
    await db.close();

    // أعد الفتح بنسخة أعلى: onUpgrade يشغّل createSchema (مسار الدفاع).
    final reopened = await factory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          onCreate: (d, v) => AppDatabase.createSchema(d),
          onUpgrade: (d, f, t) => AppDatabase.createSchema(d),
        ));
    final tables = await reopened
        .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final names = tables.map((e) => e['name'] as String).toSet();
    expect(names,
        containsAll(<String>['workspaces', 'accounts', 'settings', 'devices']));
    await reopened.close();
    await dir.delete(recursive: true);
  });

  test('انحدار ويندوز: سكربت CREATE غير محمي على جدول موجود لا ينهار', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) async {
          // جدول موجود مسبقًا بنفس الاسم.
          await d.execute(
              'CREATE TABLE workspaces (id TEXT PRIMARY KEY, name TEXT)');
        },
      ),
    );
    // سكربت على نمط البناء القديم (بدون IF NOT EXISTS).
    const oldStyle = '''
      CREATE TABLE workspaces (id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '');
      CREATE TABLE sync_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE INDEX idx_x ON sync_meta(key);
    ''';
    // يجب ألا يرمي: الطبقة المحصّنة تتجاوز "already exists".
    await AppDatabase.execSchemaScript(db, oldStyle);
    final tables =
        await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    expect(tables.map((e) => e['name']), contains('sync_meta'));
    // تشغيله مرة ثانية (idempotent) آمن أيضًا.
    await AppDatabase.execSchemaScript(db, oldStyle);
    await db.close();
  });

  test('انحدار ويندوز: ensureFullSchema يُصلح قاعدة فيها workspaces فقط',
      () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) async {
          // قاعدة تالفة: جدول المزامنة موجود فقط (شاشات الأعمال تفشل).
          await d.execute(
              'CREATE TABLE workspaces (id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT "", created_at TEXT NOT NULL, updated_at TEXT NOT NULL)');
        },
      ),
    );
    // تشغيل شبكة الأمان (كما في onOpen) يجب ألا يرمي وأن يُنشئ كل الجداول.
    await AppDatabase.ensureFullSchema(db);
    final tables = (await db
            .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((e) => e['name'] as String)
        .toSet();
    expect(
        tables,
        containsAll(<String>[
          'workspaces',
          'accounts',
          'items',
          'transactions',
          'settings',
          'currencies',
          'users',
          'devices',
          'operations',
          'sync_queue',
        ]));
    // البذرة الدنيا: العملات موجودة ولا تُكرَّر عند التشغيل ثانية.
    final c1 = (await db.rawQuery('SELECT COUNT(*) c FROM currencies'))
        .first['c'] as int;
    expect(c1, greaterThanOrEqualTo(3));
    await AppDatabase.ensureFullSchema(db);
    final c2 = (await db.rawQuery('SELECT COUNT(*) c FROM currencies'))
        .first['c'] as int;
    expect(c2, c1, reason: 'البذرة idempotent — لا تضاعف العملات');
    await db.close();
  });

  test('Auto-Heal في SyncRecorder يُنشئ جدولي operations و sync_queue تلقائياً عند فقدانهما',
      () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
    // قاعدة بيانات تخلو تماماً من جدول operations و sync_queue
    final recorder = SyncRecorder(
      () async => db,
      deviceIdLoader: () async => 'DEV-TEST-01',
      workspaceIdLoader: () async => 'ws_test_heal',
    );
    final op = await recorder.record(
      entity: EntityKind.account,
      entityId: 'acc_1',
      type: OpType.create,
      payload: const {'id': 'acc_1', 'name': 'عميل تجريبي'},
    );
    expect(op.entityId, 'acc_1');
    final ops = await db.query('operations');
    expect(ops.length, 1);
    await db.close();
  });

  test('توليد وفك تشفير حزمة استعادة كلمة المرور البرمجية (nexora-ai-rpc) بتوقيع SHA-256 صحيح',
      () {
    final packet = AccountWorkspace.buildEncryptedAiRecoveryPacket(
      phone: '0551234567',
      deviceId: 'DEVICE-ABCD1234',
      deviceFingerprint: 'FP-XYZ-987654',
      workspaceHint: 'ws_owner_1',
    );
    expect(packet, contains('nexora-ai-rpc'));
    expect(packet, contains('NEXORA_AI_CORE_RPC'));

    final verified =
        SmartSupportRecoveryService.decodeAndVerifyAiRecoveryPacket(packet);
    expect(verified, isNotNull);
    expect(verified!['verified_signature'], isTrue);
    expect(verified['phone_key'], '551234567');
    expect(verified['device_id'], 'DEVICE-ABCD1234');
    expect(verified['device_fingerprint'], 'FP-XYZ-987654');

    // التلاعب بالتوقيع يرفض الحزمة فوراً
    final tampered = packet.replaceFirst('"sig_sha256": "', '"sig_sha256": "0000');
    expect(
      SmartSupportRecoveryService.decodeAndVerifyAiRecoveryPacket(tampered),
      isNull,
    );
  });
}
