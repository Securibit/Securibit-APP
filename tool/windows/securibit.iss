; Securibit 的 Windows 安裝檔（Inno Setup 6）。tool/windows/build.ps1 會帶入版本與路徑：
;   ISCC.exe /DAppVersion=1.2.0 /DSourceDir=<flutter build 的 Release 資料夾> /DOutputDir=<dist> tool\windows\securibit.iss
;
; - 每個使用者各自安裝（PrivilegesRequired=lowest），裝在 %LOCALAPPDATA%\Programs\Securibit，
;   不需要系統管理員，自動更新時也不會跳出 UAC
; - 開始功能表捷徑；桌面捷徑可以選
; - 註冊 securibit、otpauth、otpauth-migration 三個連結（HKCU\Software\Classes），解除安裝時清掉
; - 介面有繁體中文（languages\ChineseTraditional.isl，來自 Inno Setup 原始碼 jrsoftware/issrc 的
;   Files/Languages，依 Inno Setup License 原樣保留）與英文，依系統語言自動選
; - App 自動更新時用 /SILENT /SUPPRESSMSGBOXES /NORESTART /UPDATE 執行（lib/features/update/update_installer.dart）：
;   先等 App 結束，裝好後自動打開新版
; - App 可能藏在系統匣（關視窗不會結束）：安裝、解除安裝前先問使用者，再請 App 自己結束（見 [Code] 的 WaitForApp）
; - 登入時自動開啟是 App 自己寫的 HKCU\...\Run 值（windows/runner/launch_at_login.cpp）：
;   安裝後指向新的位置，解除安裝時刪掉
; 這個檔案要存成有 BOM 的 UTF-8，Inno Setup 才會當成 Unicode 讀

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

#define AppName "Securibit"
#define AppExe "securibit.exe"
; 和 windows/runner/app_window.cpp 的 kMutexName 相同（App 開著時就存在）
#define AppMutexName "Securibit-com.bityo.securibit"
; 和 windows/runner/app_window.h 的 kQuitMessageName 相同：送給 App 的主視窗，效果同系統匣的「結束 Securibit」
#define AppQuitMessage "Securibit.Quit"
; App 主視窗的視窗類別與標題（windows/runner/win32_window.cpp 的 kWindowClassName、app_window.h 的 kWindowTitle）
#define AppWindowClass "FLUTTER_RUNNER_WIN32_WINDOW"
#define AppWindowTitle "Securibit"
; 登入時自動開啟（windows/runner/launch_at_login.cpp 的 kRunKey、kApprovedKey、kValueName）
#define RunKey "Software\Microsoft\Windows\CurrentVersion\Run"
#define ApprovedKey "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
#define RunValue "Securibit"

