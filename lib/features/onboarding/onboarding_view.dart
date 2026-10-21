import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/sliding_selection.dart';
import '../codes/totp/otp.dart';
import '../codes/widgets/countdown_ring.dart';
import 'live_demo.dart';

/*
 * 手機沒登入時的介紹頁：左右滑動，下面的點表示第幾頁，最後一頁「開始使用」進登入頁。
 * 每一頁的圖都是 App 真的畫面（會跳的驗證碼、群組成員、加密開關），內容照網站首頁。
 */
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key, required this.onDone});

  // 按「開始使用」或「略過」
  final VoidCallback onDone;

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _Page {
  const _Page({required this.title, required this.body, required this.visual});

  final String title;
  final String body;
  final Widget visual;
}

const _pages = [
  _Page(
    title: '打開就是你的驗證碼',
    body: '每 30 秒自動換一組，點一下就複製；換手機也不用重新綁定',
    visual: DemoCodeList(),
  ),
  _Page(
    title: '和家人、同事共用',
    body: '把驗證碼放進群組，用身分組決定誰看得到驗證碼、誰拿得到金鑰',
    visual: _GroupVisual(),
  ),
  _Page(
    title: '金鑰只有你看得到',
    body: '替群組設一組加密密碼，金鑰在你的裝置上先加密才上傳；伺服器存的是密文，我們也解不開',
    visual: _VaultVisual(),
  ),
  _Page(
    title: '網站和 App 同步',
    body: '用同一個 Google 帳號登入，在 2fa.bityo.tw 新增的驗證碼，App 馬上看得到',
    visual: _SyncVisual(),
  ),
];

class _OnboardingViewState extends State<OnboardingView> {
  final _controller = PageController();
  int _page = 0;

