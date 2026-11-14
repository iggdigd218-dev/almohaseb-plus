import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../core/item_conflict.dart';
import '../backup_engine.dart';
import '../repository.dart';
import 'apply_remote.dart';
import 'operation.dart';
import 'subscription_guard.dart';
import 'sync_engine.dart';

/// معاينة الأضرار والعمليات القابلة للاسترجاع في كتالوج الأصناف قبل التنفيذ.
class RecoveryPreview {
  final int autoMergeMovesCount;
  final int affectedCanonicalItemsCount;
  final int softDeletedItemsCount;
  final int recoverableHardDeletedItemsCount;
  final List<String> mergedConflictKeys;
  final List<String> sampleItemNames;

  const RecoveryPreview({
    required this.autoMergeMovesCount,
    required this.affectedCanonicalItemsCount,
    required this.softDeletedItemsCount,
    required this.recoverableHardDeletedItemsCount,
    required this.mergedConflictKeys,
    required this.sampleItemNames,
  });

  bool get hasRecoverableIssues =>
      autoMergeMovesCount > 0 ||
      softDeletedItemsCount > 0 ||
      recoverableHardDeletedItemsCount > 0 ||
      mergedConflictKeys.isNotEmpty;

  int get totalRecoverableCount =>
      autoMergeMovesCount +
      softDeletedItemsCount +
      recoverableHardDeletedItemsCount;
}

/// نتيجة تنفيذ استرجاع الأصناف أو فك الدمج التلقائي.
class CatalogRecoveryResult {
  final int restoredItems;
  final int revertedQtyMoves;
  final int resetConflicts;
  final int restoredSections;
  final int restoredCategories;
  final int queuedSyncOps;
  final String safetyBackupPath;

  const CatalogRecoveryResult({
    required this.restoredItems,
    required this.revertedQtyMoves,
    required this.resetConflicts,
    this.restoredSections = 0,
    this.restoredCategories = 0,
    required this.queuedSyncOps,
    required this.safetyBackupPath,
  });
}

/// خدمة استرجاع كتالوج الأصناف وإلغاء عمليات الدمج التلقائي (للمالك فقط).
///
/// مصممة لاستعادة الأصناف المفقودة أو المدمجة تلقائياً أو المحذوفة أثناء
/// تعارضات الانضمام السابقة، مع الحفاظ التام على جميع الفواتير والقيود
/// المحاسبية والعمليات المسجلة بعد الانضمام.
class CatalogRecoveryService {
  CatalogRecoveryService._();

  static final RegExp _conflictSuffixRegex = RegExp(
    r'\s*\((?:محلي|مؤرشف|مستقل|محذوف)\s+\d+(?:_\d+)?\)\s*$',
  );

  static String _stripConflictSuffix(String name) {
    return name.replaceAll(_conflictSuffixRegex, '').trim();
  }

  static Future<void> _ensureOwnerOrStandalone(Repo repo) async {
    final isOwner = await repo.isWorkspaceOwner();
    final mode = await repo.workspaceMode();
    if (!isOwner && mode != 'standalone') {
      throw StateError(
        'استرجاع الأصناف وإلغاء الدمج متاح حصراً لمدير المنشأة (المالك).',
      );
    }
  }

  static Future<String> _createSafeSnapshotIfFileBacked(Repo repo) async {
    try {
      final db = await repo.database;
      final path = db.path;
      if (path.isEmpty ||
          path == ':memory:' ||
          path.contains('in_memory')) {
        return '';
      }
      final file = await BackupEngine.createSafetySnapshotBeforeRestore(repo);
      return file.path;
    } catch (_) {
      return '';
    }
  }

