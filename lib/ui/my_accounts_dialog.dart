import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/auth_config.dart';
import '../core/cloud_config.dart';
import '../data/providers.dart';
import '../data/sync/account_workspace.dart';
import '../data/sync/firebase_auth_service.dart';

/// تعرض المطابقة بالبريد الذي يؤكده Firebase، وليس البريد المدخل يدوياً.
Future<void> showMyAccountsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _MyAccountsDialog(),
  );
}

class _MyAccountsDialog extends ConsumerStatefulWidget {
  const _MyAccountsDialog();

  @override
  ConsumerState<_MyAccountsDialog> createState() => _MyAccountsDialogState();
}

class _MyAccountsDialogState extends ConsumerState<_MyAccountsDialog> {
  bool _loading = true;
  String _message = '';
  String _email = '';
  List<WorkspaceInfo> _workspaces = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _message = ''; });
    try {
      if (!FirebaseAuthRest.hasAccountSession || effectiveFirebaseApiKey.isEmpty) {
        throw StateError('سجّل الدخول بحساب بريد إلكتروني موثّق لعرض منشآتك.');
      }
      final token = await FirebaseAuthRest.cloudIdToken();
      if (token == null || token.isEmpty || !FirebaseAuthRest.hasAccountSession) {
        throw StateError('تعذّر التحقق من جلسة الحساب. سجّل الدخول مجدداً.');
      }
      final response = await http.post(
        Uri.https('identitytoolkit.googleapis.com', '/v1/accounts:lookup',
            {'key': effectiveFirebaseApiKey}),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': token}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('تعذّر التحقق من البريد. تحقق من الاتصال وسجّل الدخول مجدداً.');
      }
      final decoded = jsonDecode(response.body);
      final users = decoded is Map ? decoded['users'] : null;
      if (users is! List || users.length != 1 || users.first is! Map) {
        throw StateError('تعذّر التحقق من هوية الحساب.');
      }
      final identity = users.first as Map;
      final email = '${identity['email'] ?? ''}'.trim().toLowerCase();
      final uid = '${identity['localId'] ?? ''}'.trim();
      if (identity['emailVerified'] != true || email.isEmpty ||
          uid.isEmpty || uid != FirebaseAuthRest.currentUid) {
        throw StateError('يلزم تسجيل الدخول ببريد إلكتروني موثّق.');
      }
      final repo = ref.read(repoProvider);
      final settings = await repo.settings();
      final currentEmail = (settings['account.email'] ?? settings['email'] ?? '')
          .trim().toLowerCase();
      if (currentEmail != email) {
        throw StateError('البريد الحالي لا يطابق جلسة الحساب الموثّقة.');
      }
      final all = await AccountWorkspace.listUserWorkspaces(
        repo,
        backendUrl: effectiveBackendUrl(settings['cloudBackendUrl']),
        includeAllDeviceWorkspaces: false,
      );
      final matching = all.where((w) =>
          w.ownerEmail.trim().toLowerCase() == email).toList();
      if (!mounted) return;
      setState(() { _email = email; _workspaces = matching; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e is StateError ? e.message.toString() :
            'تعذّر تحميل المنشآت. تحقق من الاتصال وحاول مجدداً.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('عرض حساباتي'),
      content: SizedBox(
        width: 440,
        child: _loading
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : _message.isNotEmpty
                ? Text(_message)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('المنشآت المرتبطة بالبريد الموثّق: $_email'),
                      const Text('قد تكون القائمة غير مكتملة عند تعذر الاتصال بالسحابة.', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 12),
                      if (_workspaces.isEmpty)
                        const Text('لا توجد منشآت مطابقة ظاهرة لهذا البريد.')
                      else
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _workspaces.length,
                            itemBuilder: (context, index) {
                              final ws = _workspaces[index];
                              return ListTile(
                                leading: Icon(ws.isCurrent ? Icons.check_circle : Icons.store_outlined),
                                title: Text(ws.storeName),
                                subtitle: Text('${ws.workspaceId}${ws.isCurrent ? ' • المنشأة الحالية' : ''}'),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 12),
                      const Text('العرض فقط حالياً؛ التبديل والحذف يتطلبان استكمال التحقق من الصلاحيات وحماية البيانات.', style: TextStyle(fontSize: 12)),
                    ],
                  ),
      ),
      actions: [
        if (!_loading) TextButton(onPressed: _load, child: const Text('تحديث')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق')),
      ],
    );
  }
}
