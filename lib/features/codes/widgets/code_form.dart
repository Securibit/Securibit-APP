import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../code_models.dart';
import '../codes_controller.dart';
import '../secret_handle.dart';
import '../totp/import_text.dart';
import '../totp/secret.dart';
import '../totp/totp_params.dart';
import '../totp/validate.dart';
import '../transfer/bulk_import_page.dart';
import '../transfer/duplicates.dart';
import '../transfer/import_sources.dart';
import 'category_input.dart';
import 'qr_scan_page.dart';

/// 新增或編輯驗證碼：寬視窗用對話框，窄螢幕用整頁；initialText 是點連結帶進來的 otpauth 連結（同貼上）
Future<void> showCodeForm(BuildContext context, CodesController controller, {GroupAccount? account, String? initialText}) {
  final form = CodeForm(controller: controller, account: account, initialText: initialText);
  if (MediaQuery.sizeOf(context).width >= 720) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 540, maxHeight: 760), child: form),
      ),
    );
  }
  return Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => form));
}

/*
 * 表單欄位同網站 TotpForm / GroupCodeEditModal：名稱、類別（可多個）、金鑰（Base32）、進階設定。
 * 新增時可以貼上 otpauth:// 連結、上傳 QR Code 圖片或備份檔、（手機與 macOS）用相機掃 QR Code：
 * 一筆就填好欄位，多筆（Google Authenticator 匯出、備份檔）開整批匯入（同網站 QrImport）。
 * 新增前檢查金鑰是否和群組裡已有的重複，重複時先問要不要照樣新增（同網站 AddCodeClient）。
 * 編輯時沒有「查看金鑰」權限看不到原本的金鑰：金鑰欄位留空代表不修改。
 */
class CodeForm extends StatefulWidget {
  const CodeForm({super.key, required this.controller, this.account, this.initialText});

  final CodesController controller;
  final GroupAccount? account;
  // 點 otpauth:// 或 otpauth-migration:// 連結打開時帶進來的連結，開啟後當作貼上處理
  final String? initialText;

  @override
  State<CodeForm> createState() => _CodeFormState();
}

class _CodeFormState extends State<CodeForm> {
  late final GroupAccount? _account = widget.account;
  // 編輯時要把原本的金鑰填進欄位，這時才從 Rust 取出來
  late final SecretHandle? _handle = _account == null ? null : widget.controller.secretOf(_account);
  late final String? _originalSecret = _handle?.reveal();
  late final bool _secretKnown = _account == null || _handle != null;

  late final _name = TextEditingController(text: _account?.name ?? '');
  late final _secret = TextEditingController(text: _originalSecret ?? '');
  final _link = TextEditingController();

  late String _category = _account?.category ?? '';
  late int _digits = _account?.digits ?? TotpDefaults.digits;
  late int _period = _account?.period ?? TotpDefaults.period;
  late TotpAlgorithm _algorithm = _account?.algorithm ?? TotpDefaults.algorithm;
  late bool _advancedOpen = _account != null &&
      (_digits != TotpDefaults.digits || _period != TotpDefaults.period || _algorithm != TotpDefaults.algorithm);

  bool _showSecret = false;
  bool _saving = false;
  // 正在讀檔案或圖片
  bool _reading = false;
  // 整批匯入畫面開著（貼上時 onChanged 可能連續觸發）
  bool _bulkOpen = false;
  // 這次已經整批匯入的筆數；有匯入過，左上角改成「完成」
  int _imported = 0;
  TotpErrors _errors = const TotpErrors();
  String? _linkError;

  bool get _isEdit => _account != null;

  @override
  void initState() {
    super.initState();
    final text = widget.initialText?.trim() ?? '';
    if (_isEdit || text.isEmpty) return;
    // 同貼上：一筆就填好欄位，多筆開整批匯入（畫面出來後才開，整批匯入要疊在表單上面）
    if (!text.contains('\n')) _link.text = text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _importText(text);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _secret.dispose();
    _link.dispose();
    super.dispose();
  }

  TotpInput get _input => TotpInput(
        name: _name.text,
        secret: _secret.text,
        category: _category,
        digits: _digits,
        period: _period,
        algorithm: _algorithm,
      );

  bool get _secretChanged {
    final next = normalizeSecret(_secret.text);
    return _isEdit && next.isNotEmpty && next != normalizeSecret(_originalSecret ?? '');
  }

