// (3.71.0) مؤشرا المزامنة اللحظيان (↑↓) — تصميم عريض ومصمت.
//
// الودجت: سهمان مدمجان في الشريط العلوي بجوار جرس الإشعارات مباشرة:
//  - أخضر/أزرق عند الاتصال والاستقرار
//  - وميض خفيف أثناء النقل الفعلي
//  - أحمر صريح عند وجود خلل في الإرسال أو الاستقبال
//  - عند الضغط: يبدأ دورة تحديث فورية ويظهر رسالة واضحة بحالة المزامنة أو تفاصيل العطل (دون نوافذ منبثقة).
//  - يختفي تلقائياً في الوضع الفردي المستقل (standalone).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sfx.dart';
import '../../data/providers.dart';
import '../../data/sync/sync_diagnostics.dart';
import '../dialogs/sync_resolution_dialog.dart';
import '../widgets.dart' show showSnack;

/// مؤشرا السهمين — يُثبَّت في الشريط العلوي بجوار الجرس.
class SyncArrowsIndicator extends ConsumerWidget {
  const SyncArrowsIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // الوضع الفردي المستقل أو المستخدم المحلي بدون حساب جوجل: لا سحابة ولا مزامنة — الودجت مخفي كلياً.
    final modeAsync = ref.watch(workspaceModeProvider);
    final mode = modeAsync.value ?? modeAsync.asData?.value;
    final st = ref.watch(settingsProvider).value ?? const <String, String>{};
    final googleLinked = ref.watch(googleLinkedProvider).value ?? false;
    final wsId = (st['sync.workspaceId'] ?? '').trim();
    final cloudProv = (st['cloudWorkspaceProvisioned'] ?? '0').trim();
    final isLocalIndividual = (st['account.type'] ?? '') == 'individual' ||
        cloudProv != '1' ||
        wsId == 'default' ||
        ((st['account.email'] ?? st['email'] ?? '').trim().isEmpty && !googleLinked);
    if (mode == 'standalone' ||
        isLocalIndividual ||
        (mode == null && !modeAsync.isLoading)) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<SyncDiagnosticsSnapshot>(
      valueListenable: SyncDiagnostics.instance.notifier,
      builder: (context, s, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final darkBase = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
        final hydrated = s.lastPullAt != null || s.lastPullApplied > 0;
        final upColor = s.uploadFaulted
            ? const Color(0xFFEF4444)
            : (s.pushing || (hydrated && (s.lastPushOk || (!s.uploadFaulted && s.failedCount == 0))))
                ? (isDark ? const Color(0xFF10B981) : const Color(0xFF065F46))
                : darkBase;
        final downColor = s.downloadFaulted
            ? const Color(0xFFEF4444)
            : (s.pulling || (hydrated && (s.lastPullOk || !s.downloadFaulted)))
                ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF075985))
                : darkBase;
        final tooltipMsg = s.catalogMismatch
            ? (s.catalogMismatchDetails ??
                '⚠️ تحذير: عدم تطابق في الحسابات أو الأصناف أو الأقسام بين الأجهزة')
            : (!hydrated ? 'بانتظار استكمال الجلب الأولي للبيانات...' : 'مؤشر المزامنة اللحظية');
        return Tooltip(
          message: tooltipMsg,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              Sfx.tap();
              try {
                // مزامنة فورية ذكية ومعالجة توفيقية للأحدث (Last-Write-Wins)
                await ref.read(syncEngineProvider).reconcileAndSyncNow();
              } catch (_) {}
              if (!context.mounted) return;

              final diag = SyncDiagnostics.instance.snapshot;
              final diagHydrated = diag.lastPullAt != null || diag.lastPullApplied > 0;
              final isNetworkFaultOnly = (diag.lastPushFault == SyncFaultSource.network ||
                      diag.lastPullFault == SyncFaultSource.network) &&
                  diag.lastLocalizedError == null &&
                  !diag.catalogMismatch &&
                  diag.failedCount == 0;

              if (diag.catalogMismatch ||
                  (diag.uploadFaulted && !isNetworkFaultOnly) ||
                  (diag.downloadFaulted && !isNetworkFaultOnly) ||
                  diag.failedCount > 0 ||
                  diag.lastLocalizedError != null) {
                SyncResolutionDialog.show(context);
              } else if (diag.pushing || diag.pulling || !diagHydrated) {
                showSnack(context, 'المزامنة السحابية جارية الآن...');
              } else if (isNetworkFaultOnly) {
                showSnack(context, 'تعذر الوصول للخادم السحابي مؤقتاً — ستتم المزامنة تلقائياً');
              } else {
                showSnack(context, 'المزامنة السحابية متصلة ومستقرة ✅');
              }
            },
            // (3.98.34) دائرة مزامنة نحيفة بلا إطار ولا خلفية — أيقونة صافية.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: _ThinSyncCircle(
                upColor: upColor,
                downColor: downColor,
                upActive: s.pushing && !s.uploadFaulted,
                downActive: s.pulling && !s.downloadFaulted,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// (3.98.34) دائرة مزامنة نحيفة: قوسان متقابلان بلا إطار يشكّلان معاً
/// دائرة تزامن، وكل قوس ينتهي برأس سهم صغير — بألوان الحالة الخاصة بكل اتجاه.
class _ThinSyncCircle extends StatelessWidget {
  final Color upColor;
  final Color downColor;
  final bool upActive;
  final bool downActive;

