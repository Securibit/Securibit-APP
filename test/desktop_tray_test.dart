import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/window_visibility.dart';
import 'package:securibit/features/menubar/desktop_tray.dart';

// 常駐圖示的平台差異（macOS 選單列、Linux 與 Windows 系統匣）、設定頁的說明，以及 Windows 登入時藏在系統匣的參數
void main() {
  group('平台差異', () {
    test('macOS、Linux、Windows 都有常駐圖示，其他平台沒有', () {
      expect(TrayPlatform.macos.supported, isTrue);
      expect(TrayPlatform.linux.supported, isTrue);
      expect(TrayPlatform.windows.supported, isTrue);
      expect(TrayPlatform.none.supported, isFalse);
    });

    test('macOS 叫「選單列」，Linux、Windows 叫「系統匣」', () {
      expect(TrayPlatform.macos.place, '選單列');
      expect(TrayPlatform.linux.place, '系統匣');
      expect(TrayPlatform.windows.place, '系統匣');
    });

    test('只有 Linux 在視窗藏著時每秒送完整內容（Windows 打開選單前才要內容）', () {
      expect(TrayPlatform.linux.refreshWhileHidden, isTrue);
      expect(TrayPlatform.windows.refreshWhileHidden, isFalse);
      expect(TrayPlatform.macos.refreshWhileHidden, isFalse);
    });

    test('登入時自動開啟：macOS、Windows 由原生端處理，Linux 在 Dart 寫 autostart 檔', () {
      expect(TrayPlatform.macos.nativeLaunchAtLogin, isTrue);
      expect(TrayPlatform.windows.nativeLaunchAtLogin, isTrue);
      expect(TrayPlatform.linux.nativeLaunchAtLogin, isFalse);
      expect(TrayPlatform.none.nativeLaunchAtLogin, isFalse);
    });
  });

  group('設定頁的說明', () {
    List<String> notes(
      TrayPlatform platform, {
      bool showInTray = true,
      bool showCodes = true,
      LaunchAtLoginState launch = LaunchAtLoginState.disabled,
    }) =>
        trayNotes(platform, showInTray: showInTray, showCodes: showCodes, launch: launch);

    test('Windows：留在系統匣、選「結束 Securibit」才結束，提示圖示可能收在「^」裡，不提 GNOME', () {
      final lines = notes(TrayPlatform.windows);
      expect(lines.first, '關閉視窗後 Securibit 會留在系統匣，點圖示就能複製驗證碼；選「結束 Securibit」才會結束');
      expect(lines.any((l) => l.contains('「^」')), isTrue);
      expect(lines.any((l) => l.contains('GNOME')), isFalse);
      expect(lines.any((l) => l.contains('⌘Q')), isFalse);
    });

    test('沒打開常駐時關視窗就結束，不提「^」', () {
      final lines = notes(TrayPlatform.windows, showInTray: false);
      expect(lines, ['關閉視窗就會結束 Securibit']);
    });

    test('不顯示驗證碼時說明選單只能打開或結束', () {
      expect(notes(TrayPlatform.windows, showCodes: false), contains('系統匣的選單不列出驗證碼，只能打開 Securibit 或結束'));
      expect(notes(TrayPlatform.macos, showCodes: false), contains('選單列的選單不列出驗證碼，只能打開 Securibit 或結束'));
    });

    test('Windows 在「設定 › 應用程式 › 啟動」被關掉時，說明要到那裡打開', () {
      final lines = notes(TrayPlatform.windows, launch: LaunchAtLoginState.requiresApproval);
      expect(lines, contains('已在「設定 › 應用程式 › 啟動」關掉 Securibit，要在那裡打開才會自動開啟'));
      expect(lines.any((l) => l.contains('登入項目')), isFalse);
    });

    test('macOS、Linux 的說明維持原樣', () {
      expect(notes(TrayPlatform.macos).first, '關閉視窗後 Securibit 會留在選單列，點圖示就能複製驗證碼；按 ⌘Q 才會結束');
      expect(notes(TrayPlatform.macos, launch: LaunchAtLoginState.unsupported), contains('登入時自動開啟需要 macOS 13 以上'));
      expect(
        notes(TrayPlatform.macos, launch: LaunchAtLoginState.requiresApproval),
        contains('要到「系統設定 › 一般 › 登入項目」允許 Securibit 才會自動開啟'),
      );
      final linux = notes(TrayPlatform.linux);
      expect(linux.first, startsWith('關閉視窗後 Securibit 會留在系統匣'));
      expect(linux.any((l) => l.contains('GNOME')), isTrue);
      expect(linux.any((l) => l.contains('「^」')), isFalse);
    });

    test('只有 macOS 會說明版本太舊不能自動開啟', () {
      expect(notes(TrayPlatform.windows, launch: LaunchAtLoginState.unsupported).any((l) => l.contains('macOS 13')), isFalse);
    });
  });

  group('Windows 登入時藏在系統匣', () {
    test('命令列有 --hidden 才一開始就藏著', () {
      expect(WindowVisibility.launchedHidden(['--hidden']), isTrue);
      expect(WindowVisibility.launchedHidden(['securibit://invite/abc', '--hidden']), isTrue);
      expect(WindowVisibility.launchedHidden([]), isFalse);
      expect(WindowVisibility.launchedHidden(['securibit://invite/abc']), isFalse);
      expect(WindowVisibility.launchedHidden(['--hidden-ish']), isFalse);
    });
  });
}
