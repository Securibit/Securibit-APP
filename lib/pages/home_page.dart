import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore
import 'package:shared_preferences/shared_preferences.dart';
import 'login_page.dart'; // Import your LoginPage
import 'dart:async';
import 'package:otp/otp.dart';
import 'package:base32/base32.dart'; // Import Base32 decoder

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;
  List<Map<String, dynamic>> _userTotps = []; // 儲存用TOTP
  String? _uid; // 儲存用戶Uid
  String? displayName; // 儲存用戶名稱
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadUserUid(); // Load UID and fetch data
    _startTotpRefresh(); // Start auto-refresh for TOTP codes
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel timer when the widget is disposed
    super.dispose();
  }

  // Start a timer to refresh TOTP every second
  void _startTotpRefresh() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {}); // Trigger rebuild to update TOTP and remaining time
    });
  }

  // Load UID from SharedPreferences
  Future<void> _loadUserUid() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('UserUid'); // Retrieve the stored UID
    if (uid != null) {
      setState(() {
        _uid = uid;
      });
      _fetchUserDisplayName(uid);
      _fetchUserTotps(uid); // Fetch TOTP data for this UID
    }
  }

  // Fetch user's display name from Firestore
  Future<void> _fetchUserDisplayName(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('user')
          .where('uid', isEqualTo: uid)
          .get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['name'] != null && data['name'].isNotEmpty){
          displayName = data['name'];
        }
      }
    } catch (error) {
      print('Error fetching user display name: $error');
    }
  }

  // Fetch user data and filter TOTP entries from Firestore
  Future<void> _fetchUserTotps(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('user')
          .where('uid', isEqualTo: uid)
          .get();

      final List<Map<String, dynamic>> totps = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['totp'] != null && data['totp'].isNotEmpty) {
          for (var totpEntry in data['totp']) {
            totps.add({
              'name': totpEntry['name'] ?? '沒有名字',
              'secret': totpEntry['secret'] ?? '',
              'category': totpEntry['category'] ?? '普通',
            });
          }
        }
      }

      setState(() {
        _userTotps = totps; // Update state with TOTP entries
      });
    } catch (error) {
      print('Error fetching TOTP data: $error');
    }
  }

  // Generate TOTP using a Base32-encoded secret
  String _generateTotp(String base32Secret) {
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

  // Calculate time left for the current TOTP cycle
  int _calculateTimeLeft() {
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return 30 - (currentTime % 30); // Each TOTP refreshes every 30 seconds
  }

  // Logout function
  Future<void> _logout() async {
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

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
                '您好, ${displayName ?? '用戶'}',
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
      body: _userTotps.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.question_mark,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 20),
                  Text(
                    '尚未設定任何驗證碼',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10),
                  Text(
                    '目前不支援軟體新增，請至網站版新增驗證碼',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _userTotps.length,
              itemBuilder: (context, index) {
                final totp = _userTotps[index];
                final totpCode = _generateTotp(totp['secret']);
                final int timeLeft = _calculateTimeLeft();
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
            ),
    );
  }
}
