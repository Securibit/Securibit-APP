import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart';  // 匯入主頁

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<void> _handleGuestLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);  // 儲存登入狀態
    _navigateToHome();
  }

  Future<void> _handleGoogleLogin() async {
    try {
      final user = await _googleSignIn.signIn();
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);  // 儲存登入狀態
        _navigateToHome();
      }
    } catch (error) {
      print('Google Login Failed: $error');
    }
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Page'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _handleGuestLogin,
              child: const Text('Continue as Guest'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _handleGoogleLogin,
              child: const Text('Sign in with Google'),
            ),
          ],
        ),
      ),
    );
  }
}
