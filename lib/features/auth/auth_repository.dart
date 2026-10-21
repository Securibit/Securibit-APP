import '../../core/result.dart';
import '../../core/rpc.dart';
import 'profile.dart';

// 確保使用者有 profile（沒有就依 email 自我修復、接回舊資料，也會建立預設群組）。冪等、可重複呼叫
Future<Result<void>> ensureProfile() => rpcVoid('ensure_profile');

// 從 profiles 讀自己的資料（RLS 只允許讀自己的那一列）
Future<Result<Profile>> loadProfile(String uid) async {
  try {
    final row = await supabase.from('profiles').select().eq('id', uid).maybeSingle().timeout(const Duration(seconds: 20));
    if (row == null) return const Err('找不到使用者資料');
    return Ok(Profile.fromJson(row));
  } catch (error) {
    return errorResult(error);
  }
}

// 記錄這次登入的時間 / IP / 裝置（網站的 API 讀請求 header 取得）；失敗不影響登入
Future<void> recordLogin() async {
  await callWebApi('/api/record-login', null);
}
