import '../../src/rust/api/secrets.dart' as core;
import 'code_models.dart';
import 'secret_handle.dart';
import 'totp/otp.dart';

enum OtpState { ready, pending, invalid }

/// 某個時間點的動態碼：有金鑰就由 Rust 產生（金鑰不經過 Dart）；沒有金鑰時用網站產生的碼（同網站 GroupCodeCard）
class OtpSnapshot {
  const OtpSnapshot({
    required this.state,
    required this.code,
    required this.next,
    required this.secondsLeft,
    required this.period,
    required this.counter,
  });

  final OtpState state;
  final String? code;
  final String? next;
  final int secondsLeft;
  final int period;
  // 第幾個週期（隱藏模式用來判斷換了一組沒）
  final int counter;

  bool get expiring => isExpiring(secondsLeft, period);

  factory OtpSnapshot.at({
    required GroupAccount account,
    required SecretHandle? secret,
    required ServerCodes? server,
    required int nowMs,
  }) {
    final period = account.period;
    // 伺服器產生的碼要用伺服器時間判斷週期，避免本機時鐘不準時顯示錯的碼
    final time = secret == null ? nowMs + (server?.offsetMs ?? 0) : nowMs;
    final seconds = time ~/ 1000;
    final secondsLeft = period - seconds % period;
    final counter = seconds ~/ period;

    OtpSnapshot make(OtpState state, [String? code, String? next]) => OtpSnapshot(
          state: state,
          code: code,
          next: next,
          secondsLeft: secondsLeft,
          period: period,
          counter: counter,
        );

    if (secret != null) {
      final codes = secret.codes(account, counter);
      return switch (codes.state) {
        core.OtpCodeState.ready => make(OtpState.ready, codes.code, codes.next),
        core.OtpCodeState.invalid => make(OtpState.invalid),
        // App 鎖定時清掉了、還沒放回來
        core.OtpCodeState.missing => make(OtpState.pending),
      };
    }

    final entry = server?.codes[account.id];
    if (server == null || entry == null) return make(OtpState.pending);
    final serverCounter = server.at ~/ 1000 ~/ period;
    if (counter == serverCounter) {
      return entry.code == null ? make(OtpState.invalid) : make(OtpState.ready, entry.code, entry.next);
    }
    // 已經進入下一個週期、還沒重新取得前，先顯示預先拿到的下一組
    if (counter == serverCounter + 1 && entry.next != null) return make(OtpState.ready, entry.next);
    return make(OtpState.pending);
  }
}
