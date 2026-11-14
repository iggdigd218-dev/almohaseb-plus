// كاشف/حلّال التعارضات الذكي — مبدأ Last-Write-Wins (اعتماد الأحدث وحذف القديم).
// يضمن استمرار المزامنة بدون توقف وحسم أي تفاوت بين الأجهزة تلقائياً وحتمياً.
import 'operation.dart';

class ConflictResolver {
  /// يقرر هل تُطبَّق العملية الواردة على الكيان المحلي (`true` = تطبيق، `false` = تجاهل)
  /// وفق مبدأ الحسم الذكي Last-Write-Wins (اعتماد الأحدث وحذف القديم).
  bool decide({
    required SyncOperation incoming,
    required bool exists,
    required int localVersion,
    required SyncOperation? localLatest,
  }) {
    // 1. Idempotency: نفس العملية برقمها مسجلة محلياً -> تجاهل مكرر
    if (localLatest != null && localLatest.id == incoming.id) {
      return false;
    }

    // 2. الكيان غير موجود محلياً
    if (!exists) {
      if (incoming.opType == OpKind.create) {
        return true;
      }
      if (incoming.opType == OpKind.delete_) {
        // حذف لكيان غير موجود أصلاً -> تجاهل آمن دون توقف
        return false;
      }
      // عملية تعديل لكيان غير موجود: إن توفرت بيانات كافية ننشئه محلياً (اعتماد الأحدث)
      return incoming.payload.isNotEmpty;
    }

    // 3. الكيان موجود محلياً: الحسم الموحّد والحتمي المتطابق مع استعلام SQLite (S2):
    // الترتيب القياسي الموحّد لكسر التعادل:
    // (أ) وقت الخادم server_time إن وجد، وإلا الطابع الزمني للعملية (timestamp / deviceTime).
    // (ب) الطابع الزمني المحلي timestamp في حال تعادل server_time.
    // (ج) رقم الإصدار (version).
    // (د) معرف العملية / الجهاز لكسر التعادل الحتمي.
    final inServerMs = incoming.serverTimeMs;
    final locServerMs = localLatest?.serverTimeMs ?? 0;

    final inEffectiveMs = inServerMs > 0
        ? inServerMs
        : (DateTime.tryParse(incoming.timestamp)?.millisecondsSinceEpoch ??
            (DateTime.tryParse(incoming.deviceTime)?.millisecondsSinceEpoch ??
                0));
    final locEffectiveMs = locServerMs > 0
        ? locServerMs
        : (DateTime.tryParse(localLatest?.timestamp ?? '')
                ?.millisecondsSinceEpoch ??
            (DateTime.tryParse(localLatest?.deviceTime ?? '')
                    ?.millisecondsSinceEpoch ??
                0));

    if (inServerMs > 0 && locServerMs > 0 && inServerMs != locServerMs) {
      return inServerMs > locServerMs;
    }
    if (inEffectiveMs != locEffectiveMs) {
      return inEffectiveMs > locEffectiveMs;
    }

    final inTsMs =
        DateTime.tryParse(incoming.timestamp)?.millisecondsSinceEpoch ?? 0;
    final locTsMs =
        DateTime.tryParse(localLatest?.timestamp ?? '')
                ?.millisecondsSinceEpoch ??
            0;
    if (inTsMs != locTsMs) {
      return inTsMs > locTsMs;
    }

    if (incoming.version != localVersion) {
      return incoming.version > localVersion;
    }

    final localId = localLatest?.id ?? '';
    if (localId.isNotEmpty && incoming.id != localId) {
      return incoming.id.compareTo(localId) > 0;
    }
    final localDevId = localLatest?.deviceId ?? '';
    if (localDevId.isNotEmpty && localDevId == incoming.deviceId) {
      return true;
    }
    return incoming.deviceId.compareTo(localDevId) <= 0;
  }
}
