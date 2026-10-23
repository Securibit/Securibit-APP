import 'package:url_launcher/url_launcher.dart';
import 'env.dart';

// 網站上的說明頁（隱私權政策、免責聲明），用瀏覽器打開
Future<bool> openWebPage(String path) =>
    launchUrl(Uri.parse('${Env.webUrl}$path'), mode: LaunchMode.externalApplication);
