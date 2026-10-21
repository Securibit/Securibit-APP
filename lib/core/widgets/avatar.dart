import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// 使用者頭像：有照片用照片，沒有或載入失敗時顯示名字的第一個字
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.photoUrl, this.size = 36});

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final initial = Text(
      name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
      style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w600, color: colors.ink),
    );
    final url = photoUrl;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: colors.surface2,
        alignment: Alignment.center,
        child: url == null || url.isEmpty
            ? initial
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => initial,
              ),
      ),
    );
  }
}
