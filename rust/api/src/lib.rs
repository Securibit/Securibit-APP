/*!
 * flutter_rust_bridge 的薄薄一層：把 securibit-core 接給 Flutter。
 * api/ 底下的 pub fn 都會產生對應的 Dart 函式（lib/src/rust/api/）；
 * 全域狀態（記憶體裡的金鑰、加密群組金鑰、這台裝置的金鑰）放在 state.rs，只有這個 crate 碰得到。
 */

pub mod api;
mod frb_generated;
mod net;
mod state;
