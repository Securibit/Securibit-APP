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

/// 依群組存的類別順序排列（群組成員共用，存在資料庫）：
/// 存過的照存的順序排前面（只留還存在的），其餘照字母排在後面
List<String> orderCategories(Iterable<String> names, List<String> order) {
  final rest = <String>{...names};
  final head = [for (final name in order) if (rest.remove(name)) name];
  return [...head, ...rest.toList()..sort()];
}

/// 資料庫回傳的類別順序（group_detail 的 category_order）：不是陣列（舊的資料庫沒有這個欄位）就是空的，
/// 只留非空字串，去頭尾空白、去重
List<String> parseCategoryOrder(Object? value) {
  if (value is! List) return [];
  final seen = <String>{};
  for (final item in value) {
    if (item is! String) continue;
    final name = item.trim();
    if (name.isNotEmpty) seen.add(name);
  }
  return seen.toList();
}
