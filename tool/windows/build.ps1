# 建置 Windows 版並打包（在 Windows 上跑；Mac 上用 make windows WIN_REMOTE=user@host 會把原始碼送過去再跑這支）。
#
#   powershell -NoProfile -File tool\windows\build.ps1
#
# 產出（dist\，檔名帶 pubspec.yaml 的版本）：
#   Securibit-<版本>-windows-x64-setup.exe   安裝檔（Inno Setup，每個使用者各自安裝，會自動更新）
#   Securibit-<版本>-windows-x64.zip         免安裝版：解開後執行 Securibit\securibit.exe（不會自動更新）
#   SHA256SUMS.txt                          dist\ 裡這個版本所有產出的 SHA-256（同 make checksums）
# 這次的產出檔名寫在 dist\.last-build（一行一個），make windows 靠它把產出拉回 Mac。
#
# 需要：Flutter 3.35.3、Visual Studio 2022（或 Build Tools）的「使用 C++ 的桌面開發」、Rust（rustup，stable-msvc）、Inno Setup 6。
# 環境變數：
#   FLUTTER   flutter 的路徑（預設先找 PATH，再找 %USERPROFILE%\flutter\bin\flutter.bat）
#   ISCC      Inno Setup 編譯器 ISCC.exe 的路徑（預設找 PATH 與 Inno Setup 6 的安裝位置）
#   OUT_DIR   產出放這裡（預設 <專案>\dist）
#
# 這個檔案要存成有 BOM 的 UTF-8，Windows PowerShell 5.1 才不會把中文讀錯

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 3
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

function Fail([string]$message) {
  [Console]::Error.WriteLine($message)
  exit 1
}

# 外部指令失敗就停下來（$ErrorActionPreference 管不到外部程式的結束碼）
function Invoke-Checked([string]$what, [scriptblock]$run) {
  & $run
  if ($LASTEXITCODE -ne 0) { Fail "$what 失敗（結束碼 $LASTEXITCODE）" }
}

$src = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out = if ($env:OUT_DIR) { $env:OUT_DIR } else { Join-Path $src 'dist' }

if (-not (Test-Path (Join-Path $src 'env.json'))) {
  Fail '找不到 env.json：先 copy env.example.json env.json 並填入連線設定（見 README）'
}

# 從 Microsoft Store 裝的 PowerShell 7（WindowsApps 裡的 pwsh.exe）在 SSH 等非互動的登入裡執行會「存取被拒」，
# flutter.bat 找到它就會失敗；這次建置拿掉 WindowsApps，讓 flutter 改用系統內建的 Windows PowerShell
$env:Path = (($env:Path -split ';') | Where-Object { $_ -and $_ -notmatch '\\WindowsApps' }) -join ';'
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
if ((Test-Path $cargoBin) -and -not (($env:Path -split ';') -contains $cargoBin)) { $env:Path = "$cargoBin;$env:Path" }

