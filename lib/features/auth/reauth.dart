import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/result.dart';
import '../../core/rpc.dart';
import '../../core/widgets/feedback.dart';
import 'auth_controller.dart';

/*
 * 刪除帳戶、後台刪除使用者這類操作（同網站 useReauth）：網站回 reauth_required（10 分鐘內沒登入過）時，
 * 先問一次，再跑一次和登入一樣的 Google 登入，確認是同一個人後自動再試一次（只重試一次）。
 * 使用者按取消時結果的 code 是 reauthCancelledCode，呼叫端不用再顯示錯誤
 */
Future<Result<T>> withReauth<T>(BuildContext context, Future<Result<T>> Function() action) async {
  final first = await action();
  if (first is! Err<T> || first.code != reauthRequiredCode || !context.mounted) return first;
  final auth = context.read<AuthController>();
  final ok = await confirmDialog(
    context,
    title: '請重新登入',
    message: '這個操作需要確認是你本人。請用目前的 Google 帳號重新登入，完成後會自動繼續',
    confirmLabel: '重新登入',
  );
  if (!ok) return const Err('已取消', code: reauthCancelledCode);
  final signedIn = await auth.reauthenticate();
  if (signedIn case Err(:final message, :final code)) return Err(message, code: code);
  return action();
}

/// 結果是使用者自己取消重新登入
bool isReauthCancelled<T>(Result<T> result) => result is Err<T> && result.code == reauthCancelledCode;
