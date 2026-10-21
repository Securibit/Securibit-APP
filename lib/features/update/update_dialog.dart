import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import 'release.dart';
import 'update_controller.dart';

// 提示已經開著（自動檢查與手動檢查同時查到時不會疊兩個）
bool _open = false;

/// 有新版本的提示：版本號、更新內容，「下載」用瀏覽器打開這個平台的安裝檔（或 Release 頁面）
Future<void> showUpdateDialog(BuildContext context, UpdateController updates, AppRelease release) async {
  if (_open) return;
  _open = true;
  try {
    await showDialog<void>(context: context, builder: (_) => _UpdateDialog(updates: updates, release: release));
  } finally {
    _open = false;
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.updates, required this.release});

  final UpdateController updates;
  final AppRelease release;

  Future<void> _download(BuildContext context) async {
    final navigator = Navigator.of(context);
    final url = updates.downloadUrl(release);
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // 下面一起處理
    }
    if (!context.mounted) return;
    if (!opened) {
      await showErrorDialog(context, '無法開啟瀏覽器', '請到這個網址下載：\n${release.pageUrl}');
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notes = plainReleaseNotes(release.notes);
    final current = updates.currentVersion;

    return AlertDialog(
      title: const Text('有新版本'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Securibit ${release.version} 已推出${current == null ? '' : '，目前是 $current'}'),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              // 更新內容太長時在框裡捲動，按鈕一直看得到
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.small)),
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(notes, style: TextStyle(fontSize: AppText.secondary, color: colors.ink, height: 1.45)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            await updates.skip(release);
            navigator.pop();
          },
          style: TextButton.styleFrom(foregroundColor: colors.inkMuted),
          child: const Text('略過這個版本'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: colors.ink),
          child: const Text('稍後'),
        ),
        FilledButton(onPressed: () => _download(context), child: const Text('下載')),
      ],
    );
  }
}