# 工具
$flutter = $env:FLUTTER
if (-not $flutter) {
  $found = Get-Command flutter.bat, flutter -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $flutter = $found.Source }
  elseif (Test-Path "$env:USERPROFILE\flutter\bin\flutter.bat") { $flutter = "$env:USERPROFILE\flutter\bin\flutter.bat" }
}
$iscc = $env:ISCC
if (-not $iscc) {
  $found = Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $iscc = $found.Source }
  else {
    $iscc = @(
      "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
      "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
      "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  }
}
$missing = @()
if (-not $flutter) { $missing += 'flutter（Flutter 3.35.3）' }
if (-not (Get-Command cargo -ErrorAction SilentlyContinue) -or -not (Get-Command rustup -ErrorAction SilentlyContinue)) {
  $missing += 'cargo／rustup（用 https://rustup.rs 安裝 Rust，選 stable-msvc）'
}
if (-not $iscc) { $missing += 'Inno Setup 6（https://jrsoftware.org/isinfo.php，或 winget install JRSoftware.InnoSetup）' }
if ($missing.Count -gt 0) { Fail ("建置 Windows 版還缺：`n" + (($missing | ForEach-Object { "  - $_" }) -join "`n")) }

# pubspec 的 version: 1.2.0+3 → 1.2.0
$fullVersion = (Select-String -Path (Join-Path $src 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$version = $fullVersion.Split('+')[0]
$arch = 'x64'
$setupName = "Securibit-$version-windows-$arch-setup.exe"
$zipName = "Securibit-$version-windows-$arch.zip"

Write-Host "==> flutter build windows（Securibit $fullVersion）"
Push-Location $src
try {
  Invoke-Checked 'flutter pub get' { & $flutter pub get }
  Invoke-Checked 'flutter build windows' { & $flutter build windows --release '--dart-define-from-file=env.json' }
} finally {
  Pop-Location
}
$release = Join-Path $src "build\windows\$arch\runner\Release"
foreach ($file in 'securibit.exe', 'securibit_api.dll', 'flutter_windows.dll') {
  if (-not (Test-Path (Join-Path $release $file))) { Fail "建置結果裡沒有 $file（$release）" }
}

# Visual C++ 執行階段（msvcp140.dll、vcruntime140.dll…）跟著 App 放在同一個資料夾（Microsoft 允許的 app-local 部署）：
# 乾淨的 Windows 不一定裝了 VC++ 可轉散發套件，少了它 securibit.exe 與 Rust 核心都打不開
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = if (Test-Path $vswhere) { & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath } else { $null }
$crt = if ($vsPath) {
  Get-ChildItem -Path "$vsPath\VC\Redist\MSVC\*\$arch\Microsoft.VC14*.CRT" -Directory -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
} else { $null }
if (-not $crt) { Fail '找不到 Visual C++ 執行階段（Visual Studio 的 VC\Redist\MSVC\<版本>\x64\Microsoft.VC14x.CRT）' }
Copy-Item -Path (Join-Path $crt.FullName '*.dll') -Destination $release -Force
Write-Host "==> Visual C++ 執行階段：$($crt.FullName)"

New-Item -ItemType Directory -Force -Path $out | Out-Null

# 免安裝版：zip 裡是 Securibit\ 資料夾。用 .NET 一個一個加，路徑分隔一律用 /（其他系統解開也正常）
Write-Host "==> $zipName"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zipPath = Join-Path $out $zipName
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
$zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
  Get-ChildItem -Path $release -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($release.Length).TrimStart('\').Replace('\', '/')
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, "Securibit/$relative", [IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
} finally {
  $zip.Dispose()
}

# 安裝檔
Write-Host "==> $setupName"
$setupPath = Join-Path $out $setupName
if (Test-Path $setupPath) { Remove-Item -Force $setupPath }
Invoke-Checked 'Inno Setup' {
  & $iscc /Q "/DAppVersion=$version" "/DSourceDir=$release" "/DOutputDir=$out" (Join-Path $PSScriptRoot 'securibit.iss')
}
if (-not (Test-Path $setupPath)) { Fail "Inno Setup 沒有產生 $setupName" }

# 這次的產出（make windows 依這份拉回 Mac）；換行用 LF
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $out '.last-build'), "$setupName`n$zipName`n", $utf8)

# dist\ 裡這個版本的所有產出（和 Makefile 的 CHECKSUM_FILES 同一組副檔名），格式同 sha256sum：「<sha256>  <檔名>」
$patterns = '*.dmg', '*.zip', '*.ipa', '*.apk', '*.aab', '*.deb', '*.tar.gz', '*.exe'
[string[]]$names = @(Get-ChildItem -Path $out -File | Where-Object {
  $name = $_.Name
  $name.Contains($version) -and ($patterns | Where-Object { $name -like $_ })
} | ForEach-Object { $_.Name })
[Array]::Sort($names, [StringComparer]::Ordinal)
$sums = ($names | ForEach-Object { '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 (Join-Path $out $_)).Hash.ToLowerInvariant(), $_ }) -join "`n"
[IO.File]::WriteAllText((Join-Path $out 'SHA256SUMS.txt'), "$sums`n", $utf8)

Write-Host ''
foreach ($name in $setupName, $zipName) {
  $size = (Get-Item (Join-Path $out $name)).Length / 1MB
  Write-Host ('→ {0}  ({1:N1} MB)' -f (Join-Path $out $name), $size)
}
Write-Host "→ $(Join-Path $out 'SHA256SUMS.txt')"
