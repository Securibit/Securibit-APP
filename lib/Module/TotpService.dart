import 'package:otp/otp.dart';

class TotpService {
  String generateTotp(String base32Secret) {
    int code = OTP.generateTOTPCode(
      base32Secret,
      DateTime.now().millisecondsSinceEpoch,
      interval: 30,
      length: 6,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
    return code.toString().padLeft(6, '0');
  }

  int calculateTimeLeft() {
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return 30 - (currentTime % 30); // Each TOTP refreshes every 30 seconds
  }
}
