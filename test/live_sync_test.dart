import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/sync/live_sync.dart';

// 即時同步的訊號（網站 database/init.sql 的 sync_signals.topic）：解析與合併、debounce
void main() {
  group('SyncBatch', () {
    test('認得群組、邀請、驗證碼與金鑰的 topic', () {
      final batch = SyncBatch();
      expect(batch.isEmpty, isTrue);
      expect(batch.add('groups'), isTrue);
      expect(batch.add('invitations'), isTrue);
      expect(batch.add('codes:g1'), isTrue);
      expect(batch.add('secrets:g2'), isTrue);
      expect(batch.groups, isTrue);
      expect(batch.invitations, isTrue);
      expect(batch.codes, {'g1': false, 'g2': true});
      expect(batch.isEmpty, isFalse);
    });

    test('同一個群組的清單與金鑰合併，金鑰變了就要重新讀金鑰', () {
      final batch = SyncBatch()
        ..add('secrets:g1')
        ..add('codes:g1')
        ..add('codes:g2')
        ..add('codes:g2');
      expect(batch.codes, {'g1': true, 'g2': false});
    });

    test('不認得的 topic 不算', () {
      final batch = SyncBatch();
      for (final topic in ['', 'codes', 'codes:', ':g1', 'other:g1', 'profile']) {
        expect(batch.add(topic), isFalse, reason: topic);
      }
      expect(batch.isEmpty, isTrue);
    });
  });

  group('SyncDebouncer', () {
    const delay = Duration(milliseconds: 40);
    const maxWait = Duration(milliseconds: 120);

    test('連續的訊號停下來後才合成一次通知', () async {
      final flushed = <SyncBatch>[];
      final debouncer = SyncDebouncer(onFlush: flushed.add, delay: delay, maxWait: maxWait);
      debouncer
        ..add('groups')
        ..add('codes:g1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      debouncer.add('secrets:g1');
      expect(flushed, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(flushed, hasLength(1));
      expect(flushed.single.groups, isTrue);
      expect(flushed.single.codes, {'g1': true});
    });

    test('一直有訊號時最多等 maxWait', () async {
      final flushed = <SyncBatch>[];
      final debouncer = SyncDebouncer(onFlush: flushed.add, delay: delay, maxWait: maxWait);
      final stopwatch = Stopwatch()..start();
      while (flushed.isEmpty && stopwatch.elapsed < const Duration(seconds: 1)) {
        debouncer.add('codes:g1');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(flushed, hasLength(1));
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 400)));
      debouncer.cancel();
    });

    test('取消後不通知，不認得的 topic 不會觸發', () async {
      final flushed = <SyncBatch>[];
      final debouncer = SyncDebouncer(onFlush: flushed.add, delay: delay, maxWait: maxWait);
      debouncer.add('groups');
      debouncer.cancel();
      debouncer.add('unknown');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(flushed, isEmpty);
    });
  });
}
