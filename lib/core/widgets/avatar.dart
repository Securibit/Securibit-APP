import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'avatar_cache.dart';

// 使用者頭像：有照片用照片（先用暫存，沒有網路時也看得到，見 AvatarCache），沒有或載入失敗時顯示名字的第一個字
class UserAvatar extends StatefulWidget {
  const UserAvatar({super.key, required this.name, this.photoUrl, this.size = 36});

  final String name;
  final String? photoUrl;
  final double size;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Uint8List? _bytes;

  String? get _url {
    final url = widget.photoUrl;
    return url == null || url.isEmpty ? null : url;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(UserAvatar old) {
    super.didUpdateWidget(old);
    if (old.photoUrl != widget.photoUrl) _load();
  }

  void _load() {
    final url = _url;
    _bytes = url == null ? null : AvatarCache.peek(url);
    if (url == null) return;
    void show(Uint8List bytes) {
      if (mounted && _url == url) setState(() => _bytes = bytes);
    }

    unawaited(AvatarCache.load(url, onUpdate: show).then((bytes) {
      if (bytes != null) show(bytes);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = widget.size;
    final name = widget.name.trim();
    final initial = Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w600, color: colors.ink),
    );
    final bytes = _bytes;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: colors.surface2,
        alignment: Alignment.center,
        child: bytes == null
            ? initial
            : Image.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => initial,
              ),
      ),
    );
  }
}
