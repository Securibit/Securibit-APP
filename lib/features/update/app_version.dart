/*
 * 版本號（語意化版本 semver）：主.次.修訂，可以帶預先發行（-beta.1），+ 後面的 build 號不算在比較裡。
 * GitHub Release 的標籤可以寫 v0.3.0 或 0.3.0；少寫的部分當 0（0.4 = 0.4.0）。
 */
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.prerelease = const []]);

  final int major;
  final int minor;
  final int patch;
  // 預先發行的各段（beta.2 → ['beta', '2']）；空的是正式版
  final List<String> prerelease;

  static final _pattern = RegExp(r'^[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$');

  /// 解析 v0.3.0、0.3.0、0.3.0+3、1.0.0-beta.1；看不懂就回傳 null
  static AppVersion? tryParse(String? text) {
    final match = _pattern.firstMatch(text?.trim() ?? '');
    if (match == null) return null;
    int part(int i) => int.parse(match.group(i) ?? '0');
    final pre = match.group(4);
    return AppVersion(part(1), part(2), part(3), pre == null ? const [] : pre.split('.'));
  }

  bool get isPrerelease => prerelease.isNotEmpty;

  bool operator >(AppVersion other) => compareTo(other) > 0;

  // semver 的順序：先比數字；數字相同時正式版比預先發行新；預先發行逐段比，數字段比大小、文字段比字典順序，數字段比文字段舊
  @override
  int compareTo(AppVersion other) {
    for (final (a, b) in [(major, other.major), (minor, other.minor), (patch, other.patch)]) {
      if (a != b) return a.compareTo(b);
    }
    if (prerelease.isEmpty || other.prerelease.isEmpty) {
      return (prerelease.isEmpty ? 1 : 0) - (other.prerelease.isEmpty ? 1 : 0);
    }
    for (var i = 0; i < prerelease.length && i < other.prerelease.length; i++) {
      final a = prerelease[i];
      final b = other.prerelease[i];
      final na = int.tryParse(a);
      final nb = int.tryParse(b);
      final int order;
      if (na != null && nb != null) {
        order = na.compareTo(nb);
      } else if (na != null || nb != null) {
        order = na != null ? -1 : 1;
      } else {
        order = a.compareTo(b);
      }
      if (order != 0) return order;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, prerelease.join('.'));

  /// 顯示用：0.3.0、1.0.0-beta.1（不帶 v）
  @override
  String toString() => '$major.$minor.$patch${isPrerelease ? '-${prerelease.join('.')}' : ''}';
}
