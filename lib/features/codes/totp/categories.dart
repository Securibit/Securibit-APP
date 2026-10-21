/*
 * 一筆驗證碼可以有多個類別（同網站 src/lib/totp/categories.ts）。
 * 資料庫沿用 category text 欄位，多個類別用半形逗號「,」串起來存。
 */

// 輸入時接受半形逗號、全形逗號、頓號當分隔
final _separator = RegExp(r'[,，、]');

/// 切成類別陣列：去頭尾空白、去空、去重，保留原本順序
List<String> parseCategories(String? value) {
  if (value == null || value.isEmpty) return [];
  final seen = <String>{};
  for (final part in value.split(_separator)) {
    final name = part.trim();
    if (name.isNotEmpty) seen.add(name);
  }
  return seen.toList();
}

/// 接成要存的字串（會順便整理一次）
String joinCategories(List<String> list) => parseCategories(list.join(',')).join(',');

/// 整理成標準格式（存檔前用）
String normalizeCategories(String? value) => joinCategories(parseCategories(value));

/// 所有類別的聯集（排序），給篩選與建議清單用
List<String> collectCategories(Iterable<String> values) {
  final all = <String>{for (final value in values) ...parseCategories(value)}.toList();
  all.sort();
  return all;
}

bool hasCategory(String value, String name) => parseCategories(value).contains(name);

/// 名稱下方顯示用：用「、」串起來
String formatCategories(String value) => parseCategories(value).join('、');
