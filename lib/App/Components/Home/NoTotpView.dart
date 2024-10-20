import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class NoTotpView extends StatelessWidget {
  const NoTotpView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/illustration/galaxy.svg',
            width: 150,
            height: 150,
          ),
          const SizedBox(height: 20),
          const Text(
            '尚未設定任何驗證碼',
            style: TextStyle(
              fontSize: 18,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            '目前不支援軟體新增，請至網站版新增驗證碼',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
