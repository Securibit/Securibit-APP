import 'package:flutter/material.dart';
import 'pages/splash_screen.dart';  // 匯入 SplashScreen

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),  // 設定 SplashScreen 作為啟動頁面
    );
  }
}
