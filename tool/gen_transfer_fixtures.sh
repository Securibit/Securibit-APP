#!/usr/bin/env bash
# 用網站自己的 src/lib/totp（migration.ts、importText.ts、otpauth.ts）產生 test/fixtures/web_totp_transfer.json，
# 給 test/migration_test.dart 比對 App 的移植結果（需要 node 22+，網站要先 npm install，用它的 typescript 轉譯）
# 用法：tool/gen_transfer_fixtures.sh [網站路徑，預設 ../Securibit-Web]
set -euo pipefail
WEB="$(cd "${1:-$(dirname "$0")/../../Securibit-Web}" && pwd)"
OUT="$(cd "$(dirname "$0")/.." && pwd)/test/fixtures/web_totp_transfer.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 轉成 CommonJS，@/ 路徑換成同一層；crud.ts 用到的 supabase 換成空物件
cat > "$TMP/transpile.cjs" <<'JS'
const ts = require(process.argv[3] + '/node_modules/typescript');
const fs = require('fs'); const path = require('path');
const out = process.argv[2];
const files = {
  Totp: 'src/types/Totp/Totp.ts', base32: 'src/lib/totp/base32.ts', crud: 'src/lib/totp/crud.ts',
  categories: 'src/lib/totp/categories.ts', otpauth: 'src/lib/totp/otpauth.ts', migration: 'src/lib/totp/migration.ts',
  importText: 'src/lib/totp/importText.ts',
};
for (const [name, file] of Object.entries(files)) {
  let src = fs.readFileSync(path.join(process.argv[3], file), 'utf8');
  src = src.replace(/'@\/types\/Totp\/Totp'/g, "'./Totp'").replace(/'@\/config\/supabase'/g, "'./supabase'").replace(/'@\/types\/Vault\/Vault'/g, "'./Totp'");
  const js = ts.transpileModule(src, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  fs.writeFileSync(path.join(out, name + '.js'), js);
}
fs.writeFileSync(path.join(out, 'supabase.js'), 'exports.supabase = {};');
JS

cat > "$TMP/fixtures.cjs" <<'JS'
const dir = process.argv[2];
const { parseMigrationUri, buildMigrationUris, canExportToGoogle } = require(dir + '/migration.js');
const { parseImportText } = require(dir + '/importText.js');
const { buildOtpauthUri } = require(dir + '/otpauth.js');

const varint = (out, v) => { while (v >= 0x80) { out.push((v % 0x80) | 0x80); v = Math.floor(v / 0x80); } out.push(v); };
const vf = (out, f, v) => { varint(out, f * 8); varint(out, v); };
const bf = (out, f, bytes) => { varint(out, f * 8 + 2); varint(out, bytes.length); out.push(...bytes); };
const str = (s) => [...Buffer.from(s, 'utf8')];
const otp = ({ secret, name, issuer, algorithm, digits, type, counter, extra }) => {
  const o = [];
  if (secret) bf(o, 1, secret);
  if (name !== undefined) bf(o, 2, str(name));
  if (issuer !== undefined) bf(o, 3, str(issuer));
  if (algorithm !== undefined) vf(o, 4, algorithm);
  if (digits !== undefined) vf(o, 5, digits);
  if (type !== undefined) vf(o, 6, type);
  if (counter !== undefined) vf(o, 7, counter);
  if (extra) { varint(o, 9 * 8 + 1); o.push(1,2,3,4,5,6,7,8); varint(o, 10 * 8 + 5); o.push(9,9,9,9); }
  return o;
};
const payload = (items, batch) => {
  const o = [];
  for (const i of items) bf(o, 1, otp(i));
  vf(o, 2, 1);
  if (batch) { vf(o, 3, batch.size); vf(o, 4, batch.index); vf(o, 5, batch.id); }
  return Buffer.from(o);
};
const uri = (buf, raw = false) => {
  const b64 = buf.toString('base64');
  return `otpauth-migration://offline?data=${raw ? b64 : encodeURIComponent(b64)}`;
};

const full = payload([
  { secret: [0x48,0x65,0x6c,0x6c,0x6f,0x21,0xde,0xad,0xbe,0xef], name: 'alice@example.com', issuer: 'GitHub', algorithm: 1, digits: 1, type: 2 },
  { secret: [0xfb,0xef,0xbe,0xfb,0xef,0xbe,1,2,3,4], name: 'Example:bob', issuer: '', algorithm: 2, digits: 2, type: 2 },
  { secret: [1,2,3,4,5], name: 'hotp', issuer: 'X', algorithm: 1, digits: 1, type: 1, counter: 5 },
  { secret: [1,2,3,4,5], name: 'md5', issuer: 'X', algorithm: 4, digits: 1, type: 2 },
  { secret: [9,8,7,6,5,4,3,2,1,0], name: '中文帳號', issuer: '銀行', algorithm: 0, digits: 0, type: 0 },
  { secret: [0xff,0xfe,0xfd,0xfc,0xfb,0xfa,0xf9,0xf8,0xf7,0xf6,0xf5,0xf4,0xf3,0xf2,0xf1,0xf0,0xef,0xee,0xed,0xec], name: 'Same:Same', issuer: 'Same', algorithm: 3, digits: 1, type: 2, counter: 300, extra: true },
  { secret: [], name: 'empty', issuer: '', algorithm: 1, digits: 1, type: 2 },
  { secret: [7,7,7], name: '  ', issuer: '', type: 2 },
], { size: 3, index: 1, id: 12345 });

const onlyHotp = payload([{ secret: [1,2,3], name: 'h', type: 1 }]);
const empty = payload([]);
const single = payload([{ secret: [1,2,3,4,5,6,7,8,9,10], name: 'Solo', issuer: 'Acme', algorithm: 1, digits: 1, type: 2 }], { size: 1, index: 0, id: 1 });
const wire3 = Buffer.from([0x0b, 0x01]);

const parseCases = {
  full: uri(full),
  fullRaw: uri(full, true),
  onlyHotp: uri(onlyHotp),
  empty: uri(empty),
  single: uri(single),
  truncated: uri(full.subarray(0, 30)),
  wire3: uri(wire3),
  badBase64: 'otpauth-migration://offline?data=%%%',
  noData: 'otpauth-migration://offline',
  otherScheme: 'https://example.com/?data=abc',
  notUrl: 'hello world',
  upper: '  ' + uri(single).replace('otpauth-migration', 'OTPAUTH-MIGRATION') + '  ',
};
const parsed = Object.fromEntries(Object.entries(parseCases).map(([k, v]) => [k, { input: v, output: parseMigrationUri(v) }]));

// 產生：固定 batchId
Math.random = () => 0.5;
const algs = ['SHA-1', 'SHA-256', 'SHA-512'];
const exportItems = Array.from({ length: 23 }, (_, i) => ({
  id: String(i),
  name: i === 3 ? 'GitHub - 張三@example.com' : `Item ${i}`,
  secret: i === 5 ? 'jbsw y3dp-ehpk 3pxp==' : ['JBSWY3DPEHPK3PXP', 'GEZDGNBVGY3TQOJQ', 'MZXW6YTBOI', 'KRSXG5BAMJ4XIZLT'][i % 4],
  category: i % 2 ? '工作' : '',
  digits: i % 3 === 0 ? 8 : 6,
  period: 30,
  algorithm: algs[i % 3],
}));
const built = buildMigrationUris(exportItems);
const roundtrip = built.map((u) => parseMigrationUri(u));
const google = [
  { name: 'a', secret: 'A', category: '', period: 30 },
  { name: 'b', secret: 'A', category: '', period: 60 },
  { name: 'c', secret: 'A', category: '' },
].map(canExportToGoogle);

const texts = {
  mixed: [
    '# Securibit TOTP 備份',
    '',
    'otpauth://totp/GitHub:me%40example.com?secret=jbswy3dpehpk3pxp&issuer=GitHub',
    '   otpauth://totp/Acme?secret=JBSWY3DPEHPK3PXP&digits=8&period=60&algorithm=SHA512&category=%E5%B7%A5%E4%BD%9C   ',
    'otpauth://hotp/Old?secret=JBSWY3DP',
    'this is a very long line that is definitely not a link at all',
    'short',
    uri(full),
  ].join('\r\n'),
  singleBad: 'otpauth://totp/a?secret=abc1',
  empty: '\n  \n# only comment\n',
  single: 'otpauth://totp/Solo?secret=JBSWY3DP',
  onlyHotpMigration: uri(onlyHotp),
};
const importParsed = Object.fromEntries(Object.entries(texts).map(([k, v]) => [k, { input: v, output: parseImportText(v) }]));

const backup = exportItems.slice(0, 4).map(buildOtpauthUri);

process.stdout.write(JSON.stringify({ parse: parsed, exportItems, built, roundtrip, google, importText: importParsed, backup }, null, 1));
JS

node "$TMP/transpile.cjs" "$TMP" "$WEB"
mkdir -p "$(dirname "$OUT")"
node "$TMP/fixtures.cjs" "$TMP" > "$OUT"
echo "已寫入 $OUT"
