import '../../core/json.dart';
import 'totp/totp_params.dart';

// group_accounts() 的一筆（不含金鑰）
class GroupAccount {
  const GroupAccount({
    required this.id,
    required this.name,
    required this.category,
    required this.digits,
    required this.period,
    required this.algorithm,
    required this.pinned,
    required this.permissions,
    required this.hasOverwrites,
  });

  final String id;
  final String name;
  // 多個類別用「,」串起來
  final String category;
  final int digits;
  final int period;
  final TotpAlgorithm algorithm;
  // 釘選的排在最上面
  final bool pinned;
  // 這一筆的有效權限（已套用個別覆寫）
  final int permissions;
  final bool hasOverwrites;

  factory GroupAccount.fromJson(Map<String, dynamic> json) => GroupAccount(
        id: asString(json['id']),
        name: asString(json['name']),
        category: asString(json['category']),
        digits: asInt(json['digits'], TotpDefaults.digits),
        period: asInt(json['period'], TotpDefaults.period),
        algorithm: TotpAlgorithm.fromLabel(json['algorithm'] as String?),
        pinned: asBool(json['pinned']),
        permissions: asInt(json['permissions']),
        hasOverwrites: asBool(json['has_overwrites']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'digits': digits,
        'period': period,
        'algorithm': algorithm.label,
        'pinned': pinned,
        'permissions': permissions,
        'has_overwrites': hasOverwrites,
      };

  GroupAccount copyWith({bool? pinned}) => GroupAccount(
        id: id,
        name: name,
        category: category,
        digits: digits,
        period: period,
        algorithm: algorithm,
        pinned: pinned ?? this.pinned,
        permissions: permissions,
        hasOverwrites: hasOverwrites,
      );
}

/// 網站 /api/groups/codes 產生的動態碼（只有「查看驗證碼」、沒有「查看金鑰」時）
class ServerCodes {
  const ServerCodes({required this.offsetMs, required this.at, required this.codes});

  // 伺服器時間 − 本機時間（ms）
  final int offsetMs;
  // 伺服器產生時的時間（ms）
  final int at;
  final Map<String, ServerCode> codes;
}

class ServerCode {
  const ServerCode({required this.code, required this.next});

  // 產生當下週期的碼，與下一個週期的碼
  final String? code;
  final String? next;
}
