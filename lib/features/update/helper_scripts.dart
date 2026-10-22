/*
 * 替換 App 的小程式（用 /bin/sh 執行）：App 不能在執行中把自己換掉，所以交給它等 App 結束後再換。
 * 腳本內容是固定的，路徑一律用參數傳進去，不拼進腳本裡（路徑有空白、引號也不會出事）。
 * 參數：<App 的 PID> <新版> <要替換的位置> <裝完要不要重新打開：1／0> <記錄檔>
 * 步驟：等 App 結束 → 把新版複製到同一個資料夾的暫存名稱 → 舊的移到暫存名稱 → 新的放進去 → 成功才刪掉舊的；
 * 中間任何一步失敗都還原，舊版照常能用。暫存名稱不帶 .app，系統不會把它當成另一個 Securibit。
 */

// 兩個平台共用的部分：記錄、只跑一次、等 App 結束、替換與還原。copy 與 relaunch 由各平台補上
String _script({required String header, required String copy, required String afterInstall, required String relaunch}) => '''#!/bin/sh
# $header
# 由 Securibit 產生（lib/features/update/helper_scripts.dart），用完會留在更新的暫存資料夾，下次開 App 時清掉
pid="\$1"; new="\$2"; target="\$3"; relaunch="\$4"; log="\$5"
exec >>"\$log" 2>&1
echo "== \$(date '+%Y-%m-%d %H:%M:%S') 更新 \$target"

parent="\$(dirname "\$target")"
staged="\$parent/.securibit-update-new-\$\$"
backup="\$parent/.securibit-update-old-\$\$"

reopen() {
$relaunch
}

finish() {
  if [ "\$relaunch" = 1 ]; then reopen; fi
  exit "\$1"
}

# 同一份更新只跑一次
lock="\$new.lock"
if ! mkdir "\$lock" 2>/dev/null; then
  echo "已經有另一個更新在跑"
  exit 0
fi
trap 'rmdir "\$lock" 2>/dev/null' EXIT

# 等 App 結束（最多兩分鐘）
n=0
while kill -0 "\$pid" 2>/dev/null; do
  n=\$((n + 1))
  if [ "\$n" -gt 1200 ]; then
    echo "App 一直沒有結束，這次不更新"
    exit 1
  fi
  sleep 0.1
done

if [ ! -d "\$new" ]; then
  echo "找不到新版：\$new"
  finish 1
fi
rm -rf "\$staged" "\$backup"
if ! $copy; then
  echo "複製新版失敗"
  rm -rf "\$staged"
  finish 1
fi
if ! mv "\$target" "\$backup"; then
  echo "移開舊版失敗"
  rm -rf "\$staged"
  finish 1
fi
if ! mv "\$staged" "\$target"; then
  echo "放入新版失敗，還原舊版"
  mv "\$backup" "\$target"
  rm -rf "\$staged"
  finish 1
fi
rm -rf "\$backup"
$afterInstall
rm -rf "\$new"
echo "完成"
finish 0
''';

/// macOS：替換 .app（ditto 保留簽章與屬性），拿掉隔離屬性後用 open 打開
final macInstallScript = _script(
  header: 'Securibit 自動更新（macOS）：等 App 結束後把舊的 .app 換成新版',
  copy: 'ditto "\$new" "\$staged"',
  afterInstall: '''xattr -dr com.apple.quarantine "\$target" 2>/dev/null || true
touch "\$target"''',
  relaunch: '  open "\$target" || true',
);

/// Linux（.tar.gz 解開的資料夾）：替換整個資料夾，重新打開時脫離這個程序
final linuxInstallScript = _script(
  header: 'Securibit 自動更新（Linux .tar.gz）：等 App 結束後把舊的資料夾換成新版',
  copy: 'cp -a "\$new" "\$staged"',
  afterInstall: 'chmod 755 "\$target/securibit" 2>/dev/null || true',
  relaunch: '''  if command -v setsid >/dev/null 2>&1; then
    setsid "\$target/securibit" >/dev/null 2>&1 </dev/null &
  else
    nohup "\$target/securibit" >/dev/null 2>&1 </dev/null &
  fi''',
);

/// Linux（.deb）：apt 裝好後等目前的 App 結束再打開新版（同一個使用者只能跑一個 Securibit）。
/// 參數：App 的 PID、要打開的執行檔
const linuxRelaunchScript = r'''while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
exec "$2"''';
