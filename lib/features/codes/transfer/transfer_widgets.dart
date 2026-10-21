import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/tokens.dart';

/// 匯入、匯出畫面：寬視窗用對話框，窄螢幕用整頁（同 showCodeForm）
Future<T?> showTransferPage<T>(BuildContext context, Widget page) {
  if (MediaQuery.sizeOf(context).width >= 720) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 540, maxHeight: 760), child: page),
      ),
    );
  }
  return Navigator.of(context).push<T>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => page));
}

/// 上面一列「左邊按鈕｜標題｜右邊按鈕」（同新增驗證碼表單）
class TransferHeader extends StatelessWidget {
  const TransferHeader({super.key, required this.title, this.subtitle, this.leading, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          SizedBox(width: 84, child: Align(alignment: Alignment.centerLeft, child: leading)),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted),
                  ),
              ],
            ),
          ),
          SizedBox(width: 84, child: Align(alignment: Alignment.centerRight, child: trailing)),
        ],
      ),
    );
  }
}

/// 匯出畫面共用的提醒（同網站 ExportWarning）：QR Code 與連結裡就是金鑰本身
class ExportWarning extends StatelessWidget {
  const ExportWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.small)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, size: 18, color: colors.alarm),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '裡面包含金鑰，任何人拿到都能產生你的驗證碼。不要截圖分享，也不要在別人看得到的地方開啟',
              style: TextStyle(fontSize: AppText.secondary, color: colors.alarm, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// QR Code：深色模式也放在白底上，掃描器才讀得到
class QrPanel extends StatelessWidget {
  const QrPanel({super.key, required this.data, this.size = 260, this.semanticLabel});

  final String data;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // 小螢幕時縮小，留出左右邊界
    final width = MediaQuery.sizeOf(context).width;
    final side = size.clamp(160.0, width - 88).toDouble();
    return Semantics(
      label: semanticLabel,
      image: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.medium)),
        child: QrImageView(
          data: data,
          size: side,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1D1D1F)),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1D1D1F)),
        ),
      ),
    );
  }
}

/// 小標（同新增驗證碼表單的區塊標題）
class TransferSectionTitle extends StatelessWidget {
  const TransferSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: TextStyle(fontSize: AppText.secondary, color: context.colors.inkMuted, fontWeight: FontWeight.w600)),
      );
}
