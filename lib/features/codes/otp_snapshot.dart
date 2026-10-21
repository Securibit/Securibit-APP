import 'code_models.dart';
import 'totp/otp.dart';

enum OtpState { ready, pending, invalid }

/// 某個時間點的動態碼：有金鑰就在 App 產生；沒有金鑰時用網站產生的碼（同網站 GroupCodeCard）
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
    required String? secret,
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
      String? generate(int c) => generateOtp(
            secret: secret,
            digits: account.digits,
            period: period,
            algorithm: account.algorithm,
            timestampMs: c * period * 1000,
          );
      final code = generate(counter);
      return code == null ? make(OtpState.invalid) : make(OtpState.ready, code, generate(counter + 1));
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
