import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/menubar/linux_autostart.dart';

// Linux 登入時自動開啟：autostart 檔的路徑、內容、Exec 的跳脫與開關
void main() {
  group('路徑', () {
    test('預設放在 ~/.config/autostart，檔名是 application id', () {
      final autostart = LinuxAutostart.current(environment: {'HOME': '/home/ann'}, resolvedExecutable: '/opt/securibit/securibit');
      expect(autostart.file.path, '/home/ann/.config/autostart/com.bityo.securibit.desktop');
      expect(autostart.executable, '/opt/securibit/securibit');
    });

    test('有設定 XDG_CONFIG_HOME 時用它，不是絕對路徑時忽略', () {
      expect(
        LinuxAutostart.current(environment: {'HOME': '/home/ann', 'XDG_CONFIG_HOME': '/cfg'}, resolvedExecutable: '/x').file.path,
        '/cfg/autostart/com.bityo.securibit.desktop',
      );
      expect(
        LinuxAutostart.current(environment: {'HOME': '/home/ann', 'XDG_CONFIG_HOME': 'cfg'}, resolvedExecutable: '/x').file.path,
        '/home/ann/.config/autostart/com.bityo.securibit.desktop',
      );
    });

    test('用 AppImage 執行時指向 AppImage 檔，不是暫時掛載的程式', () {
      final autostart = LinuxAutostart.current(
        environment: {'HOME': '/home/ann', 'APPIMAGE': '/home/ann/Apps/Securibit-0.3.0-x86_64.AppImage'},
        resolvedExecutable: '/tmp/.mount_SecuriAbc/usr/lib/securibit/securibit',
      );
      expect(autostart.executable, '/home/ann/Apps/Securibit-0.3.0-x86_64.AppImage');
    });
  });

  group('內容', () {
    test('desktop entry 的必要欄位', () {
      final entry = LinuxAutostart.desktopEntry('/opt/securibit/securibit');
      expect(entry, startsWith('[Desktop Entry]\n'));
      expect(entry, contains('\nType=Application\n'));
      expect(entry, contains('\nName=Securibit\n'));
      expect(entry, contains('\nExec="/opt/securibit/securibit"\n'));
      expect(entry, contains('\nIcon=com.bityo.securibit\n'));
      expect(LinuxAutostart.isEnabledEntry(entry), isTrue);
    });

    test('Exec 跳脫空白、引號、錢字號、反斜線與百分比，並能讀回原本的路徑', () {
      expect(LinuxAutostart.execValue('/home/a b/securibit'), '"/home/a b/securibit"');
      expect(LinuxAutostart.execValue(r'/x/"q"/$HOME/`c`'), r'"/x/\\"q\\"/\\$HOME/\\`c\\`"');
      expect(LinuxAutostart.execValue(r'/x/a\b'), r'"/x/a\\\\b"');
      expect(LinuxAutostart.execValue('/x/100%'), '"/x/100%%"');
      for (final path in ['/opt/securibit/securibit', '/home/a b/My Apps/securibit', r'/x/"q"/$HOME/`c`/a\b/100%']) {
        expect(LinuxAutostart.execPath(LinuxAutostart.desktopEntry(path)), path);
      }
    });

    test('使用者在桌面環境關掉時視為關閉', () {
      expect(LinuxAutostart.isEnabledEntry('[Desktop Entry]\nExec=a\nHidden=true\n'), isFalse);
      expect(LinuxAutostart.isEnabledEntry('[Desktop Entry]\nExec=a\nX-GNOME-Autostart-enabled=false\n'), isFalse);
      // 其他段落的同名欄位不算
      expect(LinuxAutostart.isEnabledEntry('[Desktop Entry]\nExec=a\n[Desktop Action x]\nHidden=true\n'), isTrue);
    });

    test('沒有加引號的 Exec 取第一個字', () {
      expect(LinuxAutostart.execPath('[Desktop Entry]\nExec=/usr/bin/securibit %U\n'), '/usr/bin/securibit');
      expect(LinuxAutostart.execPath('[Desktop Entry]\nName=x\n'), isNull);
    });
  });

  group('開關', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('autostart'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('打開時建立資料夾並寫入，關掉時刪除', () async {
      final autostart = LinuxAutostart(configHome: '${temp.path}/config', executable: '/opt/securibit/securibit');
      expect(await autostart.isEnabled(), isFalse);

      await autostart.setEnabled(true);
      expect(await autostart.isEnabled(), isTrue);
      expect(autostart.file.readAsStringSync(), LinuxAutostart.desktopEntry('/opt/securibit/securibit'));
      expect(File('${autostart.file.path}.tmp').existsSync(), isFalse);

      // 再打開一次只是覆寫
      await autostart.setEnabled(true);
      expect(await autostart.isEnabled(), isTrue);

      await autostart.setEnabled(false);
      expect(autostart.file.existsSync(), isFalse);
      expect(await autostart.isEnabled(), isFalse);
      // 已經關掉時再關一次不會出錯
      await autostart.setEnabled(false);
    });

    test('檔案裡的程式不在了就改指向目前的程式；還在就不動', () async {
      final exe = File('${temp.path}/securibit')..writeAsStringSync('');
      final old = LinuxAutostart(configHome: temp.path, executable: '${temp.path}/gone/securibit');
      await old.setEnabled(true);

      final current = LinuxAutostart(configHome: temp.path, executable: exe.path);
      expect(await current.refresh(), isTrue);
      expect(LinuxAutostart.execPath(current.file.readAsStringSync()), exe.path);

      // 另一份還存在的程式（例如另外安裝的版本）不會被改掉
      final other = File('${temp.path}/other')..writeAsStringSync('');
      expect(await LinuxAutostart(configHome: temp.path, executable: other.path).refresh(), isTrue);
      expect(LinuxAutostart.execPath(current.file.readAsStringSync()), exe.path);
    });

    test('關閉時 refresh 不會建立檔案', () async {
      final autostart = LinuxAutostart(configHome: temp.path, executable: '/x');
      expect(await autostart.refresh(), isFalse);
      expect(autostart.file.existsSync(), isFalse);
    });
  });
}
