// 加密密碼備援（escrow）用的團隊公鑰：設定或更改加密密碼時，用它把密碼封成 esc:v1 密文存進資料庫，
// 只有團隊離線保管的私鑰能解開（格式見網站 scripts/escrow.mjs，Rust 實作在 rust/core/src/escrow.rs）。
//
// 換金鑰時只改這裡（和網站 src/config/escrow.ts 一起換）。
// keyId 是公鑰（65 位元組未壓縮）SHA-256 的前 16 個十六進位字元，和公鑰不一致時不會產生備援密文。
class EscrowKey {
  EscrowKey._();

  static const publicKey = 'BKj7ilk7pBlOGtiu/wAs4Vg+7uGIw10UkXGzpDoAUUOxkryXTvOfEC8/0g7xJTi7qfC9w2IaJEMu9T/rgfBRDhY=';
  static const keyId = 'c96d275fada1e554';
}
