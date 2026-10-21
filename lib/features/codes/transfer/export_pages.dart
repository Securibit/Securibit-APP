import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../../core/widgets/pill.dart';
import '../totp/migration.dart';
import '../totp/otpauth.dart';
import '../totp/totp_params.dart';
import 'export_data.dart';
import 'transfer_widgets.dart';

/// 單筆匯出（同網站 ExportItemModal）：顯示 otpauth QR Code，給手機上的驗證器 App 掃描
class ExportItemPage extends StatelessWidget {
  const ExportItemPage({super.key, required this.item});

  final TotpInput item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uri = buildOtpauthUri(item);
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            TransferHeader(
              title: '匯出「${item.name}」',
              trailing: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('完成')),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Center(child: QrPanel(data: uri, semanticLabel: '${item.name} 的 QR Code')),
                  const SizedBox(height: 16),
                  Text(
                    '用 Google Authenticator、Microsoft Authenticator 等 App 掃描，就能加到手機上',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                  ),
                  const SizedBox(height: 16),
                  const ExportWarning(),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => copyText(context, uri, message: '已複製連結'),
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    label: const Text('複製連結'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/*
 * 全部匯出（同網站 ExportModal）：Google Authenticator 的匯入 QR Code（每 10 筆一張），
 * 或每行一個 otpauth 連結的文字備份（桌面存檔、手機分享，也可以複製）。
 */
class ExportAllPage extends StatefulWidget {
  const ExportAllPage({super.key, required this.items, required this.missing});

  final List<TotpInput> items;
  // 沒有「查看金鑰」或金鑰錯誤、不會匯出的筆數
  final int missing;

  @override
  State<ExportAllPage> createState() => _ExportAllPageState();
}

class _ExportAllPageState extends State<ExportAllPage> {
  late final List<TotpInput> _googleItems = widget.items.where(canExportToGoogle).toList();
  late final List<String> _migrationUris = buildMigrationUris(_googleItems);
  final DateTime _now = DateTime.now();
  late final String _backupText = buildBackupText(widget.items, _now);
  // 0：Google Authenticator，1：文字備份
  int _tab = 0;
  int _page = 0;
  final _shareKey = GlobalKey();

  Uint8List get _backupBytes => Uint8List.fromList(utf8.encode('$_backupText\n'));

  Future<void> _save() async {
    final name = backupFileName(_now);
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: '儲存備份檔',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        bytes: _backupBytes,
      );
      if (path == null) return;
      // 有的平台只回傳路徑、不會幫忙寫入
      final file = File(path);
      if (!await file.exists() || await file.length() == 0) await file.writeAsBytes(_backupBytes, flush: true);
      if (mounted) showToast(context, '已儲存備份檔');
    } catch (error) {
      if (mounted) await showErrorDialog(context, '無法儲存備份檔', '$error');
    }
  }

  Future<void> _share() async {
    final name = backupFileName(_now);
    // iPad 的分享面板要指定從哪裡彈出
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(_backupBytes, mimeType: 'text/plain', name: name)],
        fileNameOverrides: [name],
        subject: name,
        sharePositionOrigin: origin,
      ));
    } catch (error) {
      if (mounted) await showErrorDialog(context, '無法分享備份檔', '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            TransferHeader(
              title: '匯出全部驗證碼',
              subtitle: '共 ${widget.items.length} 筆',
              trailing: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('完成')),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const ExportWarning(),
                  if (widget.missing > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      '有 ${widget.missing} 筆你沒有「查看金鑰」權限（或金鑰錯誤），不會匯出',
                      style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Center(
                    child: PillBar(
                      labels: const ['Google Authenticator', '文字備份'],
                      selectedIndex: _tab,
                      onSelect: (index) => setState(() => _tab = index),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_tab == 0) _google(context) else _text(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _google(BuildContext context) {
    final colors = context.colors;
    final uris = _migrationUris;
    if (uris.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.medium)),
        child: Text(
          '沒有可以匯出到 Google Authenticator 的驗證碼',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppText.body, color: colors.inkMuted, fontWeight: FontWeight.w600),
        ),
      );
    }
    final skipped = widget.items.length - _googleItems.length;
    return Column(
      children: [
        Text(
          '在 Google Authenticator 選「轉移帳戶 → 匯入帳戶」，依序掃描${uris.length > 1 ? ' ${uris.length} 張' : '這張'} QR Code',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
        ),
        const SizedBox(height: 16),
        QrPanel(data: uris[_page], semanticLabel: '第 ${_page + 1} 張匯出 QR Code'),
        if (uris.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一張',
                onPressed: _page == 0 ? null : () => setState(() => _page--),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              const SizedBox(width: 8),
              Text(
                '${_page + 1} / ${uris.length}',
                style: TextStyle(
                  fontSize: AppText.body,
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '下一張',
                onPressed: _page == uris.length - 1 ? null : () => setState(() => _page++),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
        if (skipped > 0) ...[
          const SizedBox(height: 12),
          Text(
            '有 $skipped 筆不是 30 秒週期，Google Authenticator 不支援，請改用文字備份',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.secondary, color: colors.alarm, fontWeight: FontWeight.w500),
          ),
        ],
      ],
    );
  }

  Widget _text(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '每行一個 otpauth 連結（含類別），之後可以在「新增驗證碼 → 匯入」整批匯入，也可以給其他支援 otpauth 連結的 App 使用',
          style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
        ),
        const SizedBox(height: 16),
        GroupedList(
          children: [
            if (AppPlatform.isMobile)
              GroupedRow(
                key: _shareKey,
                label: '分享備份檔',
                accent: true,
                leading: Icon(Icons.ios_share_rounded, size: 20, color: colors.accent),
                onTap: _share,
              )
            else
              GroupedRow(
                label: '儲存備份檔',
                accent: true,
                leading: Icon(Icons.download_rounded, size: 20, color: colors.accent),
                onTap: _save,
              ),
            GroupedRow(
              label: '複製全部連結',
              accent: true,
              leading: Icon(Icons.copy_rounded, size: 20, color: colors.accent),
              onTap: () => copyText(context, _backupText, message: '已複製全部連結'),
            ),
          ],
        ),
      ],
    );
  }
}
