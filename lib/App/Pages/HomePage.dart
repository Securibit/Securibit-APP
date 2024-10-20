// lib/src/pages/home_page.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
// Securibit-Module
import 'package:securibit/Module/UserService.dart';
import 'package:securibit/Module/TotpService.dart';
// Securibit-Components
import 'package:securibit/App/Components/Home/NoTotpView.dart';
import 'package:securibit/App/Components/Home/TotpListView.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final UserService _userService = UserService();
  final TotpService _totpService = TotpService();
  List<Map<String, dynamic>> _userTotps = [];
  String? _uid;
  String? displayName;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initialize();
    _startTotpRefresh();
  }

  void _initialize() async {
    _uid = await _userService.loadUserUid();
    if (_uid != null) {
      displayName = await _userService.fetchUserDisplayName(_uid!);
      _userTotps = await _userService.fetchUserTotps(_uid!);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTotpRefresh() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.blue,
        title: Center(
          child: Text(
            '您好, ${displayName ?? '用戶'}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
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
      body: _userTotps.isEmpty
          ? const NoTotpView()
          : TotpList(
        userTotps: _userTotps,
        generateTotp: _totpService.generateTotp,
        calculateTimeLeft: _totpService.calculateTimeLeft,
      ),
    );
  }
}
