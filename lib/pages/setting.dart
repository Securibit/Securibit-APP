import 'package:flutter/material.dart';
import 'login_page.dart'; // Import login page
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(80.0), // 調整為所需的高度
        child: AppBar(
          automaticallyImplyLeading: false,
          title: Center(
            child: Container(
              padding: EdgeInsets.only(top: 16.0), // 調整為所需的距離
              child: Text(
                '設定',
                style: const TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue, Colors.lightBlueAccent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: Container(
          width: 200,
          child: ElevatedButton(
              onPressed: () async {
                final shouldLogout = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('登出'),
                      content: const Text('你確定要登出嗎?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('確定'),
                        ),
                      ],
                    );
                  },
                );

                if (shouldLogout == true) {
                  await FirebaseAuth.instance.signOut(); // Sign out from Firebase
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('isLoggedIn', false); // Clear login status
                  await prefs.remove('UserUid'); // Clear stored UID
                  Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginPage()),
                    );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlue, // Background color
                foregroundColor: Colors.white, // Text color
                padding: const EdgeInsets.symmetric(vertical: 5), // Adjust padding
                elevation: 2, // Set elevation
                shape: RoundedRectangleBorder( // Set shape
                  borderRadius: BorderRadius.circular(8), // Rounded corners
                ),
              ),
              child: const Text('登出', style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white
              )
              )
          ),
        )
      ),
    );
  }
}
