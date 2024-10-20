// lib/src/components/totp_list.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TotpList extends StatelessWidget {
  final List<Map<String, dynamic>> userTotps;
  final String Function(String secret) generateTotp;
  final int Function() calculateTimeLeft;

  const TotpList({
    super.key,
    required this.userTotps,
    required this.generateTotp,
    required this.calculateTimeLeft,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: userTotps.length,
      itemBuilder: (context, index) {
        final totp = userTotps[index];
        final totpCode = generateTotp(totp['secret']);
        final int timeLeft = calculateTimeLeft();
        final double progress = timeLeft / 30;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                totp['name'],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 5),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: totpCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已複製到剪貼簿'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(
                  totpCode,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: Colors.grey[300],
                color: Colors.blue,
              ),
              const SizedBox(height: 5),
              Text(
                '剩餘時間: ${timeLeft}s',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }
}
