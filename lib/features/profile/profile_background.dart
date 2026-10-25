import 'package:flutter/material.dart';

/*
 * 個人資料的背景圖：有上傳就顯示圖片，沒有（空字串）時用內建的深灰到黑色漸層
 * （和以前預設的背景圖一樣的感覺：左上角柔和的灰，往右下漸漸變成接近黑色），不從外部網站載入
 */
class ProfileBackground extends StatelessWidget {
  const ProfileBackground({super.key, required this.url, this.height = 112});

  final String url;
  final double height;

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8A8A8A), Color(0xFF3A3A3A), Color(0xFF111111)],
    stops: [0, 0.45, 1],
  );

  @override
  Widget build(BuildContext context) {
    const fallback = DecoratedBox(decoration: BoxDecoration(gradient: gradient));
    return SizedBox(
      height: height,
      width: double.infinity,
      child: url.isEmpty
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              // 圖片讀不到時也用漸層
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
