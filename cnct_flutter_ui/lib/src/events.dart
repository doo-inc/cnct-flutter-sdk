import 'package:flutter/foundation.dart';

/// What happened, for an app's analytics.
enum CnctChatUiEventType {
  /// The chat screen opened and the inbox answered.
  opened,

  /// A conversation started — from the name form, or from the first message.
  started,

  /// The visitor sent a message.
  sent,

  /// A file went with a message: one event per file.
  attachmentSent,

  /// The visitor ended the conversation.
  ended,

  /// The visitor rated a closed conversation.
  rated,
}

/// One thing that happened in the chat, handed to `onEvent`. Carries no message text and no
/// personal data — what a customer wrote is theirs and the business's, not an analytics vendor's.
@immutable
class CnctChatUiEvent {
  const CnctChatUiEvent(
    this.type, {
    this.conversationId,
    this.attachments = 0,
    this.mimeType,
    this.score,
  });

  final CnctChatUiEventType type;

  /// The conversation it happened in, once there is one.
  final String? conversationId;

  /// On [CnctChatUiEventType.sent]: how many files went with the message.
  final int attachments;

  /// On [CnctChatUiEventType.attachmentSent]: the file's type.
  final String? mimeType;

  /// On [CnctChatUiEventType.rated]: 1 (worst) to 5 (best).
  final int? score;

  @override
  String toString() => 'CnctChatUiEvent(${type.name}'
      '${conversationId == null ? '' : ', $conversationId'}'
      '${score == null ? '' : ', score $score'})';
}
