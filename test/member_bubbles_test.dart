import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/codes/widgets/code_list_pane.dart';

// 擁有者頭像右下角的小頭像數量
void main() {
  test('其他成員超過 3 位：2 個頭像加「…」', () {
    expect(memberBubbles(4, 3), (avatars: 2, more: true));
    expect(memberBubbles(20, 3), (avatars: 2, more: true));
  });

  test('剛好 3 位或更少：全部顯示', () {
    expect(memberBubbles(3, 3), (avatars: 3, more: false));
    expect(memberBubbles(2, 2), (avatars: 2, more: false));
    expect(memberBubbles(0, 0), (avatars: 0, more: false));
  });

  test('預覽資料比成員數少（舊資料、離線快取）時以預覽為上限', () {
    expect(memberBubbles(3, 0), (avatars: 0, more: false));
    expect(memberBubbles(5, 1), (avatars: 1, more: true));
  });
}
