import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../groups/group_models.dart';
import 'vault_controller.dart';
import 'vault_settings_section.dart' show confirmVaultReset;

/*
 * 加密群組還沒解鎖時顯示（同網站 GroupCodes 的鎖定畫面 + VaultUnlock）。
 * 不是擁有者的人解不開；忘記密碼只能清空加密群組重來（confirmVaultReset）。
 */
class VaultUnlockView extends StatefulWidget {
  const VaultUnlockView({super.key, required this.group});

  final GroupSummary group;

  @override
  State<VaultUnlockView> createState() => _VaultUnlockViewState();
}

class _VaultUnlockViewState extends State<VaultUnlockView> {
  final _controller = TextEditingController();
  bool _remember = false;
  bool _pending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final passphrase = _controller.text;
    if (passphrase.isEmpty || _pending) return;
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

    final message = !group.isOwner
        ? '這個群組已由擁有者加密，只有擁有者能查看驗證碼'
        : vault.status == VaultStatus.off
            ? '這個群組已加密，但找不到你的加密設定，請重新整理'
            : '這個群組已加密，輸入加密密碼解鎖後才能查看';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.medium)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.lock_rounded, size: 18, color: colors.inkMuted),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(message, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted))),
            ],
          ),
          if (group.isOwner && vault.status == VaultStatus.loading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator.adaptive()),
          ],
          if (group.isOwner && vault.status == VaultStatus.locked) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: true,
              autofocus: true,
              enabled: !_pending,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _unlock(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: '加密密碼',
                errorText: _error,
                fillColor: colors.surface,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _remember,
              onChanged: _pending ? null : (value) => setState(() => _remember = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              activeColor: colors.accent,
              title: Text(
                '在這台裝置記住（登出或按「立即鎖定」就會忘記）',
                style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
              ),
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => FilledButton(
                onPressed: _pending || _controller.text.isEmpty ? null : _unlock,
                child: Text(_pending ? '解鎖中…' : '解鎖'),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _pending ? null : () => confirmVaultReset(context),
                style: TextButton.styleFrom(foregroundColor: colors.alarm),
                child: const Text('忘記密碼？'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
