import '../exception.dart';
import 'chat_models.dart';

/// Where the chat client is.
enum CnctChatStatus {
  /// No session. `boot()` may have run; nobody has started a conversation.
  idle,

  /// A session exists and the socket is being opened.
  connecting,

  /// Connected. Messages arrive as they are written.
  live,

  /// The socket dropped and is being retried. **Not an error state** — the transcript is still
  /// true, sends still work over HTTP, and the client is already backing off towards a reconnect.
  offline,

  /// The conversation is closed. It cannot be reopened; `start()` a new one.
  ended,
}

/// Everything a UI renders, in one immutable snapshot.
///
/// Replaced rather than mutated on every change, so a `ValueNotifier`, a `StreamBuilder`, a Bloc or
/// a Riverpod provider comparing references all see the change, and anything reading fields sees a
/// consistent picture rather than a half-applied one.
class CnctChatState {
  const CnctChatState({
    this.status = CnctChatStatus.idle,
    this.inbox,
    this.conversation,
    this.visitor,
    this.messages = const [],
    this.theyAreTyping = false,
    this.error,
  });

  final CnctChatStatus status;

  /// What `boot()` returned. Null until it has run.
  final CnctChatInbox? inbox;

  final CnctChatConversation? conversation;
  final CnctChatVisitor? visitor;

  /// Oldest first.
  final List<CnctChatMessage> messages;

  /// True while the other side is typing. Clears itself after four seconds — the platform sends a
  /// start, never a stop, because a stop that goes missing leaves an indicator on the screen for
  /// ever.
  final bool theyAreTyping;

  /// The last failure, or null. Cleared by the next success.
  final CnctException? error;

  /// True when there is a conversation to type into.
  bool get canSend =>
      status != CnctChatStatus.idle &&
      status != CnctChatStatus.ended &&
      conversation?.status != CnctConversationStatus.closed;

  /// Messages that failed to send and are waiting for a retry.
  List<CnctChatMessage> get failed =>
      messages.where((message) => message.failed).toList(growable: false);

  CnctChatState copyWith({
    CnctChatStatus? status,
    CnctChatInbox? inbox,
    CnctChatConversation? conversation,
    CnctChatVisitor? visitor,
    List<CnctChatMessage>? messages,
    bool? theyAreTyping,
    CnctException? error,
    bool clearError = false,
    bool clearConversation = false,
    bool clearVisitor = false,
  }) =>
      CnctChatState(
        status: status ?? this.status,
        inbox: inbox ?? this.inbox,
        conversation: clearConversation ? null : (conversation ?? this.conversation),
        visitor: clearVisitor ? null : (visitor ?? this.visitor),
        messages: messages ?? this.messages,
        theyAreTyping: theyAreTyping ?? this.theyAreTyping,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  String toString() =>
      'CnctChatState(${status.name}, ${messages.length} messages${theyAreTyping ? ', typing' : ''})';
}
