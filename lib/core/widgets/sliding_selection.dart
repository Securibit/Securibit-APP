import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/*
 * 會滑動的選取底色：一排（直的或橫的）項目，選中的那一個後面墊一塊圓角底色，
 * 換選項時底色從舊的位置滑到新的位置（像 iOS 的分段控制），不是原地換色。
 * 底色的位置在繪製時才依子項目的實際位置計算，所以字級放大、項目變寬都跟得上。
 * 系統開啟「減少動態效果」時直接跳過去。
 */
class SlidingSelection extends StatefulWidget {
  const SlidingSelection({
    super.key,
    required this.selectedIndex,
    required this.children,
    required this.color,
    this.borderRadius,
    this.direction = Axis.vertical,
    this.spacing = 0,
    this.revealPadding = EdgeInsets.zero,
  });

  // 沒有選中（或超出範圍）時不畫底色
  final int? selectedIndex;
  final List<Widget> children;
  final Color color;
  // 沒給就是藥丸形（圓角是高度的一半）
  final BorderRadius? borderRadius;
  final Axis direction;
  // 項目之間的間距
  final double spacing;
  // 捲動讓選中的項目露出來時，周圍多留的空間（橫向分頁讓旁邊的分頁露出一點）
  final EdgeInsets revealPadding;

  static const duration = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;

  @override
  State<SlidingSelection> createState() => _SlidingSelectionState();
}

class _SlidingSelectionState extends State<SlidingSelection> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: SlidingSelection.duration, value: 1);
  late final _progress = CurvedAnimation(parent: _controller, curve: SlidingSelection.curve);
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 第一次顯示（例如打開側欄）時，選中的項目不在畫面內就直接捲過去，不要動畫
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(Duration.zero));
  }

  @override
  void didUpdateWidget(SlidingSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    final duration = _duration;
    _controller.duration = duration;
    _controller.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(duration));
  }

  Duration get _duration => MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : SlidingSelection.duration;

  void _reveal(Duration duration) {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject();
    if (box is _RenderSlidingSelection && box.attached) {
      box.revealSelected(duration: duration, curve: SlidingSelection.curve, padding: widget.revealPadding);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SlidingSelectionLayout(
      key: _key,
      selectedIndex: widget.selectedIndex,
      progress: _progress,
      color: widget.color,
      borderRadius: widget.borderRadius,
      direction: widget.direction,
      spacing: widget.spacing,
      textDirection: Directionality.of(context),
      children: widget.children,
    );
  }
}

class _SlidingSelectionLayout extends MultiChildRenderObjectWidget {
  const _SlidingSelectionLayout({
    super.key,
    required this.selectedIndex,
    required this.progress,
    required this.color,
    required this.borderRadius,
    required this.direction,
    required this.spacing,
    required this.textDirection,
    required super.children,
  });

  final int? selectedIndex;
  final Animation<double> progress;
  final Color color;
  final BorderRadius? borderRadius;
  final Axis direction;
  final double spacing;
  final TextDirection textDirection;

  @override
  _RenderSlidingSelection createRenderObject(BuildContext context) => _RenderSlidingSelection(
        selectedIndex: selectedIndex,
        progress: progress,
        color: color,
        borderRadius: borderRadius,
        direction: direction,
        spacing: spacing,
        textDirection: textDirection,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderSlidingSelection renderObject) {
    renderObject
      ..selectedIndex = selectedIndex
      ..progress = progress
      ..color = color
      ..borderRadius = borderRadius
      ..direction = direction
      ..spacing = spacing
      ..textDirection = textDirection;
  }
}

class _SlotParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSlidingSelection extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _SlotParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _SlotParentData> {
  _RenderSlidingSelection({
    required int? selectedIndex,
    required Animation<double> progress,
    required Color color,
    required BorderRadius? borderRadius,
    required Axis direction,
    required double spacing,
    required TextDirection textDirection,
  })  : _selectedIndex = selectedIndex,
        _progress = progress,
        _color = color,
        _borderRadius = borderRadius,
        _direction = direction,
        _spacing = spacing,
        _textDirection = textDirection;

  // 換選項那一刻底色所在的位置（動畫的起點）；第一次選中時沒有起點，直接畫在目標
  Rect? _from;
  Rect? _lastPainted;

  int? _selectedIndex;
  set selectedIndex(int? value) {
    if (value == _selectedIndex) return;
    _from = _lastPainted;
    _selectedIndex = value;
    markNeedsPaint();
  }

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (value == _progress) return;
    if (attached) _progress.removeListener(markNeedsPaint);
    _progress = value;
    if (attached) _progress.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  BorderRadius? _borderRadius;
  set borderRadius(BorderRadius? value) {
    if (value == _borderRadius) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  Axis _direction;
  set direction(Axis value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotParentData) child.parentData = _SlotParentData();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    super.detach();
  }

