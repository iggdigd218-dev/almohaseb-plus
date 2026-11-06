// شاشة إعداد المنشأة الجديدة (CreateWorkspaceScreen) + نافذة إدارة المنشآت والتبديل بينها.
//
// تطبّق السيناريو الثاني من معالج فحص وتوجيه الحسابات (Workspace Resolver / Auth Gate):
//   • للمستخدم الجديد تماماً الذي لا يملك أي منشأة سابقة في السحابة:
//     يُمنع فتح أو ربط أي منشأة مخزنة مسبقاً على الهاتف، ويُوجَّه مباشرة لهذه الشاشة.
//   • الحقول الإجبارية (100%):
//     1) اسم المنشأة التجاري
//     2) رقم هاتف المالك
//     3) نوع النشاط التجاري
//     4) العملة الافتراضية
//   • بعد إكمال الحقول بنسبة 100%:
//     إنشاء workspaceId فريد جديد، تسجيلها في فايربيس باسم البريد،
//     إنشاء ملف SQLite جديد ونظيف كلياً (nexora_${workspaceId}.db)،
//     وإدخاله للنظام بحالة اشتراك غير مفعل (unactivated) حتى يتم الترخيص.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/accounting.dart';
import '../core/cloud_config.dart';
import '../core/sfx.dart';
import '../core/theme.dart';
import '../data/providers.dart';
import '../data/sync/account_workspace.dart';
import '../data/sync/device_id.dart';
import '../data/sync/firebase_auth_service.dart';
import '../data/sync/smart_support_recovery_service.dart';
import '../data/sync/subscription_guard.dart';
import 'home_shell.dart';
import 'lock_gate.dart';
import 'logout_flow.dart';
import 'onboarding_screen.dart' show kOnboardingDoneKey;
import 'widgets.dart';

class CreateWorkspaceScreen extends ConsumerStatefulWidget {
  final String ownerEmail;
  final String ownerUid;
  final String ownerDisplayName;
  final String initialPassword;
  final bool isAdditionalWorkspace;

  const CreateWorkspaceScreen({
    super.key,
    required this.ownerEmail,
    this.ownerUid = '',
    this.ownerDisplayName = '',
    this.initialPassword = '',
    this.isAdditionalWorkspace = false,
  });

  @override
  ConsumerState<CreateWorkspaceScreen> createState() =>
      _CreateWorkspaceScreenState();
}