  const _ThinSyncCircle({
    required this.upColor,
    required this.downColor,
    required this.upActive,
    required this.downActive,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 22),
      painter: _ThinSyncCirclePainter(
        upColor: upColor,
        downColor: downColor,
        upOpacity: upActive ? 0.55 : 1.0,
        downOpacity: downActive ? 0.55 : 1.0,
      ),
    );
  }
}

/// يرسم قوسين متقابلين (كل منهما نصف دائرة تقريباً) برأس سهم في نهاية كل قوس.
class _ThinSyncCirclePainter extends CustomPainter {
  final Color upColor;
  final Color downColor;
  final double upOpacity;
  final double downOpacity;

  _ThinSyncCirclePainter({
    required this.upColor,
    required this.downColor,
    required this.upOpacity,
    required this.downOpacity,
  });

  static const double _kStroke = 1.5;
  static const double _kSweep = 2.42; // ≈ 139° لكل قوس
  static const double _kGap = 0.18; // فجوة صغيرة بين القوسين

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - (_kStroke / 2) - 0.5;

    Paint stroke(Color c, double o) => Paint()
      ..color = c.withValues(alpha: o)
      ..strokeWidth = _kStroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // القوس الأعلى (الإرسال ↑) — يمتد من اليسار العلوي إلى اليمين العلوي.
    const upStart = -2.55;
    _arcWithHead(
      canvas: canvas,
      center: center,
      radius: radius,
      startAngle: upStart,
      sweep: _kSweep,
      paint: stroke(upColor, upOpacity),
    );

    // القوس السفلي (الاستقبال ↓) — مقابل للأول ليكملا الدائرة.
    const downStart = upStart + _kSweep + _kGap;
    _arcWithHead(
      canvas: canvas,
      center: center,
      radius: radius,
      startAngle: downStart,
      sweep: _kSweep,
      paint: stroke(downColor, downOpacity),
      headAtStart: true,
    );
  }

  /// يرسم القوس ثم رأس سهم صغير عند نهايته (أو بدايته) باتجاه المماس.
  void _arcWithHead({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required double startAngle,
    required double sweep,
    required Paint paint,
    bool headAtStart = false,
  }) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, startAngle, sweep, false, paint);

    final endAngle = headAtStart ? startAngle : startAngle + sweep;
    final tangent = endAngle + (headAtStart ? -1.5708 : 1.5708);
    final tip = center + Offset(radius * _cos(endAngle), radius * _sin(endAngle));
    const wing = 3.0;
    const spread = 0.85;

    final p1 = tip -
        Offset(wing * _cos(tangent - spread), wing * _sin(tangent - spread));
    final p2 = tip -
        Offset(wing * _cos(tangent + spread), wing * _sin(tangent + spread));

    final head = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(p2.dx, p2.dy);
    canvas.drawPath(head, paint);
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(covariant _ThinSyncCirclePainter old) =>
      old.upColor != upColor ||
      old.downColor != downColor ||
      old.upOpacity != upOpacity ||
      old.downOpacity != downOpacity;
}

/// فتح نافذة تشخيص ومعالجة أخطاء وعمليات المزامنة.
Future<void> showSyncDiagnosticsSheet(BuildContext context) async {
  final diag = SyncDiagnostics.instance.snapshot;
  if (diag.catalogMismatch ||
      diag.uploadFaulted ||
      diag.downloadFaulted ||
      diag.failedCount > 0 ||
      diag.lastLocalizedError != null) {
    await SyncResolutionDialog.show(context);
  } else {
    showSnack(context, 'المزامنة السحابية متصلة ومستقرة ✅');
  }
}
