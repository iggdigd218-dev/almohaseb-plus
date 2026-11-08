import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sfx.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/sync/cloud_sync_engine.dart';
import '../../data/sync/realtime_Waiter.dart';
import '../../data/sync/sync_activity_bus.dart';
import '../../data/sync/sync_Audit_page.dart';

/// مؤشر المزامنة السحابية في الشريط العلوي:
/// - دائرة مكونة من قوسين متناظرين برأسين متعاكسين في الموقع يتبعان بعضهما
///   في مسار دائري واحد مع عقارب الساعة وبدون أي إطار أو خلفية.
/// - ألوان فاتحة وزاهية ومبهجة تعبّر عن حالات المزامنة بوضوح.
/// - حركة دوران سريعة وسلسة لمدة ثانية واحدة (1s) عند الضغط لفحص المزامنة،
///   وحركة دوران مترافقة مع نبضة (Scale pulse 1.0 → 1.22 → 1.0) عند استلام
///   عملية سحابية أو نبضة مزامنة فعالة.
class SyncArrowsIndicator extends ConsumerStatefulWidget {
  const SyncArrowsIndicator({super.key});

  @override
  ConsumerState<SyncArrowsIndicator> createState() =>
      _SyncArrowsIndicatorState();
}

class _SyncArrowsIndicatorState extends ConsumerState<SyncArrowsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  StreamSubscription<SyncActivityItem>? _busSub;
  DateTime? _lastObservedPullAt;
  DateTime? _lastObservedPushAt;
  bool _wasSyncing = false;
  bool _pulseActive = false;
  int _turnsPerRun = 2;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _busSub = SyncActivityBus.instance.stream.listen((_) {
      if (!mounted) return;
      _triggerPulseSpin();
    });
  }

  @override
  void dispose() {
    _busSub?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  /// تشغيل دوران سريع لمدة ثانية واحدة عند الضغط اليدوي على الأيقونة.
  void _triggerTapSpin() {
    _pulseActive = false;
    _turnsPerRun = 2;
    _animCtrl.duration = const Duration(milliseconds: 1000);
    _animCtrl.forward(from: 0);
  }

  /// تشغيل دوران سريع مترافق مع نبضة انبساط وانقباض (1.0 -> 1.22 -> 1.0)
  /// عند استلام حركة جديدة من السحابة أو بدء نبضة مزامنة فعالة.
  void _triggerPulseSpin() {
    setState(() {
      _pulseActive = true;
      _turnsPerRun = 1;
    });
    _animCtrl.duration = const Duration(milliseconds: 900);
    _animCtrl.forward(from: 0);
  }

  void _checkStateTransitions(CloudSyncState s) {
    final nowSyncing = s.pushing || s.pulling;
    final newPull = s.lastPullAt != null &&
        s.lastPullAt != _lastObservedPullAt &&
        s.lastPullApplied > 0;
    final newPush = s.lastPushAt != null &&
        s.lastPushAt != _lastObservedPushAt &&
        s.lastPushCount > 0;

    if ((nowSyncing && !_wasSyncing) || newPull || newPush) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_animCtrl.isAnimating) {
          _triggerPulseSpin();
        }
      });
    }
    _wasSyncing = nowSyncing;
    _lastObservedPullAt = s.lastPullAt;
    _lastObservedPushAt = s.lastPushAt;
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceProvider);
    final engine = ref.watch(cloudSyncEngineProvider);

    if (!ws.linked) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<CloudSyncState>(
      valueListenable: engine.state,
      builder: (context, s, _) {
        _checkStateTransitions(s);
        final hasFault = s.hasFault;
        final Color upColor;
        final Color downColor;
        if (hasFault) {
          upColor = const Color(0xFFFF5252);
          downColor = const Color(0xFFFF5252);
        } else if (!s.hydrated || !s.running) {
          upColor = const Color(0xFFFFB300);
          downColor = const Color(0xFFFFCA28);
        } else {
          // درجات لونية فاتحة وزاهية ومبهجة وواضحة للعين
          upColor = s.pushing
              ? const Color(0xFF00E676)
              : const Color(0xFF10B981);
          downColor = s.pulling
              ? const Color(0xFF38BDF8)
              : const Color(0xFF0EA5E9);
        }

        final tip = _tooltipFor(s);
        return Tooltip(
          message: tip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Sfx.tap();
              _triggerTapSpin();
              unawaited(engine.reconcileAndSyncNow());
            },
            onLongPress: () {
              Sfx.tap();
              _showSyncDetailsSheet(context, engine, s);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              child: AnimatedBuilder(
                animation: _animCtrl,
                builder: (context, child) {
                  final t = Curves.easeInOutCubic.transform(_animCtrl.value);
                  final angle = t * 2 * math.pi * _turnsPerRun;
                  double scale = 1.0;
                  if (_pulseActive && _animCtrl.isAnimating) {
                    // نبضة ناعمة: 1.0 -> 1.22 -> 1.0 عبر منحنى جيبي سلس
                    scale = 1.0 + 0.22 * math.sin(_animCtrl.value * math.pi);
                  }
                  return Transform.scale(
                    scale: scale,
                    child: Transform.rotate(
                      angle: angle,
                      child: child,
                    ),
                  );
                },
                child: _ThinSyncCircle(
                  upColor: upColor,
                  downColor: downColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _tooltipFor(CloudSyncState s) {
    if (s.hasFault) {
      return 'تنبيه مزامنة — اضغط للمزامنة الفورية أو مطولاً للتفاصيل';
    }
    if (!s.hydrated) return 'جارٍ تهيئة المزامنة السحابية…';
    if (s.pushing && s.pulling) return 'يرسل ويستقبل التحديثات…';
    if (s.pushing) return 'يرسل التعديلات إلى السحابة…';
    if (s.pulling) return 'يستقبل تحديثات الفروع…';
    return 'متصل بالسحابة — اضغط لفحص المزامنة الآن (ومطولاً للسجل)';
  }

  void _showSyncDetailsSheet(
    BuildContext context,
    CloudSyncEngine engine,
    CloudSyncState s,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      s.hasFault
                          ? Icons.error_outline_rounded
                          : Icons.cloud_done_rounded,
                      color: s.hasFault
                          ? AppColors.dangerOf(ctx)
                          : AppColors.greenOf(ctx),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.hasFault
                            ? 'تنبيه في المزامنة السحابية'
                            : 'المزامنة السحابية نشطة',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _kv('آخر إرسال', _fmtTime(s.lastPushAt)),
                _kv('آخر استقبال', _fmtTime(s.lastPullAt)),
                if (s.lastError != null && s.lastError!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    s.lastError!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.dangerOf(ctx),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          openSyncAuditPage(context);
                        },
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('سجل المزامنة'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          RealtimeWaiter.instance.poke();
                          await engine.reconcileAndSyncNow();
                        },
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('مزامنة الآن'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$k: ',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return 'لم يتم بعد';
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }
}

/// دائرة المزامنة النحيفة: قوسان متناظران برأسين متعاكسين يتبعان بعضهما في
/// مسار دائري واحد مع عقارب الساعة بدون إطار ولا خلفية.
class _ThinSyncCircle extends StatelessWidget {
  final Color upColor;
  final Color downColor;

  const _ThinSyncCircle({
    required this.upColor,
    required this.downColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(
        painter: _ThinSyncCirclePainter(
          upColor: upColor,
          downColor: downColor,
        ),
      ),
    );
  }
}

class _ThinSyncCirclePainter extends CustomPainter {
  final Color upColor;
  final Color downColor;

  _ThinSyncCirclePainter({
    required this.upColor,
    required this.downColor,
  });

  static const double _kStroke = 1.5;
  // كل قوس يغطي حوالي 154 درجة (~2.68 راديان) مع فجوة متناظرة صغيرة بينهما
  static const double _kSweep = 2.68;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 1.8;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // القوس العلوي: يبدأ من الجهة اليسرى (-pi + 0.23) ويمتد مع عقارب الساعة
    // لينتهي برأس سهم في الجهة اليمنى العلوية (-0.23).
    const upStart = -math.pi + 0.23;
    _drawClockwiseArcArrow(
      canvas,
      rect: rect,
      center: center,
      radius: radius,
      start: upStart,
      sweep: _kSweep,
      color: upColor,
    );

    // القوس السفلي المقابل: يبدأ من الجهة اليمنى السفلية (+0.23) ويمتد مع
    // عقارب الساعة لينتهي برأس سهم في الجهة اليسرى السفلية (pi - 0.23).
    const downStart = 0.23;
    _drawClockwiseArcArrow(
      canvas,
      rect: rect,
      center: center,
      radius: radius,
      start: downStart,
      sweep: _kSweep,
      color: downColor,
    );
  }

  void _drawClockwiseArcArrow(
    Canvas canvas, {
    required Rect rect,
    required Offset center,
    required double radius,
    required double start,
    required double sweep,
    required Color color,
  }) {
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kStroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawArc(rect, start, sweep, false, arcPaint);

    // رأس السهم في نهاية القوس باتجاه الدوران (مع عقارب الساعة)
    final tipAngle = start + sweep;
    final tip = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    // متجه المماس مع عقارب الساعة عند tipAngle هو tipAngle + pi/2،
    // لذا يعود جناحا السهم للخلف بزاوية tipAngle - pi/2 ± جناح.
    final backAngle = tipAngle - (math.pi / 2) - 0.14;
    const headLen = 3.6;
    const wingSpread = 0.56;

    final p1 = Offset(
      tip.dx + headLen * math.cos(backAngle - wingSpread),
      tip.dy + headLen * math.sin(backAngle - wingSpread),
    );
    final p2 = Offset(
      tip.dx + headLen * math.cos(backAngle + wingSpread),
      tip.dy + headLen * math.sin(backAngle + wingSpread),
    );

    final headPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(p2.dx, p2.dy);
    canvas.drawPath(headPath, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _ThinSyncCirclePainter old) =>
      old.upColor != upColor || old.downColor != downColor;
}
