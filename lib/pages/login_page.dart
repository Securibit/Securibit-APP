import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart'; // Your main page after login

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> _handleLocalLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);  // 儲存登入狀態
    _navigateToHome();
  }


  Future<void> _handleGoogleLogin() async {
    try {
      // Step 1: Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled the login
        return;
      }

      // Step 2: Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Step 3: Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Step 4: Sign in with the credential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        // Step 5: Retrieve user data
        String uid = user.uid; // Get the Firebase UID
        String? email = user.email; // Get the email
        String? displayName = user.displayName; // Get the display name
        String? photoURL = user.photoURL; // Get the photo URL

        print('User UID: $uid'); // Print the UID
        print('User Email: $email');
        print('User Display Name: $displayName');
        print('User Photo URL: $photoURL');

        // Save login status
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        _navigateToHome();
      }
    } catch (error) {
      print('========================================================================');
      print('----===Google Login Failed===----');
      print(error.toString());
      print('----===Google Login Failed End===----');
      print('========================================================================');
    }
  }


  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Set background color to white
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0), // Horizontal padding
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Display icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.lightBlue.withOpacity(0.1), // Light blue background
                  borderRadius: BorderRadius.circular(10), // Rounded corners
                ),
                child: const Text(
                  '👋',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue, // Text color
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '歡迎使用 Securibit',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue, // Text color
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '再開啟安全之旅前，先選擇登入方式',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey), // Description text color
              ),
              const SizedBox(height: 40), // Spacing before buttons

              // Google Login Button
              SizedBox(
                width: double.infinity, // Make button full width
                child: ElevatedButton.icon(
                  onPressed: _handleGoogleLogin,
                  icon: const Icon(Icons.login), // Google icon
                  label: const Text('Google'), // Button text
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, // Background color
                    foregroundColor: Colors.black, // Text color
                    padding: const EdgeInsets.symmetric(vertical: 15), // Adjust padding
                    elevation: 5, // Set elevation
                    shape: RoundedRectangleBorder( // Set shape
                      borderRadius: BorderRadius.circular(10), // Rounded corners
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20), // Spacing between buttons

              // Local Login Button
              SizedBox(
                width: double.infinity, // Make button full width
                child: ElevatedButton.icon(
                  onPressed: _handleLocalLogin,
                  icon: const Icon(Icons.phone_android), // Local login icon
                  label: const Text('本機登入'), // Button text
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, // Background color
                    foregroundColor: Colors.black, // Text color
                    padding: const EdgeInsets.symmetric(vertical: 15), // Adjust padding
                    elevation: 5, // Set elevation
                    shape: RoundedRectangleBorder( // Set shape
                      borderRadius: BorderRadius.circular(10), // Rounded corners
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
