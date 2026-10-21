// Rust 端的全域狀態：記憶體裡的金鑰、加密群組解開的金鑰、這台裝置的金鑰（封離線快取用）

use std::sync::{LazyLock, Mutex, MutexGuard};

use securibit_core::store::SecretStore;
use securibit_core::vault::VaultKey;

#[derive(Default)]
pub(crate) struct State {
    pub store: SecretStore,
    // 加密群組解鎖後的金鑰
    pub vault: Option<VaultKey>,
    // 這台裝置的金鑰：Dart 從系統安全儲存讀出來交給這裡；沒有安全儲存時用這次執行才有效的隨機金鑰
    pub device: Option<VaultKey>,
}

impl State {
    pub fn device_key(&mut self) -> &VaultKey {
        self.device.get_or_insert_with(VaultKey::random)
    }
}

static STATE: LazyLock<Mutex<State>> = LazyLock::new(|| Mutex::new(State::default()));

/// 取得全域狀態；之前有人 panic 時照樣可以用（裡面只有金鑰，不會半套）
pub(crate) fn state() -> MutexGuard<'static, State> {
    STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}