  /// فحص الأضرار التاريخية في قاعدة البيانات المحلية وعرض ملخص قبل الاسترجاع.
  static Future<RecoveryPreview> previewRecovery(Repo repo) async {
    final db = await repo.database;

    final mergeMoves = await db.rawQuery('''
      SELECT id, item_id, quantity, notes
      FROM stock_moves
      WHERE COALESCE(deleted_at, '') = ''
        AND (
          notes LIKE 'تسوية تلقائية لدمج رصيد صنف مكرر%'
          OR notes LIKE 'دمج رصيد الصنف المكرر%'
        )
    ''');

    final affectedCanonIds = <int>{};
    for (final m in mergeMoves) {
      final id = (m['item_id'] as num?)?.toInt();
      if (id != null && id > 0) affectedCanonIds.add(id);
    }

    final softDeletedRows = await db.rawQuery('''
      SELECT id, name
      FROM items
      WHERE COALESCE(is_deleted, 0) = 1 OR COALESCE(deleted_at, '') != ''
    ''');
    final existingIds = <int>{};
    final allItemIdRows = await db.query('items', columns: ['id']);
    for (final r in allItemIdRows) {
      final id = (r['id'] as num?)?.toInt();
      if (id != null) existingIds.add(id);
    }

    final recoverableHardIds = <int>{};
    final sampleNames = <String>[];
    void addSampleName(String n) {
      final clean = _stripConflictSuffix(n);
      if (clean.isEmpty) return;
      if (!sampleNames.contains(clean) && sampleNames.length < 12) {
        sampleNames.add(clean);
      }
    }

    for (final r in softDeletedRows) {
      addSampleName('${r['name'] ?? ''}');
    }

    // فحص سلة المهملات للأصناف المحذوفة
    try {
      final trashRows = await db.query(
        'trash',
        where: "store = 'items'",
        orderBy: 'id DESC',
      );
      for (final tr in trashRows) {
        try {
          final raw = '${tr['payload'] ?? ''}'.trim();
          if (raw.isEmpty) continue;
          final map = jsonDecode(raw);
          if (map is Map) {
            final id = (map['id'] as num?)?.toInt();
            if (id != null && id > 0 && !existingIds.contains(id)) {
              if (recoverableHardIds.add(id)) {
                addSampleName('${map['name'] ?? tr['label'] ?? ''}');
              }
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    // فحص سجل العمليات لاسترجاع الأصناف المحذوفة كلياً من جدول items
    try {
      final opRows = await db.query(
        'operations',
        columns: ['entity_id', 'op_type', 'payload'],
        where: "entity_type = 'item' AND op_type IN ('create', 'update', 'restore')",
        orderBy: 'rowid DESC',
      );
      for (final op in opRows) {
        try {
          final id = int.tryParse('${op['entity_id'] ?? ''}'.trim());
          if (id == null || id <= 0 || existingIds.contains(id)) continue;
          final map = jsonDecode('${op['payload'] ?? '{}'}');
          if (map is Map) {
            final name = '${map['name'] ?? ''}'.trim();
            if (name.isEmpty) continue;
            if (recoverableHardIds.add(id)) {
              addSampleName(name);
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    // فحص تعارضات الأصناف المحلولة بالدمج
    final mergedKeys = <String>[];
    try {
      final conflictRows = await db.query(
        'settings',
        where: "key LIKE 'item_conflict:%'",
      );
      for (final r in conflictRows) {
        final key = '${r['key'] ?? ''}'.trim();
        final raw = '${r['value'] ?? ''}'.trim();
        final c = OfflineItemConflict.tryParseJson(raw, fallbackKey: key);
        if (c != null &&
            c.resolution.trim().toLowerCase() == 'merged') {
          mergedKeys.add(c.key);
          addSampleName(c.item2Name);
        }
      }
    } catch (_) {}

    return RecoveryPreview(
      autoMergeMovesCount: mergeMoves.length,
      affectedCanonicalItemsCount: affectedCanonIds.length,
      softDeletedItemsCount: softDeletedRows.length,
      recoverableHardDeletedItemsCount: recoverableHardIds.length,
      mergedConflictKeys: mergedKeys,
      sampleItemNames: sampleNames,
    );
  }

  /// التراجع عن جميع عمليات الدمج التلقائي واسترجاع الأصناف المحذوفة ناعماً أو كلياً
  /// دون المساس بأي فواتير أو قيود أو حركات بيع/شراء لاحقة.
  static Future<CatalogRecoveryResult> undoAutoMerges(
    Repo repo, {
    bool syncToGroup = true,
  }) async {
    await _ensureOwnerOrStandalone(repo);
    final safetyPath = await _createSafeSnapshotIfFileBacked(repo);

    final db = await repo.database;
    final wsId = repo.requireWorkspaceId;
    final nowIso = DateTime.now().toIso8601String();

    var restoredItems = 0;
    var revertedQtyMoves = 0;
    var resetConflicts = 0;
    var queuedSyncOps = 0;
    final touchedItemIds = <int>{};
    final touchedSettingKeys = <String>[];

    await db.transaction((txn) async {
      // 1) إلغاء حركات الدمج التلقائي المصطنعة وعكس أثرها على رصيد الصنف المدمج فيه
      final mergeMoves = await txn.rawQuery('''
        SELECT id, item_id, kind, quantity, notes
        FROM stock_moves
        WHERE COALESCE(deleted_at, '') = ''
          AND (
            notes LIKE 'تسوية تلقائية لدمج رصيد صنف مكرر%'
            OR notes LIKE 'دمج رصيد الصنف المكرر%'
          )
      ''');

      final subtractByItemId = <int, double>{};
      for (final m in mergeMoves) {
        final moveId = (m['id'] as num?)?.toInt();
        final itemId = (m['item_id'] as num?)?.toInt();
        final qty = ((m['quantity'] as num?) ?? 0).toDouble();
        if (moveId != null && itemId != null && itemId > 0) {
          subtractByItemId[itemId] = (subtractByItemId[itemId] ?? 0.0) + qty;
          await txn.update(
            'stock_moves',
            {'deleted_at': nowIso},
            where: 'id = ?',
            whereArgs: [moveId],
          );
          revertedQtyMoves++;
          touchedItemIds.add(itemId);
        }
      }

      for (final entry in subtractByItemId.entries) {
        final rows = await txn.query(
          'items',
          columns: ['quantity'],
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final currentQty = ((rows.first['quantity'] as num?) ?? 0).toDouble();
          final updatedQty = currentQty - entry.value;
          await txn.update(
            'items',
            {'quantity': updatedQty, 'updated_at': nowIso},
            where: 'id = ?',
            whereArgs: [entry.key],
          );
        }
      }

      // 2) استرجاع الأصناف المحذوفة ناعماً وإزالة لواحق التكرار المصطنعة
      final softDeleted = await txn.rawQuery('''
        SELECT *
        FROM items
        WHERE COALESCE(is_deleted, 0) = 1 OR COALESCE(deleted_at, '') != ''
      ''');
      final existingIds = <int>{};
      for (final r in await txn.query('items', columns: ['id'])) {
        final id = (r['id'] as num?)?.toInt();
        if (id != null) existingIds.add(id);
      }

      for (final itemRow in softDeleted) {
        final id = (itemRow['id'] as num?)?.toInt();
        if (id == null) continue;
        final rawName = '${itemRow['name'] ?? ''}'.trim();
        final cleanedName = _stripConflictSuffix(rawName);
        await txn.update(
          'items',
          {
            if (cleanedName.isNotEmpty) 'name': cleanedName,
            'is_deleted': 0,
            'is_active': 1,
            'deleted_at': '',
            'updated_at': nowIso,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        // استعادة الحركات المخزنية التي أُغلقت مع الحذف التلقائي إن لم تكن دمجاً مصطنعاً
        await txn.rawUpdate('''
          UPDATE stock_moves
          SET deleted_at = ''
          WHERE item_id = ?
            AND COALESCE(deleted_at, '') != ''
            AND notes NOT LIKE 'تسوية تلقائية لدمج رصيد صنف مكرر%'
            AND notes NOT LIKE 'دمج رصيد الصنف المكرر%'
        ''', [id]);
        restoredItems++;
        touchedItemIds.add(id);
      }

      // 3) تنظيف أسماء الأصناف النشطة التي أُضيف لها لاحقة تعارض مصطنعة
      final suffixedActive = await txn.query(
        'items',
        columns: ['id', 'name'],
        where: "COALESCE(is_deleted, 0) = 0 AND COALESCE(deleted_at, '') = ''",
      );
      for (final r in suffixedActive) {
        final id = (r['id'] as num?)?.toInt();
        final name = '${r['name'] ?? ''}'.trim();
        if (id == null || !_conflictSuffixRegex.hasMatch(name)) continue;
        final clean = _stripConflictSuffix(name);
        if (clean.isNotEmpty) {
          await txn.update(
            'items',
            {'name': clean, 'updated_at': nowIso},
            where: 'id = ?',
            whereArgs: [id],
          );
          restoredItems++;
          touchedItemIds.add(id);
        }
      }

      // 4) استرجاع الأصناف المحذوفة نهائياً من السلة (trash) ثم من سجل العمليات (operations)
      final recoveredPayloads = <int, Map<String, Object?>>{};
      try {
        final trashRows = await txn.query(
          'trash',
          where: "store = 'items'",
          orderBy: 'id DESC',
        );
        for (final tr in trashRows) {
          try {
            final raw = '${tr['payload'] ?? ''}'.trim();
            if (raw.isEmpty) continue;
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              final map = Map<String, Object?>.from(decoded);
              final id = (map['id'] as num?)?.toInt();
              if (id != null &&
                  id > 0 &&
                  !existingIds.contains(id) &&
                  !recoveredPayloads.containsKey(id)) {
                recoveredPayloads[id] = map;
              }
            }
          } catch (_) {}
        }
      } catch (_) {}

      try {
        final opRows = await txn.query(
          'operations',
          columns: ['entity_id', 'payload'],
          where:
              "entity_type = 'item' AND op_type IN ('create', 'update', 'restore')",
          orderBy: 'rowid DESC',
        );
        for (final op in opRows) {
          try {
            final id = int.tryParse('${op['entity_id'] ?? ''}'.trim());
            if (id == null ||
                id <= 0 ||
                existingIds.contains(id) ||
                recoveredPayloads.containsKey(id)) {
              continue;
            }
            final decoded = jsonDecode('${op['payload'] ?? '{}'}');
            if (decoded is Map) {
              final map = Map<String, Object?>.from(decoded);
              if ('${map['name'] ?? ''}'.trim().isNotEmpty) {
                recoveredPayloads[id] = map;
              }
            }
          } catch (_) {}
        }
      } catch (_) {}

      for (final entry in recoveredPayloads.entries) {
        final id = entry.key;
        final src = entry.value;
        final safeCatId = await _resolveValidCategoryId(
          txn,
          (src['category_id'] as num?)?.toInt(),
        );
        final safeSecId = await _resolveValidSectionId(
          txn,
          (src['section_id'] as num?)?.toInt(),
        );
        final cleanName = _stripConflictSuffix('${src['name'] ?? ''}');
        if (cleanName.isEmpty) continue;

        final row = <String, Object?>{
          'id': id,
          'workspace_id': wsId,
          'name': cleanName,
          'category_id': safeCatId,
          'section_id': safeSecId,
          'plu': (src['plu'] as num?)?.toInt() ?? id,
          'sku': '${src['sku'] ?? ''}'.trim(),
          'unit': '${src['unit'] ?? 'حبة'}'.trim().isEmpty
              ? 'حبة'
              : '${src['unit']}'.trim(),
          'buy_price': ((src['buy_price'] as num?) ?? 0).toDouble(),
          'sell_price': ((src['sell_price'] as num?) ?? 0).toDouble(),
          'quantity': ((src['quantity'] as num?) ?? 0).toDouble(),
          'min_quantity': ((src['min_quantity'] as num?) ?? 0).toDouble(),
          'currency': '${src['currency'] ?? 'YER'}'.trim().isEmpty
              ? 'YER'
              : '${src['currency']}'.trim(),
          'category': '${src['category'] ?? ''}',
          'notes': '${src['notes'] ?? ''}',
          'image': '${src['image'] ?? ''}',
          'archived': (src['archived'] as num?)?.toInt() ?? 0,
          'is_deleted': 0,
          'is_active': 1,
          'exclude_from_shortages':
              (src['exclude_from_shortages'] as num?)?.toInt() ?? 0,
          'deleted_at': '',
          'deleted_by': null,
          'restore_op_id': '${src['restore_op_id'] ?? ''}',
          'created_at': '${src['created_at'] ?? nowIso}'.trim().isEmpty
              ? nowIso
              : '${src['created_at']}',
          'updated_at': nowIso,
        };
        await txn.insert(
          'items',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        existingIds.add(id);
        restoredItems++;
        touchedItemIds.add(id);
      }

      // 5) إعادة ضبط سجلات التعارض المحلولة بالدمج إلى pending حتى تظهر للمدير منفصلة
      final conflictRows = await txn.query(
        'settings',
        where: "key LIKE 'item_conflict:%'",
      );
      for (final r in conflictRows) {
        final key = '${r['key'] ?? ''}'.trim();
        final raw = '${r['value'] ?? ''}'.trim();
        final parsed = OfflineItemConflict.tryParseJson(raw, fallbackKey: key);
        if (parsed != null &&
            parsed.resolution.trim().toLowerCase() == 'merged') {
          final reset = parsed.copyWith(
            status: 'resolved',
            resolution: 'keep_separate',
            resolvedAt: nowIso,
          );
          await txn.insert(
            'settings',
            {'key': reset.key, 'value': reset.toJson()},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          resetConflicts++;
          touchedSettingKeys.add(reset.key);
        }
      }

      await _advanceLastPlu(txn, wsId);

      // 6) جدولة عمليات المزامنة النظيفة للأجهزة التابعة عند الطلب
      if (syncToGroup &&
          (touchedItemIds.isNotEmpty || touchedSettingKeys.isNotEmpty)) {
        final rec = await repo.newRecorder(txn);
        for (final id in touchedItemIds) {
          final rows = await txn.query(
            'items',
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (rows.isEmpty) continue;
          final payload = Map<String, Object?>.from(rows.first)
            ..['id'] = id
            ..['__qty_changed'] = 1;
          await rec.record(
            entityType: EntityKind.item,
            entityId: '$id',
            opType: OpKind.update,
            payload: payload,
          );
          queuedSyncOps++;
        }
        for (final key in touchedSettingKeys) {
          final rows = await txn.query(
            'settings',
            columns: ['key', 'value'],
            where: 'key = ?',
            whereArgs: [key],
            limit: 1,
          );
          if (rows.isEmpty) continue;
          await rec.record(
            entityType: EntityKind.setting,
            entityId: key,
            opType: OpKind.settings,
            payload: {
              'key': key,
              'value': '${rows.first['value'] ?? ''}',
            },
          );
          queuedSyncOps++;
        }
      }
    });

    if (touchedItemIds.isNotEmpty || revertedQtyMoves > 0) {
      try {
        await ApplyRemoteOp.reconcileInventoryQuantities(db);
      } catch (_) {}
    }

    await repo.logActivity(
      'تراجع عن الدمج التلقائي واسترجاع الأصناف ($restoredItems صنف، $revertedQtyMoves تسوية)',
      'item',
      '',
    );

    return CatalogRecoveryResult(
      restoredItems: restoredItems,
      revertedQtyMoves: revertedQtyMoves,
      resetConflicts: resetConflicts,
      queuedSyncOps: queuedSyncOps,
      safetyBackupPath: safetyPath,
    );
  }

  /// استرجاع جراحي لكتالوج الأصناف والأقسام والفئات من نسخة احتياطية (.nexora أو JSON)
  /// دون المساس بأي فواتير أو حسابات أو قيود مسجلة بعد الانضمام.
  static Future<CatalogRecoveryResult> restoreCatalogFromBackup(
    Repo repo,
    File backupFile, {
    SyncEngine? engine,
    SubscriptionState? sub,
    bool syncToGroup = true,
  }) async {
    await _ensureOwnerOrStandalone(repo);

    if (!await backupFile.exists()) {
      throw const BackupRestoreException('ملف النسخة الاحتياطية غير موجود.');
    }
    final rawBytes = await backupFile.readAsBytes();
    const sqliteMagic = 'SQLite format 3\x00';
    final isRawSqlite = rawBytes.length >= sqliteMagic.length &&
        utf8.decode(rawBytes.take(16).toList(), allowMalformed: true) ==
            sqliteMagic;

    BackupInspectionResult? inspection;
    if (!isRawSqlite) {
      inspection = await BackupEngine.inspectBackupBytes(
        repo,
        rawBytes,
        engine: engine,
        sub: sub,
        enforceSyncGuard: false,
        allowCrossWorkspace: true,
      );
    }

    try {
      final sectionsList = <Map<String, Object?>>[];
      final categoriesList = <Map<String, Object?>>[];
      final itemsList = <Map<String, Object?>>[];

      final File? sqliteFile =
          isRawSqlite ? backupFile : inspection?.extractedDbFile;
      if (sqliteFile != null) {
        Database? srcDb;
        try {
          srcDb = await databaseFactory.openDatabase(
            sqliteFile.path,
            options: OpenDatabaseOptions(readOnly: true),
          );
          try {
            sectionsList.addAll(
              (await srcDb.query('sections')).map(Map<String, Object?>.from),
            );
          } catch (_) {}
          try {
            categoriesList.addAll(
              (await srcDb.query('item_categories'))
                  .map(Map<String, Object?>.from),
            );
          } catch (_) {}
          try {
            itemsList.addAll(
              (await srcDb.query('items')).map(Map<String, Object?>.from),
            );
          } catch (_) {}
        } finally {
          if (srcDb != null && srcDb.isOpen) {
            try {
              await srcDb.close();
            } catch (_) {}
          }
        }
      } else if (inspection?.legacyJsonPayload != null) {
        final root = inspection!.legacyJsonPayload!;
        final dataObj =
            root['data'] is Map ? Map<String, Object?>.from(root['data'] as Map) : root;
        for (final e in (dataObj['sections'] as List? ?? const [])) {
          if (e is Map) sectionsList.add(Map<String, Object?>.from(e));
        }
        for (final e in (dataObj['item_categories'] as List? ?? const [])) {
          if (e is Map) categoriesList.add(Map<String, Object?>.from(e));
        }
        for (final e in (dataObj['items'] as List? ?? const [])) {
          if (e is Map) itemsList.add(Map<String, Object?>.from(e));
        }
      }

      if (itemsList.isEmpty && categoriesList.isEmpty && sectionsList.isEmpty) {
        throw const BackupRestoreException(
          'النسخة الاحتياطية المختارة لا تحتوي على بيانات كتالوج أصناف قابلة للاسترجاع.',
        );
      }

      final safetyPath = await _createSafeSnapshotIfFileBacked(repo);
      final db = await repo.database;
      final wsId = repo.requireWorkspaceId;
      final nowIso = DateTime.now().toIso8601String();

      var restoredSections = 0;
      var restoredCategories = 0;
      var restoredItems = 0;
      var queuedSyncOps = 0;
      final touchedSectionIds = <int>[];
      final touchedCategoryIds = <int>[];
      final touchedItemIds = <int>[];

      await db.transaction((txn) async {
        // 1) استرجاع الأقسام غير المحذوفة في النسخة
        for (final s in sectionsList) {
          final id = (s['id'] as num?)?.toInt();
          final name = '${s['name'] ?? ''}'.trim();
          final deletedAt = '${s['deleted_at'] ?? ''}'.trim();
          if (id == null || id <= 0 || name.isEmpty || deletedAt.isNotEmpty) {
            continue;
          }
          await txn.insert(
            'sections',
            {
              'id': id,
              'workspace_id': wsId,
              'name': name,
              'icon': '${s['icon'] ?? ''}',
              'icon_key': '${s['icon_key'] ?? ''}',
              'color_hex': '${s['color_hex'] ?? ''}',
              'image_path': '${s['image_path'] ?? ''}',
              'sort_order': (s['sort_order'] as num?)?.toInt() ?? 0,
              'deleted_at': '',
              'created_at': '${s['created_at'] ?? nowIso}'.trim().isEmpty
                  ? nowIso
                  : '${s['created_at']}',
              'updated_at': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          restoredSections++;
          touchedSectionIds.add(id);
        }

        // 2) استرجاع فئات الأصناف (الجذور أولاً ثم الفرعية) مع تجنب تعارض الفهرس الفريد
        final activeCats = categoriesList.where((c) {
          final id = (c['id'] as num?)?.toInt() ?? 0;
          final name = '${c['name'] ?? ''}'.trim();
          final del = '${c['deleted_at'] ?? ''}'.trim();
          return id > 0 && name.isNotEmpty && del.isEmpty;
        }).toList()
          ..sort((a, b) {
            final pa = (a['parent_id'] as num?)?.toInt() ?? 0;
            final pb = (b['parent_id'] as num?)?.toInt() ?? 0;
            return pa.compareTo(pb);
          });

        for (final c in activeCats) {
          final id = (c['id'] as num?)!.toInt();
          final name = '${c['name'] ?? ''}'.trim();
          final rawParentId = (c['parent_id'] as num?)?.toInt();
          final safeParentId =
              await _resolveValidCategoryId(txn, rawParentId, excludeId: id);
          final safeSecId =
              await _resolveValidSectionId(txn, (c['section_id'] as num?)?.toInt());

          // إزالة تعارض الاسم تحت نفس الأب قبل الاستبدال إن كان منشأً أثناء التعارض
          final colliding = await txn.rawQuery('''
            SELECT id, name FROM item_categories
            WHERE COALESCE(parent_id, 0) = ?
              AND LOWER(name) = LOWER(?)
              AND id != ?
          ''', [safeParentId ?? 0, name, id]);
          for (final dup in colliding) {
            final dupId = (dup['id'] as num?)?.toInt();
            if (dupId != null) {
              await txn.update(
                'item_categories',
                {'name': '$name (مؤرشف $dupId)', 'updated_at': nowIso},
                where: 'id = ?',
                whereArgs: [dupId],
              );
            }
          }

          await txn.insert(
            'item_categories',
            {
              'id': id,
              'workspace_id': wsId,
              'name': name,
              'parent_id': safeParentId,
              'section_id': safeSecId,
              'icon_key': '${c['icon_key'] ?? ''}',
              'color_hex': '${c['color_hex'] ?? ''}',
              'image_path': '${c['image_path'] ?? ''}',
              'deleted_at': '',
              'deleted_by': null,
              'restore_op_id': '${c['restore_op_id'] ?? ''}',
              'created_at': '${c['created_at'] ?? nowIso}'.trim().isEmpty
                  ? nowIso
                  : '${c['created_at']}',
              'updated_at': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          restoredCategories++;
          touchedCategoryIds.add(id);
        }

        // 3) استرجاع الأصناف جراحياً دون المساس بالكميات الحالية للأصناف النشطة
        for (final it in itemsList) {
          final id = (it['id'] as num?)?.toInt();
          final name = '${it['name'] ?? ''}'.trim();
          final isDelFlag = (it['is_deleted'] as num?)?.toInt() == 1;
          final delAt = '${it['deleted_at'] ?? ''}'.trim();
          if (id == null || id <= 0 || name.isEmpty || isDelFlag || delAt.isNotEmpty) {
            continue;
          }

          final existing = await txn.query(
            'items',
            columns: ['id', 'quantity', 'is_deleted', 'deleted_at'],
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );

          final safeCatId =
              await _resolveValidCategoryId(txn, (it['category_id'] as num?)?.toInt());
          final safeSecId =
              await _resolveValidSectionId(txn, (it['section_id'] as num?)?.toInt());

          final backupQty = ((it['quantity'] as num?) ?? 0).toDouble();
          final wasExistingActive = existing.isNotEmpty &&
              ((existing.first['is_deleted'] as num?)?.toInt() ?? 0) == 0 &&
              '${existing.first['deleted_at'] ?? ''}'.trim().isEmpty;
          // إذا كان الصنف قائماً ونشطاً نحافظ على كميته الحالية بعد الفواتير اللاحقة،
          // أما إن كان محذوفاً أو مفقوداً فنستعيد كميته من النسخة.
          final preservedQty = wasExistingActive
              ? ((existing.first['quantity'] as num?) ?? backupQty).toDouble()
              : backupQty;

          final row = <String, Object?>{
            'id': id,
            'workspace_id': wsId,
            'name': name,
            'category_id': safeCatId,
            'section_id': safeSecId,
            'plu': (it['plu'] as num?)?.toInt() ?? id,
            'sku': '${it['sku'] ?? ''}'.trim(),
            'unit': '${it['unit'] ?? 'حبة'}'.trim().isEmpty
                ? 'حبة'
                : '${it['unit']}'.trim(),
            'buy_price': ((it['buy_price'] as num?) ?? 0).toDouble(),
            'sell_price': ((it['sell_price'] as num?) ?? 0).toDouble(),
            'quantity': preservedQty,
            'min_quantity': ((it['min_quantity'] as num?) ?? 0).toDouble(),
            'currency': '${it['currency'] ?? 'YER'}'.trim().isEmpty
                ? 'YER'
                : '${it['currency']}'.trim(),
            'category': '${it['category'] ?? ''}',
            'notes': '${it['notes'] ?? ''}',
            'image': '${it['image'] ?? ''}',
            'archived': (it['archived'] as num?)?.toInt() ?? 0,
            'is_deleted': 0,
            'is_active': 1,
            'exclude_from_shortages':
                (it['exclude_from_shortages'] as num?)?.toInt() ?? 0,
            'deleted_at': '',
            'deleted_by': null,
            'restore_op_id': '${it['restore_op_id'] ?? ''}',
            'created_at': '${it['created_at'] ?? nowIso}'.trim().isEmpty
                ? nowIso
                : '${it['created_at']}',
            'updated_at': nowIso,
          };

          await txn.insert(
            'items',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          restoredItems++;
          touchedItemIds.add(id);
        }

        await _advanceLastPlu(txn, wsId);

        if (syncToGroup) {
          final rec = await repo.newRecorder(txn);
          for (final id in touchedSectionIds) {
            final rows = await txn.query(
              'sections',
              where: 'id = ?',
              whereArgs: [id],
              limit: 1,
            );
            if (rows.isEmpty) continue;
            await rec.record(
              entityType: EntityKind.section,
              entityId: '$id',
              opType: OpKind.update,
              payload: Map<String, Object?>.from(rows.first),
            );
            queuedSyncOps++;
          }
          for (final id in touchedCategoryIds) {
            final rows = await txn.query(
              'item_categories',
              where: 'id = ?',
              whereArgs: [id],
              limit: 1,
            );
            if (rows.isEmpty) continue;
            await rec.record(
              entityType: EntityKind.itemCategory,
              entityId: '$id',
              opType: OpKind.update,
              payload: Map<String, Object?>.from(rows.first),
            );
            queuedSyncOps++;
          }
          for (final id in touchedItemIds) {
            final rows = await txn.query(
              'items',
              where: 'id = ?',
              whereArgs: [id],
              limit: 1,
            );
            if (rows.isEmpty) continue;
            final payload = Map<String, Object?>.from(rows.first)
              ..['id'] = id
              ..['__qty_changed'] = 1;
            await rec.record(
              entityType: EntityKind.item,
              entityId: '$id',
              opType: OpKind.update,
              payload: payload,
            );
            queuedSyncOps++;
          }
        }
      });

      await repo.logActivity(
        'استرجاع كتالوج الأصناف من نسخة احتياطية ($restoredItems صنف، $restoredCategories فئة، $restoredSections قسم) بدون مساس بالفواتير',
        'item',
        '',
      );

      return CatalogRecoveryResult(
        restoredItems: restoredItems,
        revertedQtyMoves: 0,
        resetConflicts: 0,
        restoredSections: restoredSections,
        restoredCategories: restoredCategories,
        queuedSyncOps: queuedSyncOps,
        safetyBackupPath: safetyPath,
      );
    } finally {
      await inspection?.dispose();
    }
  }

  static Future<int?> _resolveValidCategoryId(
    DatabaseExecutor txn,
    int? catId, {
    int? excludeId,
  }) async {
    if (catId == null || catId <= 0 || catId == excludeId) return null;
    final rows = await txn.query(
      'item_categories',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [catId],
      limit: 1,
    );
    return rows.isNotEmpty ? catId : null;
  }

  static Future<int?> _resolveValidSectionId(
    DatabaseExecutor txn,
    int? secId,
  ) async {
    if (secId == null || secId <= 0) return null;
    final rows = await txn.query(
      'sections',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [secId],
      limit: 1,
    );
    return rows.isNotEmpty ? secId : null;
  }

  static Future<void> _advanceLastPlu(DatabaseExecutor txn, String wsId) async {
    try {
      final maxRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(COALESCE(plu, id)), 0) AS mx FROM items',
      );
      final maxPlu = (maxRows.firstOrNull?['mx'] as num?)?.toInt() ?? 0;
      if (maxPlu <= 0) return;
      final existing = await txn.query(
        'sync_meta',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['last_plu:$wsId'],
        limit: 1,
      );
      final cur = existing.isNotEmpty
          ? (int.tryParse('${existing.first['value'] ?? '0'}') ?? 0)
          : 0;
      if (maxPlu > cur) {
        await txn.insert(
          'sync_meta',
          {'key': 'last_plu:$wsId', 'value': '$maxPlu'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (_) {}
  }
}
