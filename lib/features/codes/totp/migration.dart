import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/result.dart';
import '../../../src/rust/api/totp.dart' as core;
import 'secret.dart';
import 'totp_params.dart';

/*
 * Google Authenticator「匯出帳戶」的 QR Code（同網站 src/lib/totp/migration.ts）：otpauth-migration://offline?data=<base64>
 * data 是 protobuf 編碼的 MigrationPayload：
 *   1 otp_parameters（重複）  2 version  3 batch_size  4 batch_index  5 batch_id
 * OtpParameters：
 *   1 secret（bytes）  2 name  3 issuer  4 algorithm  5 digits  6 type  7 counter
 * Google Authenticator 不記錄週期，一律 30 秒。
 */

const _algorithms = {1: TotpAlgorithm.sha1, 2: TotpAlgorithm.sha256, 3: TotpAlgorithm.sha512};
const _digits = {1: 6, 2: 8};
const _typeHotp = 1;
const _typeTotp = 2;

/// 一張 QR Code 放幾筆（與 Google Authenticator 自己匯出時相同，太多 QR Code 會密到掃不出來）
const migrationBatchSize = 10;

const _invalidLink = '不是有效的 Google Authenticator 匯出連結';

// ---------- 最小的 protobuf 讀寫 ----------

class _Field {
  const _Field(this.field, {this.varint, this.bytes});

  final int field;
  final int? varint;
  final Uint8List? bytes;
}

class _ProtoError implements Exception {
  const _ProtoError(this.message);
  final String message;
}

(int, int) _readVarint(Uint8List buf, int pos) {
  var result = 0;
  var shift = 0;
  int byte;
  do {
    // 超過 64 位元的不是正常資料
    if (pos >= buf.length || shift >= 64) throw const _ProtoError('資料不完整');
    byte = buf[pos++];
    result |= (byte & 0x7f) << shift;
    shift += 7;
  } while (byte & 0x80 != 0);
  return (result, pos);
}

List<_Field> _readFields(Uint8List buf) {
  final fields = <_Field>[];
  var pos = 0;
  while (pos < buf.length) {
    final int key;
    (key, pos) = _readVarint(buf, pos);
    final field = key ~/ 8;
    final wire = key % 8;

    if (wire == 0) {
      final int value;
      (value, pos) = _readVarint(buf, pos);
      fields.add(_Field(field, varint: value));
    } else if (wire == 2) {
      final int length;
      (length, pos) = _readVarint(buf, pos);
      if (pos + length > buf.length) throw const _ProtoError('資料不完整');
      fields.add(_Field(field, bytes: Uint8List.sublistView(buf, pos, pos + length)));
      pos += length;
    } else if (wire == 1) {
      pos += 8;
    } else if (wire == 5) {
      pos += 4;
    } else {
      throw const _ProtoError('不支援的資料格式');
    }
  }
  return fields;
}

void _writeVarint(List<int> out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.add((v % 0x80) | 0x80);
    v ~/= 0x80;
  }
  out.add(v);
}

void _writeVarintField(List<int> out, int field, int value) {
  _writeVarint(out, field * 8);
  _writeVarint(out, value);
}

void _writeBytesField(List<int> out, int field, List<int> bytes) {
  _writeVarint(out, field * 8 + 2);
  _writeVarint(out, bytes.length);
  out.addAll(bytes);
}

// ---------- 解析 ----------

/// 分好幾張 QR Code 匯出時，這是第幾張（index 從 1 開始）
class MigrationBatch {
  const MigrationBatch({required this.index, required this.size});

  final int index;
  final int size;

  @override
  bool operator ==(Object other) => other is MigrationBatch && other.index == index && other.size == size;

  @override
  int get hashCode => Object.hash(index, size);
}

class MigrationData {
  const MigrationData({required this.items, required this.skipped, this.batch});

  final List<TotpInput> items;
  // HOTP 等不支援的項目數
  final int skipped;
  final MigrationBatch? batch;
}

/// 組出顯示名稱（同網站 otpauth.ts 的 composeName）：label 可能是「Issuer:account」或只有 account，issuer 優先。
/// 結果為「Issuer - account」，只有其中一個就用那個
String composeName(String label, [String issuerParam = '']) {
  final separator = label.indexOf(':');
  final labelIssuer = separator >= 0 ? label.substring(0, separator).trim() : '';
  final account = (separator >= 0 ? label.substring(separator + 1) : label).trim();
  final issuer = issuerParam.trim().isNotEmpty ? issuerParam.trim() : labelIssuer;

  if (issuer.isNotEmpty && account.isNotEmpty && issuer != account) return '$issuer - $account';
  if (issuer.isNotEmpty) return issuer;
  if (account.isNotEmpty) return account;
  return '未命名';
}

// 同瀏覽器的 URLSearchParams：+ 變空白，解不開的 % 編碼保留原樣（之後 base64 解析才算失敗）
String? _queryParam(Uri url, String name) {
  for (final pair in url.query.split('&')) {
    final separator = pair.indexOf('=');
    final key = separator >= 0 ? pair.substring(0, separator) : pair;
    if (_decodeQuery(key) != name) continue;
    return separator >= 0 ? _decodeQuery(pair.substring(separator + 1)) : '';
  }
  return null;
}

