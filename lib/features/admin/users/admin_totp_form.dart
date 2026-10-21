import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../codes/totp/categories.dart';
import '../../codes/totp/secret.dart';
import '../../codes/totp/totp_params.dart';
import '../../codes/totp/validate.dart';
import '../../codes/widgets/category_input.dart';
import '../admin_models.dart';
import '../admin_repository.dart' as repo;
import '../widgets/admin_widgets.dart';

/*
 * 管理員編輯使用者的一筆 2FA（同網站 AdminTotpEditModal）：名稱、類別、金鑰、位數、週期、演算法。
 * 使用者的預設群組已加密時金鑰欄位停用。只送出有變動的欄位；成功時以更新後的資料關閉。
 */
class AdminTotpForm extends StatefulWidget {
  const AdminTotpForm({
    super.key,
    required this.item,
    required this.secretLocked,
    required this.categories,
    required this.onSave,
  });

  final AdminTotpItem item;
  final bool secretLocked;
  final List<String> categories;
  final Future<Result<void>> Function(Map<String, dynamic> patch) onSave;

  @override
  State<AdminTotpForm> createState() => _AdminTotpFormState();
}

class _AdminTotpFormState extends State<AdminTotpForm> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _secret = TextEditingController(text: widget.item.secret ?? '');
  late String _category = widget.item.category;
  late int _digits = widget.item.digits;
  late int _period = widget.item.period;
  late TotpAlgorithm _algorithm = widget.item.algorithm;
  bool _showSecret = false;
  bool _saving = false;
  String? _nameError;
  String? _secretError;

  @override
  void dispose() {
    _name.dispose();
    _secret.dispose();
    super.dispose();
  }

  bool get _secretChanged => !widget.secretLocked && normalizeSecret(_secret.text) != normalizeSecret(widget.item.secret ?? '');

  Future<void> _save() async {
    final item = widget.item;
    String? nameError;
    String? secretError;
    if (_name.text.trim().isEmpty) nameError = '請輸入名稱';
    if (_secretChanged) {
      if (normalizeSecret(_secret.text).isEmpty) {
        secretError = '請輸入金鑰';
      } else if (!isValidSecret(_secret.text)) {
        secretError = secretFormatMessage;
      }
    }
    setState(() {
      _nameError = nameError;
      _secretError = secretError;
    });
    if (nameError != null || secretError != null) return;

    final nameChanged = _name.text.trim() != item.name;
    final categoryChanged = normalizeCategories(_category) != normalizeCategories(item.category);
    final patch = repo.buildTotpPatch(
      name: nameChanged ? _name.text : null,
      category: categoryChanged ? _category : null,
      secret: _secretChanged ? _secret.text : null,
      digits: _digits != item.digits ? _digits : null,
      period: _period != item.period ? _period : null,
      algorithm: _algorithm != item.algorithm ? _algorithm : null,
    );
    if (patch.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    final result = await widget.onSave(patch);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result case Err(:final message)) {
      await showErrorDialog(context, '儲存驗證碼失敗', message);
      return;
    }
    showToast(context, '已儲存');
    Navigator.of(context).pop(item.copyWith(
      name: nameChanged ? _name.text.trim() : null,
      category: categoryChanged ? normalizeCategories(_category) : null,
      secret: _secretChanged ? normalizeSecret(_secret.text) : null,
      digits: _digits,
      period: _period,
      algorithm: _algorithm,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AdminFormScaffold(
      title: '編輯驗證碼',
      saving: _saving,
      onSubmit: _save,
      children: [
        const FieldLabel('名稱'),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() => _nameError = null),
          decoration: InputDecoration(errorText: _nameError),
        ),
        const SizedBox(height: 20),
        const FieldLabel('類別'),
        CategoryInput(value: _category, suggestions: widget.categories, onChanged: (value) => setState(() => _category = value)),
        const SizedBox(height: 20),
        const FieldLabel('金鑰'),
        if (widget.secretLocked)
          const TextField(
            enabled: false,
            decoration: InputDecoration(hintText: '已加密，無法修改', helperText: '這位使用者的預設群組已加密，管理員不能查看或修改金鑰'),
          )
        else
          TextField(
            controller: _secret,
            obscureText: !_showSecret,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() => _secretError = null),
            decoration: InputDecoration(
              errorText: _secretError,
              helperText: 'Base32 格式（A–Z、2–7），空白與小寫會自動轉換',
              suffixIcon: IconButton(
                tooltip: _showSecret ? '隱藏金鑰' : '顯示金鑰',
                onPressed: () => setState(() => _showSecret = !_showSecret),
                icon: Icon(_showSecret ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              ),
            ),
          ),
        const SizedBox(height: 20),
        _choice<int>('位數', totpDigitsOptions, _digits, (d) => '$d 位數', (d) => setState(() => _digits = d)),
        const SizedBox(height: 12),
        _choice<int>('週期', totpPeriodOptions, _period, (p) => '$p 秒', (p) => setState(() => _period = p)),
        const SizedBox(height: 12),
        _choice<TotpAlgorithm>('演算法', TotpAlgorithm.values, _algorithm, (a) => a.label, (a) => setState(() => _algorithm = a)),
        if (_secretChanged) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.small)),
            child: Text(
              '更換金鑰後會產生完全不同的驗證碼，使用者原本綁定的服務可能就無法登入',
              style: TextStyle(fontSize: AppText.secondary, color: colors.alarm, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ],
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
                  onSelected: _saving ? null : (_) => onChanged(option),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: AppText.secondary,
                    fontWeight: FontWeight.w600,
                    color: option == value ? colors.surface : colors.ink,
                  ),
                  selectedColor: colors.ink,
                  backgroundColor: colors.surface1,
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