  bool get _last => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      widget.onDone();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(_page + 1);
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fast = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 右上角的略過，最後一頁不需要
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AnimatedOpacity(
                    opacity: _last ? 0 : 1,
                    duration: fast,
                    child: IgnorePointer(
                      ignoring: _last,
                      child: TextButton(
                        onPressed: widget.onDone,
                        style: TextButton.styleFrom(foregroundColor: colors.inkMuted),
                        child: const Text('略過'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => _PageBody(page: _pages[index]),
              ),
            ),
            const SizedBox(height: 12),
            _Dots(controller: _controller, count: _pages.length),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AnimatedSwitcher(
                    duration: fast,
                    child: _last
                        ? FilledButton(
                            key: const ValueKey('start'),
                            onPressed: _next,
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                            child: const Text('開始使用'),
                          )
                        : FilledButton(
                            key: const ValueKey('next'),
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: colors.surface1,
                              foregroundColor: colors.ink,
                            ),
                            child: const Text('繼續'),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // 圖在上面的彈性空間裡置中，標題與說明固定在同一個高度，換頁時文字不會上下跳
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  // 螢幕太矮放不下時整張圖等比縮小，不裁切
                  builder: (context, constraints) => Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(width: constraints.maxWidth, child: page.visual),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 132),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      page.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      page.body,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: AppText.body, height: 1.5, color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 頁數的點：目前那頁拉長，滑動時跟著手指連續變化
class _Dots extends StatelessWidget {
  const _Dots({required this.controller, required this.count});

  final PageController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients && controller.position.haveDimensions ? controller.page ?? 0 : 0.0;
        return Semantics(
          label: '第 ${page.round() + 1} 頁，共 $count 頁',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                Builder(builder: (context) {
                  final t = (1 - (page - i).abs()).clamp(0.0, 1.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8 + 16 * t,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color.lerp(colors.line, colors.ink, t),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

// 第二頁：群組成員與各自看得到什麼，每隔幾秒換一個人（也可以自己點）
class _GroupVisual extends StatefulWidget {
  const _GroupVisual();

  @override
  State<_GroupVisual> createState() => _GroupVisualState();
}

class _Member {
  const _Member(this.name, this.role, this.canSeeSecret);

  final String name;
  final String role;
  final bool canSeeSecret;
}

const _members = [
  _Member('Andy', '擁有者', true),
  _Member('小安', '工程師', false),
  _Member('Mia', '客服', false),
];

class _GroupVisualState extends State<_GroupVisual> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _members.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pick(int index) {
    // 自己點了就不再自動換
    _timer?.cancel();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final member = _members[_index];
    final divider = Divider(height: 0.5, thickness: 0.5, color: colors.line.withValues(alpha: 0.6));
    final fast = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220);
    return DemoCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: '幣友 BITYO 團隊帳號', style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: ' · ${_members.length} 位成員', style: TextStyle(color: colors.inkMuted)),
              ]),
              style: const TextStyle(fontSize: AppText.body),
            ),
          ),
          divider,
          Padding(
            padding: const EdgeInsets.all(6),
            child: SlidingSelection(
              selectedIndex: _index,
              color: colors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.small),
              children: [
                for (var i = 0; i < _members.length; i++)
                  _MemberRow(member: _members[i], onTap: () => _pick(i)),
              ],
            ),
          ),
          divider,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: fast,
                  layoutBuilder: _alignStart,
                  child: Text(
                    '${member.name} 看到的',
                    key: ValueKey(member.name),
                    style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600, color: colors.inkMuted),
                  ),
                ),
                const SizedBox(height: 6),
                DemoCodeRow(account: demoAccounts.first, showAccount: false, codeSize: 24),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.key_rounded, size: 18, color: colors.inkMuted),
                    const SizedBox(width: 6),
                    Text('金鑰', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: fast,
                        layoutBuilder: _alignStart,
                        child: Text(
                          member.canSeeSecret ? 'JBSW Y3DZ EBSW Y3DZ' : '不會傳到他的裝置',
                          key: ValueKey(member.canSeeSecret),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppText.secondary,
                            fontWeight: FontWeight.w600,
                            color: member.canSeeSecret ? colors.ink : colors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _alignStart(Widget? current, List<Widget> previous) =>
    Stack(alignment: AlignmentDirectional.centerStart, children: [...previous, ?current]);

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onTap});

  final _Member member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              UserAvatar(name: member.name, size: 32),
              const SizedBox(width: 10),
              Expanded(child: Text(member.name, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: colors.surface2, borderRadius: BorderRadius.circular(100)),
                child: Text(member.role, style: const TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 76,
                child: Text(
                  member.canSeeSecret ? '看得到金鑰' : '只看驗證碼',
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w500, color: colors.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 第三頁：加密開關，進來時自己打開；打開後資料庫裡存的金鑰變成密文（可以自己切換看看）
class _VaultVisual extends StatefulWidget {
  const _VaultVisual();

  @override
  State<_VaultVisual> createState() => _VaultVisualState();
}

class _VaultVisualState extends State<_VaultVisual> {
  bool _on = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _on = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fast = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 260);
    return DemoCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('金鑰加密', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('用你自己的密碼，在裝置上加密後才上傳', style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: _on,
                  onChanged: (value) {
                    _timer?.cancel();
                    setState(() => _on = value);
                  },
                ),
              ],
            ),
          ),
          Divider(height: 0.5, thickness: 0.5, color: colors.line.withValues(alpha: 0.6)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('伺服器上存的金鑰', style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w600, color: colors.inkMuted)),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: fast,
                  layoutBuilder: _alignStart,
                  child: Row(
                    key: ValueKey(_on),
                    children: [
                      Icon(_on ? Icons.lock_rounded : Icons.lock_open_rounded, size: 18, color: _on ? colors.accent : colors.inkMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _on ? 'enc:v1:mT4xQ9…Qk9aWw==' : 'JBSW Y3DZ EBSW Y3DZ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 第四頁：網站和 App 上同一筆驗證碼，一起跳
class _SyncVisual extends StatelessWidget {
  const _SyncVisual();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _SyncCard(icon: Icons.language_rounded, label: '網站')),
        SizedBox(width: 12),
        Expanded(child: _SyncCard(icon: Icons.phone_iphone_rounded, label: 'App')),
      ],
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final account = demoAccounts.first;
    return DemoCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 16),
      child: DemoTicker(
        builder: (context, now) {
          final code = DemoCode.at(account, now);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: colors.inkMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label, style: TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600, color: colors.inkMuted)),
                  ),
                  CountdownRing(secondsLeft: code.secondsLeft, period: 30, expiring: code.expiring, size: 28),
                ],
              ),
              const SizedBox(height: 14),
              Text(account.name, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: RollingCode(
                  code: formatOtp(code.code),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, height: 1.2, color: code.expiring ? colors.alarm : colors.ink),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
