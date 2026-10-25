# Securibit App

修改前先讀網站專案的施工規範 `../Securibit-Web/docs/security-rules.md`（安全與邏輯規則，網站、App、資料庫共用），照裡面的規則施工；做完再對一遍。

App 特別注意：

- 權限檢查在伺服器的 RPC，App 只負責隱藏按鈕；功能、文字、錯誤訊息要和網站一致
- 加密設定讀回來先檢查格式；設定或變更加密密碼一定附託管密文（格式見 `../Securibit-Web/scripts/escrow.mjs`）
- 圖片一律上傳到網站的 `/api/profile/photo`，不接受網址
- 舊版 App 還會連線一段時間，改動要相容