class _CreateWorkspaceScreenState extends ConsumerState<CreateWorkspaceScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;
  final _storeNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _activityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  String _countryDialCode = '+967';
  String _currency = 'YER';
  bool _obscurePassword = true;
  bool _busy = false;
  String? _errorMsg;

  static const _dialCodes = <(String, String)>[
    ('+967', 'اليمن (+967)'),
    ('+966', 'السعودية (+966)'),
    ('+971', 'الإمارات (+971)'),
    ('+968', 'عُمان (+968)'),
    ('+965', 'الكويت (+965)'),
    ('+974', 'قطر (+974)'),
    ('+973', 'البحرين (+973)'),
    ('+20', 'مصر (+20)'),
    ('+962', 'الأردن (+962)'),
    ('+964', 'العراق (+964)'),
  ];

  static const _suggestedActivities = <String>[
    'مواد غذائية وتموينات',
    'تجارة عامة وجملة',
    'إلكترونيات وهواتف',
    'ملابس وأحذية',
    'مواد بناء وكهرباء',
    'صيدلية ومستلزمات طبية',
    'مطعم وكافيه',
    'قطع غيار وزيوت',
    'خدمات ومقاولات',
  ];

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.ownerEmail.trim());
    _passwordCtrl = TextEditingController(text: widget.initialPassword);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _storeNameCtrl.dispose();
    _phoneCtrl.dispose();
    _activityCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _errorMsg = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      Sfx.error();
      return;
    }

    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text.trim();
    final storeName = _storeNameCtrl.text.trim();
    final rawPhone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[^\d]'), '');
    final localDigits =
        rawPhone.startsWith('0') ? rawPhone.substring(1) : rawPhone;
    final fullPhone = '$_countryDialCode$localDigits';
    final activity = _activityCtrl.text.trim();
    final address = _addressCtrl.text.trim();

    setState(() => _busy = true);
    try {
      final repo = ref.read(repoProvider);
      final st = await repo.settings();
      final url = effectiveBackendUrl(st['cloudBackendUrl']);

      var effectiveUid = widget.ownerUid.trim().isNotEmpty
          ? widget.ownerUid.trim()
          : 'email:${AccountWorkspace.emailToKey(email)}';

      if (password.length >= 6 && widget.ownerUid.trim().isEmpty) {
        try {
          final authAcc = await FirebaseAuthRest.signUpWithEmailPassword(
            email: email,
            password: password,
            displayName: storeName,
          );
          if (authAcc.uid.trim().isNotEmpty) {
            effectiveUid = authAcc.uid.trim();
          }
        } catch (_) {}
      }

      if (!widget.isAdditionalWorkspace) {
        final localMatches = await AccountWorkspace.findLocalWorkspacesOnDevice(
          filterEmail: email,
        );
        if (localMatches.isNotEmpty) {
          final existingWs = localMatches.first.workspaceId;
          final existingName = localMatches.first.storeName;
          if (!mounted) return;
          setState(() {
            _busy = false;
            _errorMsg =
                'البريد الإلكتروني ($email) مسجل مسبقاً لمنشأة «$existingName» على هذا الجهاز.\nلا يُسمح بإنشاء حساب مكرر بنفس البريد الإلكتروني.';
          });
          final openExisting = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dctx) => AlertDialog(
              title: const Text('البريد مسجل مسبقاً',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              content: Text(
                'البريد الإلكتروني ($email) مرتبط بمنشأة سابقة معتمدة على هذا الجهاز باسم «$existingName».\n\n'
                'لا يُسمح بتكرار الحسابات أو إنشاء منشآت مكررة بنفس البريد. هل ترغب بفتح منشأتك السابقة؟',
                style: const TextStyle(fontSize: 13.5, height: 1.6),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dctx).pop(false),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(dctx).pop(true),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('فتح المنشأة السابقة'),
                ),
              ],
            ),
          );
          if (openExisting == true && mounted) {
            final restored = await AccountWorkspace.switchToExistingWorkspace(
              repo,
              backendUrl: url,
              targetWorkspaceId: existingWs,
            );
            if (restored) {
              await repo.setSetting('account.type', 'enterprise');
              await repo.setSetting(kOnboardingDoneKey, '1');
              await repo.setSetting('onboardingCompleted', '1');
              if (!mounted) return;
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (_) => const LockGate(child: HomeShell())),
                (route) => false,
              );
              return;
            }
          }
          return;
        }
      }

      if (!widget.isAdditionalWorkspace && url.isNotEmpty) {
        final devId = await ensureDeviceId(repo);
        final rawFp =
            await SubscriptionGuard.hardwareFingerprintRaw() ?? 'fallback:$devId';
        final hwFp = SubscriptionGuard.fingerprintHash(rawFp);

        final preCheck = await AccountWorkspace.resolveWorkspaceInCloud(
          backendUrl: url,
          email: email,
          uid: effectiveUid,
          deviceId: devId,
          deviceFingerprint: hwFp,
          phone: fullPhone,
        ).timeout(
          const Duration(seconds: 7),
          onTimeout: () => const CloudWorkspaceResolution.notFound(),
        );

        if (preCheck.found && preCheck.workspaceId.isNotEmpty) {
          final existingWs = preCheck.workspaceId;
          final existingName = (preCheck.meta?['storeName'] ??
                  preCheck.meta?['store_name'] ??
                  existingWs)
              .toString()
              .trim();
          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.shield_outlined,
                      color: Color(0xFF16A34A), size: 24),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'منشأة سابقة معتمدة',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              content: Text(
                'تم العثور على منشأتك السابقة المرتبطة بهذا الجهاز/البيانات باسم «$existingName».\n\n'
                'لحماية بياناتك المالية من التشتت، هل ترغب بفتح منشأتك المعتمدة بدلاً من إنشاء مساحة فارغة جديدة؟',
                style: const TextStyle(fontSize: 13.5, height: 1.6),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dctx).pop(false),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                  ),
                  onPressed: () => Navigator.of(dctx).pop(true),
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text('فتح المنشأة واستعادة البيانات'),
                ),
              ],
            ),
          );

          if (confirmed == true && mounted) {
            final restored = await AccountWorkspace.switchToExistingWorkspace(
              repo,
              backendUrl: url,
              targetWorkspaceId: existingWs,
            );
            if (restored) {
              await repo.setSetting('account.type', 'enterprise');
              await repo.setSetting(kOnboardingDoneKey, '1');
              await repo.setSetting('onboardingCompleted', '1');
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => const LockGate(child: HomeShell())),
                  (route) => false,
                );
              }
              return;
            }
          } else {
            if (mounted) {
              setState(() {
                _busy = false;
                _errorMsg =
                    'البريد الإلكتروني ($email) مسجل مسبقاً في السحابة لمنشأة «$existingName».\nلا يُسمح بإنشاء منشآت مكررة بنفس البريد الإلكتروني.';
              });
            }
            return;
          }
        }
      }

      await AccountWorkspace.createAndRegisterNewWorkspace(
        repo,
        backendUrl: url,
        storeName: storeName,
        phone: fullPhone,
        businessActivity: activity,
        defaultCurrency: _currency,
        address: address,
        emailOverride: email,
        uidOverride: effectiveUid,
        displayNameOverride: widget.ownerDisplayName,
        password: password,
        isAdditionalWorkspace: widget.isAdditionalWorkspace,
      );

      // إعادة تشغيل محرك المزامنة وتحديث كافة الـ Providers للمنشأة الجديدة المعزولة
      try {
        final engine = ref.read(syncEngineProvider);
        engine.stop();
        await engine.start();
        unawaited(engine.forceSyncNow());
      } catch (_) {}

      ref.invalidate(googleLinkedProvider);
      ref.invalidate(currentUserProvider);
      ref.invalidate(deviceRoleProvider);
      ref.invalidate(effectivePermissionsProvider);
      ref.invalidate(canManageGroupProvider);
      ref.invalidate(settingsProvider);
      ref.invalidate(isOwnerProvider);
      ref.invalidate(workspaceModeProvider);
      ref.invalidate(subscriptionProvider);
      bump(ref);

      Sfx.tap();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LockGate(child: HomeShell())),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      final cleanErr = '$e'.replaceFirst(RegExp(r'^(Bad state:\s*|Exception:\s*)'), '').trim();
      setState(() {
        _errorMsg = cleanErr.isNotEmpty ? cleanErr : 'تعذّر إنشاء المنشأة: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isAdditionalWorkspace
              ? 'إنشاء منشأة جديدة مستقلة'
              : 'إنشاء حساب وإعداد المنشأة الجديدة',
        ),
        actions: [
          if (!widget.isAdditionalWorkspace)
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final repo = ref.read(repoProvider);
                      await performCompleteSessionPurge(ref, repo);
                    },
              icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
              label: const Text(
                'تسجيل الخروج',
                style: TextStyle(color: Colors.redAccent, fontSize: 12.5),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.domain_add_rounded,
                                  color: primary, size: 28),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.isAdditionalWorkspace
                                      ? 'تأسيس منشأة إضافية بقاعدة بيانات معزولة'
                                      : 'مرحباً بك! يرجى إكمال بيانات حسابك ومنشأتك للبدء',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'سيتم إنشاء معرف منشأة فريد وقاعدة بيانات SQLite مستقلة ونظيفة كلياً، '
                            'وتسجيلها سحابياً باسم بريدك الإلكتروني بحالة اشتراك غير مفعل حتى يتم الترخيص.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.55,
                              color: AppColors.text2Of(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_errorMsg != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Text(
                          _errorMsg!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 0) البريد الإلكتروني للمالك (مُعبأ مسبقاً أو قابل للإدخال)
                    TextFormField(
                      controller: _emailCtrl,
                      enabled: !_busy && widget.ownerUid.trim().isEmpty,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني للمالك *',
                        hintText: 'name@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty || !s.contains('@') || !s.contains('.')) {
                          return 'يرجى إدخال بريد إلكتروني صحيح للمالك';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // 0.1) كلمة المرور للحساب والمنشأة
                    if (!widget.isAdditionalWorkspace) ...[
                      TextFormField(
                        controller: _passwordCtrl,
                        enabled: !_busy,
                        obscureText: _obscurePassword,
                        textDirection: TextDirection.ltr,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: widget.ownerUid.trim().isEmpty
                              ? 'كلمة المرور للحساب * (6 أحرف على الأقل)'
                              : 'كلمة مرور احتياطية للمنشأة (اختياري)',
                          hintText: 'لاستعادة المنشأة والدخول من أي جهاز',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                            ),
                          ),
                        ),
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (widget.ownerUid.trim().isEmpty && s.length < 6) {
                            return 'يرجى إدخال كلمة مرور لا تقل عن 6 أحرف لحماية حسابك ومنشأتك';
                          }
                          if (s.isNotEmpty && s.length < 6) {
                            return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 1) اسم المنشأة التجاري (إجباري)
                    TextFormField(
                      controller: _storeNameCtrl,
                      enabled: !_busy,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'اسم المنشأة التجاري *',
                        hintText: 'مثال: مؤسسة النور للتجارة والتوكيلات',
                        prefixIcon: Icon(Icons.storefront_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.length < 2) {
                          return 'يرجى إدخال اسم المنشأة التجاري (إجباري)';
                        }
                        if (s == 'متجري' || s == 'منشأتي') {
                          return 'يرجى كتابة الاسم التجاري الحقيقي للمنشأة';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // 2) رقم هاتف المالك مع مفتاح الدولة (إجباري)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 155,
                          child: DropdownButtonFormField<String>(
                            value: _countryDialCode,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'مفتاح الدولة *',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 14),
                            ),
                            items: [
                              for (final c in _dialCodes)
                                DropdownMenuItem(
                                  value: c.$1,
                                  child: Text(
                                    c.$2,
                                    style: const TextStyle(fontSize: 12.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() => _countryDialCode = v);
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneCtrl,
                            enabled: !_busy,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'رقم هاتف المالك *',
                              hintText: '77xxxxxxx',
                              prefixIcon: Icon(Icons.phone_iphone_rounded),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              final digits = (v ?? '')
                                  .trim()
                                  .replaceAll(RegExp(r'[^\d]'), '');
                              if (digits.length < 7) {
                                return 'يرجى إدخال رقم هاتف صحيح للمالك (إجباري)';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3) نوع النشاط التجاري (إجباري)
                    TextFormField(
                      controller: _activityCtrl,
                      enabled: !_busy,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'نوع النشاط التجاري *',
                        hintText: 'مثال: مواد غذائية، إلكترونيات، تجارة عامة...',
                        prefixIcon: Icon(Icons.category_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().length < 2) {
                          return 'يرجى تحديد نوع النشاط التجاري (إجباري)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final act in _suggestedActivities)
                          ActionChip(
                            label: Text(act, style: const TextStyle(fontSize: 11.5)),
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() => _activityCtrl.text = act);
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 4) العملة الافتراضية (إجباري)
                    DropdownButtonFormField<String>(
                      value: _currency,
                      decoration: const InputDecoration(
                        labelText: 'العملة الافتراضية للمنشأة *',
                        prefixIcon: Icon(Icons.currency_exchange_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in kDefaultCurrencies)
                          DropdownMenuItem(
                            value: c.code,
                            child: Text('${c.name} (${c.code})'),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v != null) setState(() => _currency = v);
                            },
                    ),
                    const SizedBox(height: 16),

                    // العنوان (اختياري)
                    TextFormField(
                      controller: _addressCtrl,
                      enabled: !_busy,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'عنوان المنشأة (اختياري)',
                        hintText: 'المدينة - الشارع',
                        prefixIcon: Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 26),

                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.rocket_launch_rounded),
                        label: Text(
                          _busy
                              ? 'جاري إنشاء قاعدة البيانات وتسجيل المنشأة...'
                              : 'إنشاء المنشأة والدخول للنظام',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// نافذة «إدارة المنشآت / إنشاء منشأة أخرى» لمن يرغب بإدارة أكثر من نشاط بنفس الحساب
/// دون أن تتداخل حسابات المنشأتين مع بعضهما (قاعدة بيانات SQLite مستقلة لكل منشأة).
Future<void> showWorkspaceManagerDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _WorkspaceManagerDialog(),
  );
}

class _WorkspaceManagerDialog extends ConsumerStatefulWidget {
  const _WorkspaceManagerDialog();

  @override
  ConsumerState<_WorkspaceManagerDialog> createState() =>
      _WorkspaceManagerDialogState();
}

class _WorkspaceManagerDialogState
    extends ConsumerState<_WorkspaceManagerDialog> {
  List<WorkspaceInfo> _workspaces = const [];
  bool _loading = true;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(repoProvider);
      final st = await repo.settings();
      final url = effectiveBackendUrl(st['cloudBackendUrl']);
      final list = await AccountWorkspace.listUserWorkspaces(
        repo,
        backendUrl: url,
      );
      if (!mounted) return;
      setState(() {
        _workspaces = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _switchTo(WorkspaceInfo ws) async {
    if (_switching || ws.isCurrent) return;
    final ok = await confirmDialog(
      context,
      title: 'التبديل إلى «${ws.storeName}»',
      message:
          'سيتم إغلاق قاعدة بيانات المنشأة الحالية بأمان وفتح قاعدة البيانات المعزولة الخاصة بمنشأة «${ws.storeName}» (${ws.workspaceId}) دون أي تداخل في الحسابات أو العمليات.\n\nهل تريد المتابعة؟',
      confirmText: 'تبديل المنشأة',
    );
    if (ok != true || !mounted) return;

    setState(() => _switching = true);
    try {
      final repo = ref.read(repoProvider);
      final st = await repo.settings();
      final url = effectiveBackendUrl(st['cloudBackendUrl']);

      try {
        ref.read(syncEngineProvider).stop();
      } catch (_) {}

      final switched = await AccountWorkspace.switchToExistingWorkspace(
        repo,
        backendUrl: url,
        targetWorkspaceId: ws.workspaceId,
      );

      if (switched) {
        try {
          final engine = ref.read(syncEngineProvider);
          await engine.start();
          unawaited(engine.forceSyncNow());
        } catch (_) {}

        ref.invalidate(googleLinkedProvider);
        ref.invalidate(currentUserProvider);
        ref.invalidate(deviceRoleProvider);
        ref.invalidate(effectivePermissionsProvider);
        ref.invalidate(canManageGroupProvider);
        ref.invalidate(settingsProvider);
        ref.invalidate(isOwnerProvider);
        ref.invalidate(workspaceModeProvider);
        ref.invalidate(subscriptionProvider);
        bump(ref);

        if (!mounted) return;
        Navigator.of(context).pop();
        showSnack(context, 'تم التبديل إلى منشأة «${ws.storeName}» بنجاح ✅');
      } else {
        if (!mounted) return;
        showSnack(context, 'تعذّر التبديل إلى المنشأة المحددة', error: true);
        setState(() => _switching = false);
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'خطأ أثناء تبديل المنشأة: $e', error: true);
      setState(() => _switching = false);
    }
  }

  Future<void> _deleteWorkspace(WorkspaceInfo ws) async {
    if (_switching || ws.isCurrent) return;
    final ok = await confirmDialog(
      context,
      title: 'حذف المنشأة «${ws.storeName}»',
      message:
          'هل أنت متأكد من حذف منشأة «${ws.storeName}» (${ws.workspaceId}) من حسابك وقاعدتك نهائياً؟\n\nتنبيه: لا يمكن التراجع عن هذا الإجراء.',
      confirmText: 'حذف نهائياً',
      danger: true,
    );
    if (ok != true || !mounted) return;

    setState(() => _switching = true);
    try {
      final repo = ref.read(repoProvider);
      final st = await repo.settings();
      final url = effectiveBackendUrl(st['cloudBackendUrl']);
      await AccountWorkspace.deleteWorkspaceRegistration(
        repo,
        backendUrl: url,
        workspaceId: ws.workspaceId,
        ownerEmail: ws.ownerEmail,
        phone: ws.phone,
        deleteLocalDbFile: true,
      );
      if (!mounted) return;
      showSnack(context, 'تم حذف المنشأة «${ws.storeName}» بنجاح');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'خطأ أثناء حذف المنشأة: $e', error: true);
    } finally {
      // (دفعة التدقيق) إعادة الحالة في كل المسارات — النجاح كان يترك
      // _switching محتجزاً إن لم تصفّره _load فتتعطل أزرار الحوار.
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _changeWorkspacePassword(WorkspaceInfo ws) async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure1 = true;
    bool obscure2 = true;
    bool saving = false;
    String? errMsg;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          title: Row(
            children: [
              Icon(Icons.lock_reset_rounded,
                  color: AppColors.primaryOf(context), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تغيير كلمة المرور للمنشأة — ${ws.storeName}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 330,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'تحديث مباشر وآمن لحقل password_hash في عقدة المنشأة (/workspaces/${ws.workspaceId}/meta/password_hash).',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.text2Of(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure1,
                    enabled: !saving,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور الجديدة *',
                      isDense: true,
                      prefixIcon:
                          const Icon(Icons.lock_outline_rounded, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure1
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        onPressed: () =>
                            setDState(() => obscure1 = !obscure1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: obscure2,
                    enabled: !saving,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'تأكيد كلمة المرور الجديدة *',
                      isDense: true,
                      prefixIcon:
                          const Icon(Icons.verified_user_outlined, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure2
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        onPressed: () =>
                            setDState(() => obscure2 = !obscure2),
                      ),
                    ),
                  ),
                  if (errMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errMsg!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final p1 = passCtrl.text.trim();
                      final p2 = confirmCtrl.text.trim();
                      if (p1.length < 4) {
                        setDState(() => errMsg =
                            'يرجى إدخال كلمة مرور لا تقل عن 4 محارف.');
                        return;
                      }
                      if (p1 != p2) {
                        setDState(() => errMsg =
                            'كلمتا المرور غير متطابقتين. يرجى التأكد من التطابق.');
                        return;
                      }
                      setDState(() {
                        saving = true;
                        errMsg = null;
                      });
                      try {
                        final repo = ref.read(repoProvider);
                        final st = await repo.settings();
                        final url = effectiveBackendUrl(st['cloudBackendUrl']);
                        final token = await FirebaseAuthService.getValidIdToken(
                          repo,
                          apiKey: FirebaseWebAuthConfig.apiKey,
                        );
                        if (token == null || token.isEmpty) {
                          throw Exception(
                              'يلزم تسجيل الدخول بحساب المنشأة لتحديث كلمة المرور.');
                        }
                        await SmartSupportRecoveryService
                            .adminUpdateWorkspacePassword(
                          backendUrl: url,
                          adminIdToken: token,
                          workspaceId: ws.workspaceId,
                          newPassword: p1,
                          ownerEmail: ws.ownerEmail,
                          phone: ws.phone,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          showSnack(context,
                              'تم تحديث كلمة المرور للمنشأة «${ws.storeName}» بنجاح ✅');
                        }
                      } catch (e) {
                        setDState(() {
                          saving = false;
                          errMsg = '$e';
                        });
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, size: 16),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    WorkspaceInfo? currentWs;
    for (final w in _workspaces) {
      if (w.isCurrent) {
        currentWs = w;
        break;
      }
    }
    currentWs ??= _workspaces.isNotEmpty ? _workspaces.first : null;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
      contentPadding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      actionsPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          Icon(Icons.domain_rounded, color: primary, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'إدارة المنشآت',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
          ),
          if (currentWs != null && !_loading && !_switching)
            PopupMenuButton<String>(
              tooltip: 'خيارات المنشأة',
              icon: const Icon(Icons.more_vert_rounded, size: 19),
              padding: EdgeInsets.zero,
              onSelected: (val) {
                if (val == 'change_password' && currentWs != null) {
                  _changeWorkspacePassword(currentWs);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'change_password',
                  child: Row(
                    children: [
                      Icon(Icons.lock_reset_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'تغيير كلمة المرور للمنشأة',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: _loading || _switching
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.3),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _switching
                          ? 'جاري التبديل وفتح قاعدة بيانات المنشأة المختارة...'
                          : 'جاري تحميل قائمة منشآتك...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'قاعدة بيانات SQLite مستقلة لكل منشأة — انقر للتبديل السريع:',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: AppColors.text2Of(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _workspaces.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 5),
                      itemBuilder: (ctx, i) {
                        final ws = _workspaces[i];
                        return Container(
                          decoration: BoxDecoration(
                            color: ws.isCurrent
                                ? primary.withValues(alpha: 0.1)
                                : Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: ws.isCurrent
                                  ? primary
                                  : Colors.grey.withValues(alpha: 0.3),
                              width: ws.isCurrent ? 1.4 : 1,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            leading: CircleAvatar(
                              radius: 15,
                              backgroundColor: ws.isCurrent
                                  ? primary
                                  : Colors.grey.withValues(alpha: 0.2),
                              foregroundColor:
                                  ws.isCurrent ? Colors.white : primary,
                              child: Icon(
                                ws.isCurrent
                                    ? Icons.check_circle_rounded
                                    : Icons.store_rounded,
                                size: 16,
                              ),
                            ),
                            title: Text(
                              ws.storeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                            subtitle: Text(
                              [
                                ws.workspaceId,
                                ws.defaultCurrency,
                              ].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10.5),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (ws.isCurrent)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'النشطة',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                    ),
                                    onPressed: () => _switchTo(ws),
                                    child: const Text(
                                      'تبديل',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                PopupMenuButton<String>(
                                  tooltip: 'خيارات المنشأة',
                                  icon: const Icon(Icons.more_vert_rounded,
                                      size: 17),
                                  padding: EdgeInsets.zero,
                                  onSelected: (val) {
                                    if (val == 'change_password') {
                                      _changeWorkspacePassword(ws);
                                    } else if (val == 'delete' &&
                                        !ws.isCurrent) {
                                      _deleteWorkspace(ws);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem<String>(
                                      value: 'change_password',
                                      child: Row(
                                        children: [
                                          Icon(Icons.lock_reset_rounded,
                                              size: 17),
                                          SizedBox(width: 8),
                                          Text(
                                            'تغيير كلمة المرور للمنشأة',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!ws.isCurrent)
                                      const PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline,
                                                color: Colors.redAccent,
                                                size: 17),
                                            SizedBox(width: 8),
                                            Text(
                                              'حذف المنشأة',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            onTap: ws.isCurrent ? null : () => _switchTo(ws),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      showSecuredLogout(ref);
                    },
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('تسجيل الخروج لشاشة الدخول والمنشآت',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: _switching ? null : () => Navigator.of(context).pop(),
          child: const Text('إغلاق', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