String _decodeQuery(String value) {
  try {
    return Uri.decodeQueryComponent(value);
  } on Object {
    return value.replaceAll('+', ' ');
  }
}

Uint8List _fromBase64(String value) {
  // 網址參數裡的 + 有時會被當成空白
  return base64.decode(base64.normalize(value.replaceAll(' ', '+')));
}

TotpInput? _parseOtpParameters(Uint8List buf) {
  Uint8List secret = Uint8List(0);
  var name = '';
  var issuer = '';
  var algorithm = 1;
  var digits = 1;
  var type = _typeTotp;

  for (final f in _readFields(buf)) {
    if (f.field == 1 && f.bytes != null) secret = f.bytes!;
    if (f.field == 2 && f.bytes != null) name = utf8.decode(f.bytes!, allowMalformed: true);
    if (f.field == 3 && f.bytes != null) issuer = utf8.decode(f.bytes!, allowMalformed: true);
    if (f.field == 4 && f.varint != null) algorithm = f.varint!;
    if (f.field == 5 && f.varint != null) digits = f.varint!;
    if (f.field == 6 && f.varint != null) type = f.varint!;
  }

  // HOTP（計數型）與 MD5 不支援；0 代表未指定，視為預設值
  if (type == _typeHotp || secret.isEmpty) return null;
  if (algorithm != 0 && !_algorithms.containsKey(algorithm)) return null;

  return TotpInput(
    name: composeName(name, issuer),
    secret: core.base32Encode(bytes: secret),
    digits: _digits[digits] ?? TotpDefaults.digits,
    period: TotpDefaults.period,
    algorithm: _algorithms[algorithm] ?? TotpDefaults.algorithm,
  );
}

/// 解析 Google Authenticator 的匯出連結；略過 HOTP 與不支援的演算法
Result<MigrationData> parseMigrationUri(String text) {
  final Uri url;
  try {
    url = Uri.parse(text.trim());
  } on FormatException {
    return const Err(_invalidLink);
  }
  final data = _queryParam(url, 'data');
  if (url.scheme != 'otpauth-migration' || data == null || data.isEmpty) return const Err(_invalidLink);

  try {
    final items = <TotpInput>[];
    var skipped = 0;
    var batchSize = 1;
    var batchIndex = 0;

    for (final f in _readFields(_fromBase64(data))) {
      if (f.field == 1 && f.bytes != null) {
        final item = _parseOtpParameters(f.bytes!);
        if (item != null) {
          items.add(item);
        } else {
          skipped++;
        }
      }
      if (f.field == 3 && f.varint != null) batchSize = f.varint!;
      if (f.field == 4 && f.varint != null) batchIndex = f.varint!;
    }

    if (items.isEmpty) {
      return Err(skipped > 0 ? '裡面只有 HOTP（計數型）驗證碼，目前不支援' : '這個匯出 QR Code 裡沒有驗證碼');
    }
    return Ok(MigrationData(
      items: items,
      skipped: skipped,
      batch: batchSize > 1 ? MigrationBatch(index: batchIndex + 1, size: batchSize) : null,
    ));
  } on _ProtoError {
    return const Err('無法解析匯出資料，QR Code 可能不完整');
  } on FormatException {
    return const Err('無法解析匯出資料，QR Code 可能不完整');
  }
}

// ---------- 產生 ----------

/// Google Authenticator 只支援 30 秒週期，其他週期的無法匯出到它
bool canExportToGoogle(TotpInput item) => item.period == TotpDefaults.period;

List<int> _encodeOtpParameters(TotpInput item) {
  final out = <int>[];
  _writeBytesField(out, 1, core.base32Decode(input: normalizeSecret(item.secret)).bytes);
  _writeBytesField(out, 2, utf8.encode(item.name));
  final algorithm = _algorithms.entries.firstWhere((e) => e.value == item.algorithm, orElse: () => _algorithms.entries.first);
  _writeVarintField(out, 4, algorithm.key);
  _writeVarintField(out, 5, item.digits == 8 ? 2 : 1);
  _writeVarintField(out, 6, _typeTotp);
  return out;
}

/// 產生可讓 Google Authenticator「匯入帳戶」掃描的連結，每 [migrationBatchSize] 筆一張。
/// batchId 只給測試固定用，平常隨機
List<String> buildMigrationUris(List<TotpInput> items, {int? batchId}) {
  final batches = <List<TotpInput>>[
    for (var i = 0; i < items.length; i += migrationBatchSize) items.sublist(i, min(i + migrationBatchSize, items.length)),
  ];
  final id = batchId ?? Random.secure().nextInt(0x7fffffff);

  return [
    for (var index = 0; index < batches.length; index++)
      () {
        final out = <int>[];
        for (final item in batches[index]) {
          _writeBytesField(out, 1, _encodeOtpParameters(item));
        }
        _writeVarintField(out, 2, 1);
        _writeVarintField(out, 3, batches.length);
        _writeVarintField(out, 4, index);
        _writeVarintField(out, 5, id);
        return 'otpauth-migration://offline?data=${Uri.encodeComponent(base64.encode(out))}';
      }(),
  ];
}
