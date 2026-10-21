import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/tokens.dart';

/// 用相機掃描 QR Code（只在 iOS / Android 開啟），掃到就把內容帶回上一頁
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (value == null) return;
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
        title: const Text('掃描 QR Code'),
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
          const Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              '對準服務在兩步驟驗證設定頁顯示的 QR Code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: AppText.secondary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
