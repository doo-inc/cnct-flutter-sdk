import 'dart:async';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/material.dart';

/// A complete chat screen, and a deliberately ordinary one.
///
/// Nothing here is provided by the SDK: the bubbles, the composer, the retry button and the cards
/// are all this app's. That is the arrangement — the SDK ships state and events, the interface is
/// yours. What it does give you is the guarantee that rendering [CnctChatState] is always rendering
/// the truth, including straight after a reconnect.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.cnct,
    required this.publicKey,
    required this.tokenStore,
    super.key,
  });

  final Cnct cnct;
  final String publicKey;
  final CnctTokenStore tokenStore;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final CnctChatClient _chat;
  late final StreamSubscription<CnctChatEvent> _events;
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  CnctChatInbox? _inbox;
  Object? _bootFailure;

  @override
  void initState() {
    super.initState();
    _chat = widget.cnct.chat(
      CnctChatPublicKey(widget.publicKey),
      tokenStore: widget.tokenStore,
    );
    _events = _chat.events.listen(_onEvent);
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final inbox = await _chat.boot();
      if (!mounted) return;
      setState(() => _inbox = inbox);
      // A visitor who has been here before comes straight back to their own thread. False simply
      // means this is their first time — not an error.
      final resumed = await _chat.resume();
      if (!resumed && inbox.isActive && !inbox.requirePhone) {
        await _chat.start(displayName: 'Visitor');
      }
    } on CnctException catch (error) {
      if (mounted) setState(() => _bootFailure = error);
    }
  }

  void _onEvent(CnctChatEvent event) {
    switch (event) {
      case CnctChatMessageReceived():
        _scrollToEnd();
      case CnctChatUnauthenticated():
        // Their thirty days ran out, or the conversation was closed from the other side. They are a
        // stranger again; start them over rather than leaving a dead screen.
        unawaited(_chat.start(displayName: 'Visitor'));
      default:
        break;
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    try {
      await _chat.send(text);
      _scrollToEnd();
    } on CnctException {
      // Nothing to do here: the bubble is still on screen, marked failed, with a retry button.
    }
  }

  @override
  void dispose() {
    unawaited(_events.cancel());
    _chat.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bootFailure != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(child: Text('$_bootFailure')),
      );
    }
    final inbox = _inbox;
    if (inbox == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<CnctChatState>(
      initialData: _chat.state,
      stream: _chat.states,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const CnctChatState();
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(inbox.business),
                // `withPerson` says somebody is on the thread. Never who — the platform does not
                // publish a colleague's name to a customer, so neither does this.
                _Status(state: state),
              ],
            ),
          ),
          body: Column(
            children: [
              if (!inbox.isActive)
                const _Banner('This inbox is closed right now.'),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) => _Bubble(
                    message: state.messages[index],
                    onRetry: _chat.retry,
                  ),
                ),
              ),
              if (state.theyAreTyping) const _Typing(),
              _Composer(
                controller: _composer,
                enabled: state.canSend,
                onChanged: (_) => _chat.typing(),
                onSend: _send,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.state});

  final CnctChatState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state.status) {
      CnctChatStatus.live when state.conversation?.withPerson == true => 'Someone is with you',
      CnctChatStatus.live => 'Connected',
      CnctChatStatus.connecting => 'Connecting…',
      // Offline is not an error: the transcript is still true and sends still go over HTTP.
      CnctChatStatus.offline => 'Reconnecting…',
      CnctChatStatus.ended => 'This conversation has ended',
      CnctChatStatus.idle => '',
    };
    return Text(label, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onRetry});

  final CnctChatMessage message;
  final Future<CnctChatMessage> Function(String clientKey) onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.speaker == CnctSpeaker.caller;

    // Switching on `type` is the whole of card handling, and the `default` is the compatibility
    // story: a card type added to the platform next year arrives here with a `body` that reads
    // correctly as a sentence, so this app shows something true rather than an empty bubble.
    final Widget content = switch (message.type) {
      CnctMessageType.ticketUpdate when message.ticket != null => _Card(
          icon: Icons.receipt_long,
          title: 'Ticket #${message.ticket!.ticketNumber}',
          lines: [message.ticket!.title, message.ticket!.status],
        ),
      CnctMessageType.bookingUpdate when message.booking != null => _Card(
          icon: Icons.event,
          title: message.booking!.title,
          lines: [
            // Their locale, not the business's — the SDK has already converted the instant.
            '${message.booking!.startsAt}',
            if (message.booking!.locationName != null) message.booking!.locationName!,
            message.booking!.status,
          ],
        ),
      _ => Text(message.body),
    };

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: mine ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: message.failed ? Border.all(color: theme.colorScheme.error) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(opacity: message.pending ? 0.6 : 1, child: content),
            for (final attachment in message.attachments)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.attach_file, size: 16),
                    const SizedBox(width: 4),
                    Flexible(child: Text(attachment.filename ?? attachment.mimeType)),
                  ],
                ),
              ),
            // The words somebody typed never disappear on a failure — they get a way back.
            if (message.failed && message.clientKey != null)
              TextButton.icon(
                onPressed: () => onRetry(message.clientKey!).ignore(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.lines});

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              for (final line in lines) Text(line),
            ],
          ),
        ),
      ],
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(alignment: Alignment.centerLeft, child: Text('typing…')),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Text(text),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                // Throttled inside the SDK to one frame every three seconds, and again on the
                // server, so calling it per keystroke is the intended use.
                onChanged: onChanged,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(onPressed: enabled ? onSend : null, icon: const Icon(Icons.send)),
          ],
        ),
      ),
    );
  }
}
