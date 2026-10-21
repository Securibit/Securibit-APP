import 'dart:io';

/*
 * Linux 的「登入時自動開啟」：在 ~/.config/autostart（或 $XDG_CONFIG_HOME/autostart）放一個 .desktop 檔，
 * 桌面環境登入時會執行裡面的 Exec（XDG Autostart 規範，GNOME、KDE、XFCE、Cinnamon 都支援）。
 * Exec 指向目前執行中的程式。
 * 純 Dart、路徑可以注入，方便測試。
 */
class LinuxAutostart {
  LinuxAutostart({required this.configHome, required this.executable});

  /// 依目前的環境變數與執行檔決定路徑
  factory LinuxAutostart.current({Map<String, String>? environment, String? resolvedExecutable}) {
    final env = environment ?? Platform.environment;
    final xdg = env['XDG_CONFIG_HOME'];
    // 規範：XDG_CONFIG_HOME 不是絕對路徑時當作沒設定
    final configHome = xdg != null && xdg.startsWith('/') ? xdg : '${env['HOME'] ?? ''}/.config';
    return LinuxAutostart(configHome: configHome, executable: resolvedExecutable ?? Platform.resolvedExecutable);
  }

  // 和 App 的 application id 相同，桌面環境才對得上 App 的圖示與名稱
  static const fileName = 'com.bityo.securibit.desktop';

  final String configHome;
  final String executable;

  File get file => File('$configHome/autostart/$fileName');

  Future<bool> isEnabled() async {
    if (!await file.exists()) return false;
    try {
      return isEnabledEntry(await file.readAsString());
    } on FileSystemException {
      return false;
    }
  }

  /// 打開時寫入（先寫暫存檔再改名，不會留下寫一半的檔案），關掉時刪除
  Future<void> setEnabled(bool enabled) async {
    if (!enabled) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(desktopEntry(executable), flush: true);
    await temp.rename(file.path);
  }

  /// 讀取目前狀態；已打開但檔案裡的程式不在了（例如 .tar.gz 解開的資料夾換了位置）就改指向目前的程式
  Future<bool> refresh() async {
    if (!await isEnabled()) return false;
    try {
      final path = execPath(await file.readAsString());
      if (path != executable && (path == null || !await File(path).exists())) await setEnabled(true);
    } on FileSystemException {
      // 改不了就維持原狀
    }
    return true;
  }

  static String desktopEntry(String executable) => '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=Securibit\n'
      'Comment=登入時開啟 Securibit 兩步驟驗證器\n'
      'Exec=${execValue(executable)}\n'
      'Icon=com.bityo.securibit\n'
      'Terminal=false\n'
      'X-GNOME-Autostart-enabled=true\n';

  /// Exec 的值：路徑一律加雙引號，引號內的 " ` $ \ 前面加反斜線、% 寫成 %%；
  /// 之後再套用字串值的跳脫（反斜線變兩個），所以路徑裡的一個反斜線最後是四個
  static String execValue(String path) {
    final quoted = '"${path.replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}').replaceAll('%', '%%')}"';
    return quoted.replaceAll(r'\', r'\\');
  }

  /// 從 .desktop 檔的內容取回 Exec 的程式路徑（execValue 的反向）；沒有 Exec 時是 null
  static String? execPath(String entry) {
    final line = _value(entry, 'Exec');
    if (line == null) return null;
    final value = _unescapeString(line);
    if (!value.startsWith('"')) return value.split(' ').first.replaceAll('%%', '%');
    final buffer = StringBuffer();
    for (var i = 1; i < value.length; i++) {
      final c = value[i];
      if (c == r'\' && i + 1 < value.length) {
        buffer.write(value[++i]);
      } else if (c == '"') {
        break;
      } else {
        buffer.write(c);
      }
    }
    return buffer.toString().replaceAll('%%', '%');
  }

  /// Hidden=true 或 X-GNOME-Autostart-enabled=false 代表使用者在桌面環境的設定裡關掉了
  static bool isEnabledEntry(String entry) =>
      _value(entry, 'Hidden')?.trim() != 'true' && _value(entry, 'X-GNOME-Autostart-enabled')?.trim() != 'false';

  // 只看 [Desktop Entry] 這一段
  static String? _value(String entry, String key) {
    var inMain = false;
    for (final raw in entry.split('\n')) {
      final line = raw.trimRight();
      if (line.startsWith('[')) {
        inMain = line == '[Desktop Entry]';
        continue;
      }
      if (!inMain) continue;
      final eq = line.indexOf('=');
      if (eq <= 0 || line.substring(0, eq).trim() != key) continue;
      return line.substring(eq + 1).trimLeft();
    }
    return null;
  }

  static String _unescapeString(String value) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final c = value[i];
      if (c != r'\' || i + 1 >= value.length) {
        buffer.write(c);
        continue;
      }
      final next = value[++i];
      buffer.write(switch (next) { 's' => ' ', 'n' => '\n', 't' => '\t', 'r' => '\r', _ => next });
    }
    return buffer.toString();
  }
}
