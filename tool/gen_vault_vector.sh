#!/usr/bin/env bash
# 用網站自己的 src/lib/vault/crypto.ts 產生 test/vault_test.dart 的測試向量（需要 node 22+）
# 用法：tool/gen_vault_vector.sh [網站路徑，預設 ../Securibit-Web]
set -euo pipefail
WEB="${1:-$(dirname "$0")/../../Securibit-Web}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 只把型別 import 換成本地型別，其餘照原樣
sed "s#^import { VaultInfo } from '@/types/Vault/Vault';#type VaultInfo = { v: 1; salt: string; iterations: number; check: string };#" \
  "$WEB/src/lib/vault/crypto.ts" > "$TMP/crypto.ts"

cat > "$TMP/gen.ts" <<'TS'
import { createVault, encryptText, unlockVault, decryptText } from './crypto.ts';

const passphrase = '正確的馬 battery staple';
const secret = 'JBSWY3DPEHPK3PXP';
const { info, key } = await createVault(passphrase);
const cipher = await encryptText(key, secret);
const again = await unlockVault(info, passphrase);
if (!again || (await decryptText(again, cipher)) !== secret) throw new Error('self check failed');
console.log(JSON.stringify({ passphrase, secret, vault: info, cipher }, null, 2));
TS

node --experimental-strip-types --no-warnings "$TMP/gen.ts"
