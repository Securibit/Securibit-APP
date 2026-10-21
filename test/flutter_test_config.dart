import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:securibit/src/rust/frb_generated.dart';

/*
 * flutter test 會在每個測試檔之前跑這裡：載入本機編好的 Rust 安全核心（rust/api）。
 * 先編好：cd rust && cargo build --release -p securibit_api
 */
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final name = Platform.isMacOS ? 'libsecuribit_api.dylib' : (Platform.isWindows ? 'securibit_api.dll' : 'libsecuribit_api.so');
  final path = 'rust/target/release/$name';
  if (!File(path).existsSync()) {
    throw StateError('找不到 $path，請先執行 cd rust && cargo build --release -p securibit_api');
  }
  await RustLib.init(externalLibrary: ExternalLibrary.open(path));
  await testMain();
}