  /// 匯入貼上、掃描或檔案的內容：一筆就填好欄位（類別沒填時才用連結裡的），多筆開整批匯入。
  /// inline 時錯誤顯示在連結欄位下面，否則跳出錯誤對話框
  Future<bool> _importText(String text, {bool inline = true, String source = '連結', List<String> extraErrors = const []}) async {
    final result = parseImportText(text)..errors.addAll(extraErrors);
    if (result.items.isEmpty) {
      final message = result.errors.join('\n');
      if (inline) {
        setState(() => _linkError = message);
      } else {
        await showErrorDialog(context, '無法匯入', message);
      }
      return false;
    }
    if (result.isSingle) {
      final data = result.items.single;
      setState(() {
        _name.text = data.name;
        _secret.text = data.secret;
        if (_category.isEmpty) _category = data.category;
        _digits = data.digits;
        _period = data.period;
        _algorithm = data.algorithm;
        _advancedOpen = !data.isDefaultAdvanced;
        _errors = const TotpErrors();
        _linkError = null;
      });
      showToast(context, '已從$source填好欄位，確認後按新增');
      return true;
    }

    if (_bulkOpen) return false;
    _bulkOpen = true;
    setState(() => _linkError = null);
    _link.clear();
    final count = await showBulkImport(context, widget.controller, result);
    _bulkOpen = false;
    if (!mounted || count == null) return false;
    setState(() => _imported += count);
    return true;
  }

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _linkError = '剪貼簿裡沒有文字');
      return;
    }
    // 多行的內容（備份檔、多個連結）不放進欄位，直接匯入
    if (!text.contains('\n')) _link.text = text;
    await _importText(text);
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (!mounted || value == null) return;
    await _importText(value, inline: false, source: ' QR Code ');
  }

  Future<void> _pickFile(ImportFileKind kind) async {
    if (_reading) return;
    setState(() => _reading = true);
    final picked = await pickImportFiles(kind);
    if (!mounted) return;
    setState(() => _reading = false);
    if (picked == null) return;
    final texts = [for (final file in picked) ?file.result.text];
    // 選了好幾個時，讀不出來的那幾個標上檔名，跟讀得到的一起列在整批匯入裡
    final failures = [
      for (final file in picked)
        if (file.result.text == null) picked.length > 1 ? '${file.name}：${file.result.errorMessage}' : file.result.errorMessage ?? '',
    ];
    if (texts.isEmpty) {
      final single = picked.length == 1 ? picked.single.result : null;
      await showErrorDialog(context, single?.errorTitle ?? '無法匯入', failures.join('\n'));
      return;
    }
    await _importText(texts.join('\n'), inline: false, source: '檔案', extraErrors: failures);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final input = _input;
    final errors = _isEdit ? validateTotpEdit(input, secretKnown: _secretKnown) : validateTotpInput(input);
    setState(() => _errors = errors);
    if (!errors.isEmpty) return;

    final controller = widget.controller;
    final account = _account;
    // 金鑰和既有的某筆相同時，先問要不要照樣新增（只比得到我看得到金鑰的那些）
    if (account == null) {
      final duplicate = findDuplicateIn(controller, input.secret);
      if (duplicate != null) {
        final confirmed = await confirmDialog(
          context,
          title: '已經有相同的金鑰',
          message: '「${duplicate.name}」使用相同的金鑰，產生的驗證碼會一模一樣。確定還要再新增一筆嗎？',
          confirmLabel: '仍要新增',
        );
        if (!mounted || !confirmed) return;
      }
    }

    setState(() => _saving = true);
    final error = account == null
        ? await controller.add(input)
        // 金鑰沒有改就不送，避免沒有「查看金鑰」的人誤把金鑰清掉
        : await controller.update(account, input, secret: _secretChanged ? input.secret : null);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      await showErrorDialog(context, account == null ? '新增驗證碼失敗' : '儲存驗證碼失敗', error);
      return;
    }
    showToast(context, account == null ? '已新增「${input.name.trim()}」' : '已儲存');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  if (!_isEdit) ...[
                    if (!widget.controller.solo)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          '新增後群組成員會依身分組權限看到這筆驗證碼',
                          style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                        ),
                      ),
                    _importSection(context),
                    const SizedBox(height: 24),
                    _sectionTitle(context, '或手動輸入'),
                  ],
                  _label(context, '名稱'),
                  TextField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() => _errors = const TotpErrors()),
                    decoration: InputDecoration(hintText: '例如：Google - me@example.com', errorText: _errors.name),
                  ),
                  const SizedBox(height: 20),
                  _label(context, '類別'),
                  CategoryInput(
                    value: _category,
                    suggestions: widget.controller.categories,
                    onChanged: (value) => setState(() => _category = value),
                  ),
                  const SizedBox(height: 20),
                  _label(context, '金鑰'),
                  TextField(
                    controller: _secret,
                    obscureText: !_showSecret,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (text) {
                      // 直接把 otpauth:// 連結貼進金鑰欄也可以
                      if (!_isEdit && text.trim().startsWith('otpauth')) {
                        _secret.clear();
                        _importText(text);
                        return;
                      }
                      setState(() => _errors = const TotpErrors());
                    },
                    decoration: InputDecoration(
                      hintText: _secretKnown ? 'JBSWY3DPEHPK3PXP' : '不修改請留空',
                      errorText: _errors.secret,
                      helperText: _secretKnown
                          ? 'Base32 格式（A–Z、2–7），空白與小寫會自動轉換'
                          : '你沒有「查看金鑰」權限，看不到目前的金鑰；要更換才需要填寫',
                      suffixIcon: IconButton(
                        tooltip: _showSecret ? '隱藏金鑰' : '顯示金鑰',
                        onPressed: () => setState(() => _showSecret = !_showSecret),
                        icon: Icon(_showSecret ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _advanced(context),
                  if (_secretChanged) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.small)),
                      child: Text(
                        '更換金鑰後會產生完全不同的驗證碼，群組裡所有成員看到的驗證碼都會跟著改變',
                        style: TextStyle(fontSize: AppText.secondary, color: colors.alarm, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: colors.ink),
            child: Text(_imported > 0 ? '完成' : '取消'),
          ),
          Expanded(
            child: Text(
              _isEdit ? '編輯驗證碼' : '新增驗證碼',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEdit ? '儲存' : '新增'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: TextStyle(fontSize: AppText.secondary, color: context.colors.inkMuted, fontWeight: FontWeight.w600)),
      );

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600)),
      );

  Widget _importSection(BuildContext context) {
    final colors = context.colors;
    final buttons = <Widget>[
      if (AppPlatform.isMobile) ...[
        _importButton(Icons.photo_library_rounded, '從相簿選擇圖片', () => _pickFile(ImportFileKind.image)),
        _importButton(Icons.description_rounded, '選擇備份檔', () => _pickFile(ImportFileKind.backup)),
      ] else if (AppPlatform.canReadQrImage)
        _importButton(Icons.upload_file_rounded, '上傳圖片或備份檔', () => _pickFile(ImportFileKind.any))
      else
        _importButton(Icons.upload_file_rounded, '上傳備份檔', () => _pickFile(ImportFileKind.backup)),
      if (AppPlatform.canScanQr) _importButton(Icons.qr_code_scanner_rounded, '用相機掃描', _scan, file: false),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(context, '匯入'),
        if (_imported > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 20, color: colors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已匯入 $_imported 筆驗證碼，可以繼續新增下一筆',
                    style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        TextField(
          controller: _link,
          autocorrect: false,
          enableSuggestions: false,
          // 可以一次貼上多行連結
          minLines: 1,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          onChanged: (text) {
            if (text.trim().startsWith('otpauth')) {
              _importText(text);
            } else if (_linkError != null) {
              setState(() => _linkError = null);
            }
          },
          decoration: InputDecoration(
            hintText: '貼上 otpauth 連結',
            errorText: _linkError,
            suffixIcon: IconButton(tooltip: '從剪貼簿貼上', onPressed: _pasteLink, icon: const Icon(Icons.content_paste_rounded)),
          ),
        ),
        const SizedBox(height: 10),
        // 寬的時候兩個按鈕並排，窄的時候或按鈕多時一個一行
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 440 && buttons.length <= 2) {
              return Row(
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: buttons[i]),
                  ],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  buttons[i],
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '貼上服務給的 otpauth 連結，或用綁定畫面的 QR Code；Google Authenticator 的匯出 QR Code 和備份檔可以一次匯入多筆',
          style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
        ),
      ],
    );
  }

  // file：選檔的按鈕，讀檔時顯示「讀取中…」
  Widget _importButton(IconData icon, String label, VoidCallback onPressed, {bool file = true}) => OutlinedButton.icon(
        onPressed: _reading || _saving ? null : onPressed,
        icon: Icon(icon, size: 20),
        label: Text(_reading && file ? '讀取中…' : label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );

  Widget _advanced(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.small)),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.small),
            onTap: () => setState(() => _advancedOpen = !_advancedOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Text('進階設定', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    '$_digits 位數 · $_period 秒 · ${_algorithm.label}',
                    style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                  ),
                  const SizedBox(width: 6),
                  Icon(_advancedOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: colors.inkMuted),
                ],
              ),
            ),
          ),
          if (_advancedOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '大多數服務使用預設值（6 位數、30 秒、SHA-1），除非服務另有說明否則不需更改',
                    style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
                  ),
                  const SizedBox(height: 12),
                  _choice<int>('位數', totpDigitsOptions, _digits, (d) => '$d 位數', (d) => setState(() => _digits = d)),
                  const SizedBox(height: 12),
                  _choice<int>('週期', totpPeriodOptions, _period, (p) => '$p 秒', (p) => setState(() => _period = p)),
                  const SizedBox(height: 12),
                  _choice<TotpAlgorithm>('演算法', TotpAlgorithm.values, _algorithm, (a) => a.label, (a) => setState(() => _algorithm = a)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _choice<T>(String label, List<T> options, T value, String Function(T) text, ValueChanged<T> onChanged) {
    final colors = context.colors;
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600))),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(text(option)),
                  selected: option == value,
                  onSelected: (_) => onChanged(option),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: AppText.secondary,
                    fontWeight: FontWeight.w600,
                    color: option == value ? colors.surface : colors.ink,
                  ),
                  selectedColor: colors.ink,
                  backgroundColor: colors.surface,
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
