import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cloud_config.dart';
import '../data/providers.dart';
import '../data/sync/account_workspace.dart';

/// تعرض المنشآت المطابقة للبريد المسجّل في المنشأة الحالية.
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
      final repo = ref.read(repoProvider);
      final settings = await repo.settings();
      final email = (settings['account.email'] ?? settings['email'] ?? '')
          .trim().toLowerCase();
      if (email.isEmpty) {
        throw StateError('لا يوجد بريد مسجّل في المنشأة الحالية. سجّل الدخول أو أضف البريد أولاً.');
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
                      Text('المنشآت المطابقة للبريد المسجّل: $_email'),
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