[Setup]
; 不要改：Windows 用它認得「已經安裝的 Securibit」，改了會變成另一個程式
AppId={{8916B238-7888-4A25-9349-D7FAF44267E7}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=BITYO
AppCopyright=Copyright © 2026 幣友 BITYO 🤝 靈魂之神工作室 保留一切權利。
AppPublisherURL=https://2fa.bityo.tw
AppSupportURL=https://github.com/Securibit/Securibit-APP/issues
AppUpdatesURL=https://2fa.bityo.tw/download
VersionInfoVersion={#AppVersion}
VersionInfoCompany=BITYO
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} 安裝程式
VersionInfoCopyright=Copyright © 2026 幣友 BITYO 🤝 靈魂之神工作室 保留一切權利。

PrivilegesRequired=lowest
DefaultDirName={userpf}\{#AppName}
DisableDirPage=yes
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableReadyPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

OutputDir={#OutputDir}
OutputBaseFilename=Securibit-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ShowLanguageDialog=no
LanguageDetectionMethod=uilanguage
; 安裝前已經請 App 結束並等它結束（見 [Code]），不用 Restart Manager 另外關；也不要它重新打開，裝好後由 [Run] 打開
CloseApplications=no
RestartApplications=no

[Languages]
Name: "zh_TW"; MessagesFile: "languages\ChineseTraditional.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
zh_TW.AskQuitApp=Securibit 正在執行（可能藏在工作列右下角的系統匣裡）。%n%n按「確定」結束 Securibit 並繼續。
en.AskQuitApp=Securibit is running (it may be hidden in the notification area of the taskbar).%n%nClick OK to quit Securibit and continue.
zh_TW.AppRunning=Securibit 正在執行。請從系統匣的 Securibit 圖示選「結束 Securibit」（或關閉它的視窗），再按「重試」繼續。
en.AppRunning=Securibit is running. Choose "Quit Securibit" from its icon in the notification area (or close its window), then click Retry to continue.
zh_TW.AppRunningUninstall=Securibit 正在執行。請從系統匣的 Securibit 圖示選「結束 Securibit」（或關閉它的視窗），再按「重試」解除安裝。
en.AppRunningUninstall=Securibit is running. Choose "Quit Securibit" from its icon in the notification area (or close its window), then click Retry to uninstall.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Flutter 的資源每版都整份換掉，舊版多出來的檔案不要留著
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; securibit://（群組邀請、Google 登入轉回 App）只有 Securibit 會用，解除安裝時整個刪掉
Root: HKCU; Subkey: "Software\Classes\securibit"; ValueType: string; ValueName: ""; ValueData: "URL:Securibit"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\securibit"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\securibit\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"",0"
Root: HKCU; Subkey: "Software\Classes\securibit\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
; otpauth://、otpauth-migration://（新增驗證碼、Google Authenticator 的匯出）其他驗證器也可能註冊，
; 解除安裝時還指向 Securibit 才刪（見 [Code] 的 RemoveSchemeIfOurs）
Root: HKCU; Subkey: "Software\Classes\otpauth"; ValueType: string; ValueName: ""; ValueData: "URL:otpauth"
Root: HKCU; Subkey: "Software\Classes\otpauth"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\otpauth\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"",0"
Root: HKCU; Subkey: "Software\Classes\otpauth\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\otpauth-migration"; ValueType: string; ValueName: ""; ValueData: "URL:otpauth-migration"
Root: HKCU; Subkey: "Software\Classes\otpauth-migration"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\otpauth-migration\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"",0"
Root: HKCU; Subkey: "Software\Classes\otpauth-migration\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""

[Run]
; 一般安裝：完成頁可以勾選「執行 Securibit」
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; App 自動更新（/UPDATE，靜默安裝）：裝好直接打開新版
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: IsAutoUpdate

[UninstallDelete]
; 自動更新下載的檔案與記錄（%LOCALAPPDATA%\Securibit）；設定與登入資料（%APPDATA%\BITYO\Securibit）照 macOS、Linux 的慣例留著
Type: filesandordirs; Name: "{localappdata}\Securibit"

[Code]
function HasParam(const Name: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), Name) = 0 then
    begin
      Result := True;
      Exit;
    end;
end;

// App 自動更新時帶 /UPDATE（而且是靜默安裝）
function IsAutoUpdate: Boolean;
begin
  Result := WizardSilent and HasParam('/UPDATE');
end;

function FindWindowW(ClassName, WindowName: String): HWND;
  external 'FindWindowW@user32.dll stdcall';

function AppRunning: Boolean;
begin
  Result := CheckForMutexes('{#AppMutexName}');
end;

// 等 App 結束，最多 Seconds 秒
function WaitForAppExit(Seconds: Integer): Boolean;
var
  Waited: Integer;
begin
  Waited := 0;
  while AppRunning and (Waited < Seconds * 4) do
  begin
    Sleep(250);
    Waited := Waited + 1;
  end;
  Result := not AppRunning;
end;

// 請開著的 Securibit 結束（同系統匣的「結束 Securibit」）；舊版不認得這個訊息，就由下面請使用者自己結束
function RequestAppQuit: Boolean;
var
  Wnd: HWND;
begin
  Wnd := FindWindowW('{#AppWindowClass}', '{#AppWindowTitle}');
  Result := (Wnd <> 0) and PostMessage(Wnd, RegisterWindowMessage('{#AppQuitMessage}'), 0, 0);
end;

// App 開著時讓它結束：
// - 自動更新是 App 先啟動安裝檔再自己結束，先等它最多 30 秒
// - 還開著（例如藏在系統匣）：問使用者後請它結束（靜默安裝時 /SUPPRESSMSGBOXES 選「確定」），最多等 10 秒
// - 還是開著（例如舊版不認得結束的訊息）：請使用者自己結束再按「重試」（靜默安裝時選「取消」，不安裝）
function WaitForApp(const Message: String; Wait: Boolean): Boolean;
begin
  if Wait then
    WaitForAppExit(30);
  if AppRunning and (SuppressibleMsgBox(CustomMessage('AskQuitApp'), mbConfirmation, MB_OKCANCEL, IDOK) = IDOK) then
    if RequestAppQuit then
      WaitForAppExit(10);
  while AppRunning do
    if SuppressibleMsgBox(Message, mbError, MB_RETRYCANCEL, IDCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
  Result := True;
end;

function InitializeSetup: Boolean;
begin
  Result := WaitForApp(CustomMessage('AppRunning'), HasParam('/UPDATE'));
end;

function InitializeUninstall: Boolean;
begin
  Result := WaitForApp(CustomMessage('AppRunningUninstall'), False);
end;

// Run 值裡的程式路徑：有引號時是引號裡的部分，沒有時是第一個空白之前（同 launch_at_login.cpp 的 ExecutableFromCommand）
function RunValueExe(const Command: String): String;
var
  Rest: String;
begin
  if Copy(Command, 1, 1) = '"' then
  begin
    Rest := Copy(Command, 2, Length(Command));
    if Pos('"', Rest) > 0 then
      Result := Copy(Rest, 1, Pos('"', Rest) - 1)
    else
      Result := Rest;
  end
  else if Pos(' ', Command) > 0 then
    Result := Copy(Command, 1, Pos(' ', Command) - 1)
  else
    Result := Command;
end;

// 有打開「登入時自動開啟」時改指向這次裝的位置（安裝位置變了也跟著改）；
// 指向另一份還在的 Securibit（例如免安裝版）就不動，同 App 的 LaunchAtLoginStatus
procedure UpdateRunValue;
var
  Command, Exe, Target: String;
begin
  if not RegQueryStringValue(HKCU, '{#RunKey}', '{#RunValue}', Command) then
    Exit;
  Exe := ExpandConstant('{app}\{#AppExe}');
  Target := RunValueExe(Command);
  if (CompareText(Target, Exe) = 0) or not FileExists(Target) then
    RegWriteStringValue(HKCU, '{#RunKey}', '{#RunValue}', '"' + Exe + '" --hidden');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    UpdateRunValue;
end;

// 連結還是由這份 Securibit 打開時才刪（使用者後來改用別的驗證器就不動）
procedure RemoveSchemeIfOurs(const Scheme: String);
var
  Command: String;
begin
  if RegQueryStringValue(HKCU, 'Software\Classes\' + Scheme + '\shell\open\command', '', Command) and
     (Pos(Lowercase(ExpandConstant('{app}\{#AppExe}')), Lowercase(Command)) > 0) then
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\' + Scheme);
end;

// 登入時自動開啟還指向這份 Securibit（或指向的程式已經不在）時刪掉，「設定 › 應用程式 › 啟動」的紀錄一起刪
procedure RemoveRunValueIfOurs;
var
  Command, Target: String;
begin
  if not RegQueryStringValue(HKCU, '{#RunKey}', '{#RunValue}', Command) then
    Exit;
  Target := RunValueExe(Command);
  if (CompareText(Target, ExpandConstant('{app}\{#AppExe}')) = 0) or not FileExists(Target) then
  begin
    RegDeleteValue(HKCU, '{#RunKey}', '{#RunValue}');
    RegDeleteValue(HKCU, '{#ApprovedKey}', '{#RunValue}');
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RemoveSchemeIfOurs('otpauth');
    RemoveSchemeIfOurs('otpauth-migration');
    RemoveRunValueIfOurs;
  end;
end;
