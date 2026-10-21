import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../codes_controller.dart';
import '../totp/categories.dart';
import '../totp/import_text.dart';
import '../totp/totp_params.dart';
import '../widgets/category_input.dart';
import 'duplicates.dart';
import 'import_repository.dart';
import 'transfer_widgets.dart';

/// 一次匯入多筆（Google Authenticator 匯出、備份檔、多行連結）；成功時回傳匯入的筆數
Future<int?> showBulkImport(BuildContext context, CodesController controller, ImportTextResult result) =>
    showTransferPage<int>(context, BulkImportPage(controller: controller, result: result));

/// 一筆的補充說明：類別與不是預設值的進階設定（同網站 BulkImportModal 的 describe）
String describeImportItem(TotpInput item) => [
      if (item.category.isNotEmpty) formatCategories(item.category),
      if (item.digits != TotpDefaults.digits) '${item.digits} 位數',
      if (item.period != TotpDefaults.period) '${item.period} 秒',
      if (item.algorithm != TotpDefaults.algorithm) item.algorithm.label,
    ].join(' · ');

/*
 * 列出解析到的驗證碼（同網站 BulkImportModal）：可以取消勾選、統一指定類別（可多個）。
 * 金鑰和群組既有的、或和清單裡前面的重複時標「已存在」，預設不勾。
 */
class BulkImportPage extends StatefulWidget {
  const BulkImportPage({super.key, required this.controller, required this.result});

  final CodesController controller;
  final ImportTextResult result;

  @override
  State<BulkImportPage> createState() => _BulkImportPageState();
}

class _BulkImportPageState extends State<BulkImportPage> {
  late final List<TotpInput> _items = widget.result.items;
  late final List<bool> _duplicates = markDuplicates(existingSecrets(widget.controller), _items);
  late final List<bool> _selected = [for (final duplicate in _duplicates) !duplicate];
  String _category = '';
  bool _saving = false;

  int get _count => _selected.where((s) => s).length;

  Future<void> _confirm() async {
    if (_saving || _count == 0) return;
    setState(() => _saving = true);
    final controller = widget.controller;
    final inputs = [for (var i = 0; i < _items.length; i++) if (_selected[i]) _items[i]];
    final result = await importGroupAccounts(controller.group.id, inputs, category: _category, encrypted: controller.group.encrypted);
    if (!mounted) return;
    final error = result.messageOrNull;
    if (error != null) {
      setState(() => _saving = false);
      await showErrorDialog(context, '匯入驗證碼失敗', error);
      return;
    }
    await controller.load();
    if (!mounted) return;
    showToast(context, '已匯入 ${inputs.length} 筆驗證碼');
    Navigator.of(context).pop(inputs.length);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final batch = widget.result.batch;
    final errors = widget.result.errors;
    final group = widget.controller.group;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            TransferHeader(
              title: '匯入 ${_items.length} 筆驗證碼',
              subtitle: batch == null ? null : '第 ${batch.index} / ${batch.size} 張匯出 QR Code',
              leading: TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: colors.ink),
                child: const Text('取消'),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Text(
                    group.encrypted
                        ? '加到「${group.name}」，金鑰會先用你的加密密碼加密才送出'
                        : '加到「${group.name}」${widget.controller.solo ? '' : '，群組成員會依身分組權限看到'}',
                    style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                  ),
                  if (batch != null && batch.index < batch.size) ...[
                    const SizedBox(height: 6),
                    Text(
                      '這是第 ${batch.index} / ${batch.size} 張，匯入後請繼續掃描下一張',
                      style: TextStyle(fontSize: AppText.secondary, color: colors.ink, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _list(context),
                  const SizedBox(height: 24),
                  const TransferSectionTitle('類別'),
                  CategoryInput(
                    value: _category,
                    suggestions: widget.controller.categories,
                    onChanged: (value) => setState(() => _category = value),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '套用到勾選的全部，可留空；可選多個，會取代各筆原本的類別',
                    style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
                  ),
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('以下內容無法匯入', style: TextStyle(fontSize: AppText.secondary, color: colors.alarm, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    for (final error in errors)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('・$error', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || _count == 0 ? null : _confirm,
                  child: _saving
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.inkMuted))
                      : Text('匯入 $_count 筆'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final colors = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      final detail = describeImportItem(item);
      if (i > 0) rows.add(Divider(indent: 56, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      rows.add(InkWell(
        onTap: _saving ? null : () => setState(() => _selected[i] = !_selected[i]),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
          child: Row(
            children: [
              Checkbox(
                value: _selected[i],
                activeColor: colors.accent,
                onChanged: _saving ? null : (value) => setState(() => _selected[i] = value ?? false),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
                      ),
                  ],
                ),
              ),
              if (_duplicates[i]) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(999)),
                  child: Text('已存在', style: TextStyle(fontSize: AppText.caption, color: colors.alarm, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      ));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: ColoredBox(color: colors.surface1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
    );
  }
}
