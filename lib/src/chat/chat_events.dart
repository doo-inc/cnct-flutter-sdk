import '../exception.dart';
import 'chat_models.dart';

/// Something that happened, as opposed to something that is true.
///
/// [CnctChatState] is enough to render the whole interface; these are for the things a UI *does*
/// rather than shows — playing a sound on a new message, scrolling to the bottom, sending the
/// visitor back to a login screen when their session is refused.
sealed class CnctChatEvent {
  const CnctChatEvent();
}

/// The socket is up and the transcript has been refetched.
class CnctChatConnected extends CnctChatEvent {
  const CnctChatConnected();
}

/// The socket dropped. A reconnect is already scheduled; nothing is required of you.
class CnctChatDisconnected extends CnctChatEvent {
  const CnctChatDisconnected();
}

/// The session token was refused and has been cleared. The visitor is a stranger again — show
/// whatever you show before a conversation starts.
class CnctChatUnauthenticated extends CnctChatEvent {
  const CnctChatUnauthenticated();
}

/// A message arrived. Already in [CnctChatState.messages] by the time this is emitted.
class CnctChatMessageReceived extends CnctChatEvent {
  const CnctChatMessageReceived(this.message);
  final CnctChatMessage message;
}

/// The other side is typing.
class CnctChatTypingReceived extends CnctChatEvent {
  const CnctChatTypingReceived();
}

/// The conversation changed — assigned to somebody, snoozed, reopened.
class CnctChatConversationUpdated extends CnctChatEvent {
  const CnctChatConversationUpdated(this.conversation);
  final CnctChatConversation conversation;
}

/// The conversation was closed, by the visitor or by the business.
class CnctChatClosed extends CnctChatEvent {
  const CnctChatClosed();
}

/// Something failed. Also in [CnctChatState.error].
class CnctChatErrored extends CnctChatEvent {
  const CnctChatErrored(this.error);
  final CnctException error;
}
