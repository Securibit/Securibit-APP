import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import 'admin_widgets.dart';

/// 用上一頁最後一筆的 id 載入下一頁（null = 第一頁）
typedef PageLoader<T> = Future<Result<List<T>>> Function(int? beforeId);

/// 往前翻頁的清單狀態（同網站 usePagedList）：一頁滿了才有下一頁，合併時去掉重複的 id
class PagedState<T> {
  PagedState({required this.pageSize, required this.idOf});

  final int pageSize;
  final int Function(T item) idOf;

  // null：第一頁載入中
  List<T>? items;
  bool hasMore = false;
  bool loadingMore = false;

  void applyFirst(List<T> data) {
    items = data;
    hasMore = data.length >= pageSize;
  }

  void applyMore(List<T> data) {
    final seen = {for (final item in items ?? <T>[]) idOf(item)};
    items = [...?items, ...data.where((item) => !seen.contains(idOf(item)))];
    hasMore = data.length >= pageSize;
  }

  int? get lastId => items == null || items!.isEmpty ? null : idOf(items!.last);
}

/*
 * 分組清單樣式的紀錄列表：掛上時載入第一頁，下面有「載入更多」。
 * load 換了（例如換使用者）時請由外層用 key 重新掛載。
 */
class PagedList<T> extends StatefulWidget {
  const PagedList({
    super.key,
    required this.load,
    required this.pageSize,
    required this.idOf,
    required this.itemBuilder,
    required this.emptyText,
    required this.errorTitle,
  });

  final PageLoader<T> load;
  final int pageSize;
  final int Function(T item) idOf;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final String emptyText;
  final String errorTitle;

  @override
  State<PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<PagedList<T>> {
  late final _state = PagedState<T>(pageSize: widget.pageSize, idOf: widget.idOf);

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    final result = await widget.load(null);
    if (!mounted) return;
    switch (result) {
      case Ok(:final data):
        setState(() => _state.applyFirst(data));
      case Err(:final message):
        setState(() => _state.applyFirst(const []));
        await showErrorDialog(context, widget.errorTitle, message);
    }
  }

  Future<void> _loadMore() async {
    final last = _state.lastId;
    if (last == null || _state.loadingMore) return;
    setState(() => _state.loadingMore = true);
    final result = await widget.load(last);
    if (!mounted) return;
    setState(() => _state.loadingMore = false);
    switch (result) {
      case Ok(:final data):
        setState(() => _state.applyMore(data));
      case Err(:final message):
        await showErrorDialog(context, widget.errorTitle, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _state.items;
    if (items == null) return const ListLoading();
    if (items.isEmpty) return ListEmpty(widget.emptyText);
    final colors = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) rows.add(Divider(indent: 16, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      rows.add(widget.itemBuilder(context, items[i], i));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: ColoredBox(color: colors.surface1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
        ),
        if (_state.hasMore) LoadMoreButton(onPressed: _loadMore, loading: _state.loadingMore),
      ],
    );
  }
}
