import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/result.dart';
import 'package:securibit/features/codes/totp/import_text.dart';
import 'package:securibit/features/codes/totp/migration.dart';
import 'package:securibit/features/codes/totp/otpauth.dart';
import 'package:securibit/features/codes/totp/totp_params.dart';

/*
 * Google Authenticator 匯出連結與整批匯入文字的解析／產生，跟網站比對：
 * test/fixtures/web_totp_transfer.json 是網站 src/lib/totp 對同一組輸入的輸出（tool/gen_transfer_fixtures.sh 產生）
 */

final Map<String, dynamic> web = jsonDecode(File('test/fixtures/web_totp_transfer.json').readAsStringSync());

Map<String, dynamic> itemJson(TotpInput item) => {
      'name': item.name,
      'secret': item.secret,
      'category': item.category,
      'digits': item.digits,
      'period': item.period,
      'algorithm': item.algorithm.label,
    };

TotpInput fromWeb(Map<String, dynamic> json) => TotpInput(
      name: json['name'] as String,
      secret: json['secret'] as String,
      category: json['category'] as String? ?? '',
      digits: json['digits'] as int? ?? TotpDefaults.digits,
      period: json['period'] as int? ?? TotpDefaults.period,
      algorithm: TotpAlgorithm.fromLabel(json['algorithm'] as String?),
    );

// 轉成網站 MigrationResult 的 JSON 形狀方便比對
Map<String, dynamic> migrationJson(Result<MigrationData> result) => switch (result) {
      Ok(:final data) => {
          'success': true,
          'data': data.items.map(itemJson).toList(),
          'skipped': data.skipped,
          if (data.batch != null) 'batch': {'index': data.batch!.index, 'size': data.batch!.size},
        },
      Err(:final message) => {'success': false, 'message': message},
    };

Map<String, dynamic> importJson(ImportTextResult result) => {
      'items': result.items.map(itemJson).toList(),
      'errors': result.errors,
      if (result.batch != null) 'batch': {'index': result.batch!.index, 'size': result.batch!.size},
    };

void main() {
  group('解析 otpauth-migration 連結', () {
    final cases = (web['parse'] as Map<String, dynamic>).cast<String, Map<String, dynamic>>();
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () {
        expect(migrationJson(parseMigrationUri(value['input'] as String)), value['output']);
      });
    }

    test('包含 HOTP、MD5、空金鑰與分批資訊', () {
      final data = parseMigrationUri(cases['full']!['input'] as String).dataOrNull!;
      expect(data.items.length, 5);
      expect(data.skipped, 3);
      expect(data.batch, const MigrationBatch(index: 2, size: 3));
      expect(data.items.first.name, 'GitHub - alice@example.com');
      expect(data.items[2].name, '銀行 - 中文帳號');
    });
  });

  group('產生 otpauth-migration 連結', () {
    final items = (web['exportItems'] as List).cast<Map<String, dynamic>>().map(fromWeb).toList();

    test('與網站相同（固定 batch id）', () {
      // 網站產生時 Math.random 固定為 0.5
      final uris = buildMigrationUris(items, batchId: (0.5 * 0x7fffffff).floor());
      expect(uris, web['built']);
      expect(uris.length, 3);
    });

    test('解析回來與網站相同', () {
      final uris = buildMigrationUris(items);
      final roundtrip = uris.map((uri) => migrationJson(parseMigrationUri(uri))).toList();
      expect(roundtrip, web['roundtrip']);
      // 名稱、金鑰（正規化）、位數、演算法都保留，週期一律 30 秒
      final back = roundtrip.expand((r) => r['data'] as List).toList();
      expect(back.length, items.length);
      expect(back[5]['secret'], 'JBSWY3DPEHPK3PXP');
      expect(back[3]['name'], 'GitHub - 張三@example.com');
    });

    test('沒有項目時不產生', () {
      expect(buildMigrationUris(const []), isEmpty);
    });

    test('Google Authenticator 只支援 30 秒', () {
      expect(canExportToGoogle(const TotpInput(name: 'a', secret: 'A')), isTrue);
      expect(canExportToGoogle(const TotpInput(name: 'b', secret: 'A', period: 60)), isFalse);
      expect(web['google'], [true, false, true]);
    });

    test('文字備份的連結與網站相同', () {
      expect(items.take(4).map(buildOtpauthUri).toList(), web['backup']);
    });
  });

  group('整批匯入的文字', () {
    final cases = (web['importText'] as Map<String, dynamic>).cast<String, Map<String, dynamic>>();
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () {
        expect(importJson(parseImportText(value['input'] as String)), value['output']);
      });
    }

    test('只有一筆而且沒有錯誤才直接帶入表單', () {
      expect(parseImportText(cases['single']!['input'] as String).isSingle, isTrue);
      expect(parseImportText(cases['mixed']!['input'] as String).isSingle, isFalse);
      expect(parseImportText(cases['singleBad']!['input'] as String).isSingle, isFalse);
    });
  });

  test('組名稱同網站', () {
    expect(composeName('alice', 'GitHub'), 'GitHub - alice');
    expect(composeName('Example:bob'), 'Example - bob');
    expect(composeName('Same:Same', 'Same'), 'Same');
    expect(composeName('  '), '未命名');
    expect(composeName(':bob', ' '), 'bob');
  });
}
