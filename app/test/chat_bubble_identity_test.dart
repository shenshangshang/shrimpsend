import 'package:app/chat/chat_bubble_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fileReceiveBubbleId prefers sender localId', () {
    expect(
      fileReceiveBubbleId(
        senderLocalId: 'abc',
        fallbackId: '123_web',
      ),
      'local_abc',
    );
    expect(
      fileReceiveBubbleId(senderLocalId: '  ', fallbackId: '123_web'),
      '123_web',
    );
    expect(
      fileReceiveBubbleId(senderLocalId: null, fallbackId: '123_web'),
      '123_web',
    );
  });

  test('wouldDuplicateChatBubbleId detects persist-after-offer collision', () {
    expect(
      wouldDuplicateChatBubbleId(
        existingBubbleId: 'local_recv',
        serverId: '123_web',
        serverIdAlreadyOnScreen: true,
      ),
      isTrue,
    );
    expect(
      wouldDuplicateChatBubbleId(
        existingBubbleId: 'local_recv',
        serverId: '123_web',
        serverIdAlreadyOnScreen: false,
      ),
      isFalse,
    );
    expect(
      wouldDuplicateChatBubbleId(
        existingBubbleId: '123_web',
        serverId: '123_web',
        serverIdAlreadyOnScreen: true,
      ),
      isFalse,
    );
  });
}
