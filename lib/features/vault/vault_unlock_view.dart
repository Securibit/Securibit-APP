import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/lock_backdrop.dart';
import '../../core/widgets/logo.dart';
import '../groups/group_models.dart';
import 'vault_controller.dart';
import 'vault_settings_section.dart' show confirmVaultReset;

/*
 * 加密群組還沒解鎖時顯示（同網站 GroupCodes 的鎖定畫面 + VaultUnlock）。
 * 不是擁有者的人解不開；忘記密碼只能清空加密群組重來（confirmVaultReset）。
 * 版面照設計稿：置中的「解鎖＋盾牌＋Securibit」標題、藥丸輸入框與按鈕、底部幣友署名；
 * 漸層底由外層 CodeListPane 的 LockBackdrop 提供（連同上面的群組標題一起蓋）。
 */
class VaultUnlockView extends StatefulWidget {
  const VaultUnlockView({super.key, required this.group});

  final GroupSummary group;

  @override
  State<VaultUnlockView> createState() => _VaultUnlockViewState();
}

class _VaultUnlockViewState extends State<VaultUnlockView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _remember = false;
  bool _visible = false;
  bool _pending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final passphrase = _controller.text;
    if (_pending) return;
    // 還沒輸入時按「解鎖」只把游標移回輸入框
    if (passphrase.isEmpty) {
      _focus.requestFocus();
      return;
    }
    setState(() {
      _pending = true;
      _error = null;
    });
    final error = await context.read<VaultController>().unlock(passphrase, remember: _remember);
    if (!mounted) return;
    setState(() {
      _pending = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vault = context.watch<VaultController>();
    final group = widget.group;
    final locked = group.isOwner && vault.status == VaultStatus.locked;

    final message = !group.isOwner
        ? '這個群組已由擁有者加密，只有擁有者能查看驗證碼'
        : vault.status == VaultStatus.off
            ? '這個群組已加密，但找不到你的加密設定，請重新整理'
            : '輸入你設定的加密密碼來解鎖加密群組';

    // 內容在可捲動的區域裡置中，署名貼底；鍵盤彈出或視窗太矮時改成捲動
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: (constraints.maxWidth - 48).clamp(0.0, double.infinity), minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FittedBox(fit: BoxFit.scaleDown, child: UnlockTitle()),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                    ),
                    if (group.isOwner && vault.status == VaultStatus.loading) ...[
                      const SizedBox(height: 28),
                      const Center(child: CircularProgressIndicator.adaptive()),
                    ],
                    if (locked) ..._form(colors),
                  ],
                ),
              ),
              const Padding(padding: EdgeInsets.only(top: 32, bottom: 20), child: BityoCredit()),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _form(AppColors colors) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 深色的輸入框比軟底再暗一點，貼近漸層底（設計稿的顏色）
    final fill = dark ? const Color(0xFF1E1F24) : colors.surface1;
    final line = dark ? const Color(0xFF3A3B41) : colors.line;
    OutlineInputBorder pill(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: color, width: width));
    final fallback = AppPlatform.fontFamilyFallback;

    return [
      const SizedBox(height: 28),
      TextField(
        controller: _controller,
        focusNode: _focus,
        obscureText: !_visible,
        autofocus: true,
        enabled: !_pending,
        autofillHints: const [AutofillHints.password],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _unlock(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        style: TextStyle(fontSize: AppText.secondary, color: colors.ink),
        decoration: InputDecoration(
          hintText: '加密密碼',
          hintStyle: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
          errorText: _error,
          isDense: true,
          fillColor: fill,
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 4, 12),
          border: pill(line),
          enabledBorder: pill(line),
          disabledBorder: pill(line),
          focusedBorder: pill(colors.accent.withValues(alpha: 0.6), 1.5),
          errorBorder: pill(colors.alarm),
          focusedErrorBorder: pill(colors.alarm, 1.5),
          suffixIconConstraints: const BoxConstraints.tightFor(width: 48, height: 40),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: _visible ? '隱藏密碼' : '顯示密碼',
              onPressed: () => setState(() => _visible = !_visible),
              padding: EdgeInsets.zero,
              iconSize: 20,
              color: colors.inkMuted,
              icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: '登出或按「立即鎖定」就會忘記',
          child: MergeSemantics(
            child: InkWell(
              onTap: _pending ? null : () => setState(() => _remember = !_remember),
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 8, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: Checkbox(
                        value: _remember,
                        onChanged: _pending ? null : (value) => setState(() => _remember = value ?? false),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        side: BorderSide(color: colors.inkMuted, width: 1.5),
                        activeColor: colors.brand,
                        checkColor: colors.accentInk,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('在這台裝置記住', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      // 跟設計稿一樣一直是綠色；空白時按下只會回到輸入框（見 _unlock）
      FilledButton(
        onPressed: _pending ? null : _unlock,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamilyFallback: fallback),
        ),
        child: Text(_pending ? '解鎖中…' : '解鎖'),
      ),
      const SizedBox(height: 10),
      Center(
        child: TextButton(
          onPressed: _pending ? null : () => confirmVaultReset(context),
          style: TextButton.styleFrom(
            foregroundColor: colors.alarm,
            textStyle: TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w400, fontFamilyFallback: fallback),
          ),
          child: const Text('忘記密碼？'),
        ),
      ),
    ];
  }
}
