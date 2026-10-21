// RPC 回傳的 jsonb 轉型小工具（欄位可能是 null 或型別不一致，一律給預設值）
String asString(Object? value, [String fallback = '']) => value is String ? value : (value?.toString() ?? fallback);

int asInt(Object? value, [int fallback = 0]) => switch (value) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v) ?? fallback,
      _ => fallback,
    };

bool asBool(Object? value, [bool fallback = false]) => value is bool ? value : fallback;

Map<String, dynamic> asMap(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> asMapList(Object? value) =>
    value is List ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

String? asNullableString(Object? value) => value is String && value.isNotEmpty ? value : null;
