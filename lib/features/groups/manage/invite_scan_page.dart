import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/tokens.dart';
import 'group_rules.dart';

/// 掃描邀請連結的 QR Code（只在 iOS / Android 開啟）：掃到邀請連結就帶回上一頁，掃到別的提示一下繼續掃
class InviteScanPage extends StatefulWidget {
  const InviteScanPage({super.key});

  @override
  State<InviteScanPage> createState() => _InviteScanPageState();
}

class _InviteScanPageState extends State<InviteScanPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  bool _wrong = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final values = capture.barcodes.map((b) => b.rawValue).whereType<String>();
    // 網站與 App 產生的 QR Code 都是完整網址
    final value = values.where((v) => v.contains('/invite/') && parseInviteCode(v) != null).firstOrNull;
    if (value == null) {
      if (values.isNotEmpty && !_wrong) setState(() => _wrong = true);
      return;
    }
    _done = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('掃描邀請 QR Code'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? '沒有相機權限，請到系統設定允許 Securibit 使用相機'
                      : '無法開啟相機',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: AppText.body),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: colors.brand, width: 3),
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              _wrong ? '這不是群組邀請的 QR Code，請對準群組成員分享的邀請 QR Code' : '對準群組成員分享的邀請 QR Code',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: AppText.secondary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
