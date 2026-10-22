import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/secure_store.dart';

// Windows 的安全儲存把全部項目存成一份加密檔，每次寫入都是「讀出整份 → 改一筆 → 寫回整份」：
// 同時寫好幾筆時要排隊，不然後寫完的會蓋掉先寫的（例如登入時 session 和離線快取一起存）

/// 假的安全儲存：和 flutter_secure_storage_windows 一樣整份讀出、等一下、整份寫回
class _WholeFileStorage extends FlutterSecureStorage {
  _WholeFileStorage();

  Map<String, String> file = {};

  Future<Map<String, String>> _load() async {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return Map.of(file);
  }

  Future<void> _save(Map<String, String> data) async {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    file = data;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final map = await _load();
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    await _save(map);
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => (await _load())[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final map = await _load();
    map.remove(key);
    await _save(map);
  }
}

void main() {
  test('Windows：同時寫好幾筆，每一筆都留著', () async {
    final storage = _WholeFileStorage();
    final store = SecureStore(storage, serial: true);
    await Future.wait([for (var i = 0; i < 20; i++) store.write(key: 'k$i', value: 'v$i')]);
    expect(storage.file.length, 20);
    expect(await store.read(key: 'k7'), 'v7');
    await Future.wait([store.delete(key: 'k1'), store.write(key: 'k2', value: 'new'), store.delete(key: 'k3')]);
    expect(storage.file.keys, isNot(contains('k1')));
    expect(storage.file.keys, isNot(contains('k3')));
    expect(storage.file['k2'], 'new');
    expect(storage.file.length, 18);
  });

  test('不排隊的話會掉資料（其他平台每一筆分開存，不需要排隊）', () async {
    final storage = _WholeFileStorage();
    final store = SecureStore(storage, serial: false);
    await Future.wait([for (var i = 0; i < 20; i++) store.write(key: 'k$i', value: 'v$i')]);
    expect(storage.file.length, lessThan(20));
  });

  test('前一筆失敗不會卡住後面的', () async {
    final storage = _FailingOnce();
    final store = SecureStore(storage, serial: true);
    final first = store.write(key: 'a', value: '1');
    final second = store.write(key: 'b', value: '2');
    await expectLater(first, throwsA(isA<StateError>()));
    await second;
    expect(storage.file, {'b': '2'});
  });

  test('Windows 不讀舊版放在認證管理員的資料', () {
    expect(secureStore.wOptions.toMap()['useBackwardCompatibility'], 'false');
  });

}

class _FailingOnce extends _WholeFileStorage {
  bool _failed = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (!_failed) {
      _failed = true;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      throw StateError('寫入失敗');
    }
    return super.write(key: key, value: value);
  }
}
