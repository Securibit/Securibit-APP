// lib 裡所有資料存取的回傳格式（同網站的 Result<T>）：成功帶資料，失敗帶給使用者看的中文訊息
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  T? get dataOrNull => switch (this) {
        Ok<T>(:final data) => data,
        Err<T>() => null,
      };

  String? get messageOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final message) => message,
      };
}

class Ok<T> extends Result<T> {
  const Ok(this.data);
  final T data;
}

class Err<T> extends Result<T> {
  const Err(this.message, {this.offline = false});
  final String message;
  // 連不上伺服器（可以改用離線快取）
  final bool offline;
}
