import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show ExternalLibrary;

import '../src/rust/api/secrets.dart' as core;
import '../src/rust/frb_generated.dart';
import 'secure_store.dart';

/*
 * Rust 安全核心（rust/core、rust/api）的初始化與 App 鎖定時的「封存」。
 * 金鑰、加密群組的金鑰都放在 Rust 的記憶體，Dart 端只拿到驗證碼；
 * 這台裝置的金鑰（封離線快取、記住加密群組金鑰用）存在系統安全儲存，啟動時交給 Rust 一次。
 */

const _deviceKeyName = 'device-key';

/// App 啟動時呼叫一次（runApp 之前）
Future<void> initSecurityCore() async {
  await RustLib.init(externalLibrary: _bundledLibrary());
  await _installDeviceKey();
}

// 只載入 App 自己包進去的 Rust 函式庫（cargokit 建置）：
// FRB 預設會先找目前目錄的 rust/api/target/release/ 與環境變數指定的目錄，安全核心不要讓外面換掉
ExternalLibrary? _bundledLibrary() {
  if (Platform.isIOS || Platform.isMacOS) return ExternalLibrary.open('securibit_api.framework/securibit_api');
  if (Platform.isAndroid || Platform.isLinux) return ExternalLibrary.open('libsecuribit_api.so');
  return null;
}

Future<void> _installDeviceKey() async {
  String? stored;
  try {
    stored = await secureStore.read(key: _deviceKeyName);
  } catch (_) {
    // 讀不到安全儲存（例如 Linux 沒有 Secret Service）：Rust 改用這次執行才有效的隨機金鑰，離線快取下次打不開
    return;
  }
  if (stored != null && core.deviceKeyInstall(keyBase64: stored)) return;
  try {
    await secureStore.write(key: _deviceKeyName, value: core.deviceKeyGenerate());
  } catch (_) {
    // 存不了就只在這次有效
  }
}

/// App 鎖定時清掉 Rust 記憶體裡的全部金鑰，解鎖前不再接受新的；解鎖後各個畫面從離線快取（或重新連線）放回來
class SecretSeal {
  SecretSeal._();

  static final ValueNotifier<bool> sealed = ValueNotifier(false);

  static void seal() {
    core.secretsSeal();
    sealed.value = true;
  }

  static void unseal() {
    core.secretsUnseal();
    sealed.value = false;
  }

  /// 登出：清掉全部金鑰與加密群組的金鑰
  static void clearAll() => core.secretsClearAll();
}