  RenderBox? _childAt(int? index) {
    if (index == null || index < 0) return null;
    var child = firstChild;
    for (var i = 0; child != null && i < index; i++) {
      child = childAfter(child);
    }
    return child;
  }

  /// 捲動外層，讓選中的項目整個露出來
  void revealSelected({required Duration duration, required Curve curve, required EdgeInsets padding}) {
    final child = _childAt(_selectedIndex);
    if (child == null || !child.hasSize) return;
    child.showOnScreen(rect: padding.inflateRect(Offset.zero & child.size), duration: duration, curve: curve);
  }

  // 直排：每一項撐滿寬度、往下排；橫排：每一項用自己的寬度、往右排、上下置中
  Size _performLayout(BoxConstraints constraints, {required bool dry}) {
    Size sizeOf(RenderBox child, BoxConstraints c) {
      if (dry) return child.getDryLayout(c);
      child.layout(c, parentUsesSize: true);
      return child.size;
    }

    final count = childCount;
    final gaps = count > 1 ? _spacing * (count - 1) : 0.0;

    if (_direction == Axis.vertical) {
      final bounded = constraints.hasBoundedWidth;
      final childConstraints = bounded ? BoxConstraints.tightFor(width: constraints.maxWidth) : const BoxConstraints();
      var y = 0.0;
      var width = bounded ? constraints.maxWidth : 0.0;
      var child = firstChild;
      while (child != null) {
        final size = sizeOf(child, childConstraints);
        if (!dry) (child.parentData! as _SlotParentData).offset = Offset(0, y);
        y += size.height + _spacing;
        if (!bounded) width = math.max(width, size.width);
        child = childAfter(child);
      }
      return constraints.constrain(Size(width, count == 0 ? 0 : y - _spacing));
    }

    final childConstraints = BoxConstraints(maxHeight: constraints.maxHeight);
    final sizes = <Size>[];
    var child = firstChild;
    while (child != null) {
      sizes.add(sizeOf(child, childConstraints));
      child = childAfter(child);
    }
    final contentWidth = sizes.fold(0.0, (sum, s) => sum + s.width) + gaps;
    final height = sizes.fold(0.0, (h, s) => math.max(h, s.height));
    final size = constraints.constrain(Size(contentWidth, height));
    if (!dry) {
      final rtl = _textDirection == TextDirection.rtl;
      var x = rtl ? size.width : 0.0;
      var i = 0;
      child = firstChild;
      while (child != null) {
        final s = sizes[i++];
        final dy = (size.height - s.height) / 2;
        if (rtl) {
          x -= s.width;
          (child.parentData! as _SlotParentData).offset = Offset(x, dy);
          x -= _spacing;
        } else {
          (child.parentData! as _SlotParentData).offset = Offset(x, dy);
          x += s.width + _spacing;
        }
        child = childAfter(child);
      }
    }
    return size;
  }

  @override
  void performLayout() => size = _performLayout(constraints, dry: false);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _performLayout(constraints, dry: true);

  double _sumOrMax(double Function(RenderBox child) measure, {required bool sum}) {
    var result = 0.0;
    var child = firstChild;
    while (child != null) {
      final value = measure(child);
      result = sum ? result + value : math.max(result, value);
      child = childAfter(child);
    }
    if (sum && childCount > 1) result += _spacing * (childCount - 1);
    return result;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _sumOrMax((c) => c.getMinIntrinsicWidth(height), sum: _direction == Axis.horizontal);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _sumOrMax((c) => c.getMaxIntrinsicWidth(height), sum: _direction == Axis.horizontal);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _sumOrMax((c) => c.getMinIntrinsicHeight(width), sum: _direction == Axis.vertical);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _sumOrMax((c) => c.getMaxIntrinsicHeight(width), sum: _direction == Axis.vertical);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = _childAt(_selectedIndex);
    if (child != null && child.hasSize) {
      final target = (child.parentData! as _SlotParentData).offset & child.size;
      final t = _progress.value;
      final from = _from;
      final rect = from == null || t >= 1 ? target : Rect.lerp(from, target, t)!;
      _lastPainted = rect;
      final radius = _borderRadius ?? BorderRadius.circular(rect.shortestSide / 2);
      context.canvas.drawRRect(
        radius.toRRect(rect.shift(offset)),
        Paint()..color = _color,
      );
    } else {
      _lastPainted = null;
    }
    defaultPaint(context, offset);
  }
}
