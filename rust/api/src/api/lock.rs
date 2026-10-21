// App 鎖定的圖形 / 密碼雜湊；存的格式（salt、iterations、hash）和之前的 Dart 版相同

use flutter_rust_bridge::frb;
use securibit_core::lock;

pub struct LockHashData {
    pub salt: Vec<u8>,
    pub iterations: u32,
    pub hash: Vec<u8>,
}

/// 產生新的鹽並雜湊（在背景執行緒計算，不會卡住解鎖畫面的動畫）
pub fn lock_hash(secret: String, iterations: u32) -> LockHashData {
    let hashed = lock::hash(&secret, iterations);
    LockHashData { salt: hashed.salt, iterations: hashed.iterations, hash: hashed.hash }
}

/// 檢查輸入的圖形或密碼和存的雜湊是否相同（固定時間比對）
pub fn lock_verify(secret: String, salt: Vec<u8>, iterations: u32, hash: Vec<u8>) -> bool {
    lock::verify(&secret, &lock::LockHash { salt, iterations, hash })
}

/// 固定時間比對
#[frb(sync)]
pub fn constant_time_equals(a: Vec<u8>, b: Vec<u8>) -> bool {
    lock::constant_time_eq(&a, &b)
}
