# rust_builder

FRB（flutter_rust_bridge）產生的 FFI plugin 外殼：`flutter build` 時由 cargokit 編譯 `../rust/api`（Rust 安全核心），
iOS / macOS 走 CocoaPods 的 script phase，Android 走 Gradle，Linux 走 CMake。這裡沒有要手動改的程式碼。
