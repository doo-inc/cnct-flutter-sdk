import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/material.dart';

import '../bidi.dart';
import 'cards.dart';
import 'parts.dart';
import 'scope.dart';
import 'viewer.dart';

/// The conversation: oldest at the top, scrolled to the newest, which stays in view when the
/// keyboard opens because the list is anchored at its bottom.
class ChatThread extends StatefulWidget {
  const ChatThread({super.key});

  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  final _scroll = ScrollController();

  /// Each message's place in the thread, so a quote can scroll to what it quotes.
  final Map<String, GlobalKey> _anchors = {};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _anchor(String id) => _anchors.putIfAbsent(id, GlobalKey.new);

  void _showQuoted(String messageId) {
    final context = _anchors[messageId]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: MediaQuery.disableAnimationsOf(this.context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final items = _items(scope);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      itemCount: items.length,
      itemBuilder: (_, index) => items[items.length - 1 - index],
    );
  }

  /// Everything in the thread, oldest first: days, runs of one voice, then what the conversation is
  /// waiting for, the typing dots, and the cards.
  List<Widget> _items(ChatScope scope) {
    final controller = scope.controller;
    final l10n = scope.l10n;
    final messages = controller.messages;
    final out = <Widget>[];

    final greeting = controller.greeting;
    if (greeting != null) out.add(SystemLine(greeting, key: const ValueKey('greeting')));

    String? lastDay;
    ThreadRun? run;
    void flush() {
      final current = run;
      if (current == null) return;
      out.add(RunView(
        key: ValueKey('run:${_keyOf(current.messages.first)}'),
        run: current,
        anchor: _anchor,
        onShowQuoted: _showQuoted,
      ));
      run = null;
    }

    for (final message in messages) {
      final day = l10n.day(message.createdAt);
      if (day != lastDay) {
        flush();
        out.add(DayStamp(day, key: ValueKey('day:$day')));
        lastDay = day;
      }
      if (message.speaker == CnctSpeaker.system || message.speaker == CnctSpeaker.unknown) {
        flush();
        out.add(SystemLine(message.words, key: ValueKey('system:${_keyOf(message)}')));
        continue;
      }
      final signer = _signer(message);
      if (run == null || run!.signer != signer) {
        flush();
        run = ThreadRun(signer, mine: message.isMine);
      }
      run!.messages.add(message);
    }

    // "Seen" under the visitor's last words once the team has read them — only when theirs are the
    // last words: after a reply, the reply says it better.
    final last = messages.isEmpty ? null : messages.last;
    if (run != null &&
        last != null &&
        last.isMine &&
        !last.pending &&
        !last.failed &&
        (controller.conversation?.hasSeen(last) ?? false)) {
      run!.seen = true;
    }
    flush();

    final awaiting = controller.awaiting;
    if (awaiting != null && awaiting.choices.isNotEmpty) {
      out.add(ChoicesView(flow: awaiting, key: const ValueKey('choices')));
    }
    final suggestions = controller.suggestions;
    if (suggestions.isNotEmpty) {
      out.add(SuggestionsView(suggestions: suggestions, key: const ValueKey('suggestions')));
    }
    if (controller.theyAreTyping) out.add(const TypingIndicator(key: ValueKey('typing')));

    if (controller.justNamed != null) {
      out.add(NamedNote(key: const ValueKey('named'), name: controller.justNamed!));
    } else if (controller.asksForName) {
      out.add(const DetailsCard(key: ValueKey('details')));
    }
    final conversation = controller.conversation;
    if (conversation != null && !controller.isLive) {
      out.add(const EndedDivider(key: ValueKey('ended')));
      if (controller.showsRating) out.add(const RatingCard(key: ValueKey('rating')));
    }
    return out;
  }

  static String _keyOf(CnctChatMessage message) => message.clientKey ?? message.id;

  /// Who a message is from, as one comparable string — what decides where a run starts.
  static String _signer(CnctChatMessage message) {
    if (message.isMine) return 'you';
    final sender = message.sender;
    if (sender != null) return sender.identity;
    return message.speaker == CnctSpeaker.ai ? 'ai' : 'business';
  }
}

/// One run of the same voice, as the thread groups it.
class ThreadRun {
  ThreadRun(this.signer, {required this.mine});
  final String signer;
  final bool mine;
  final List<CnctChatMessage> messages = [];
  bool seen = false;
}

/// "Today", centred between runs.
class DayStamp extends StatelessWidget {
  const DayStamp(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(label, style: scope.styles.caption.copyWith(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// A line from the platform — a greeting, an out-of-hours notice — centred, not a bubble.
class SystemLine extends StatelessWidget {
  const SystemLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Center(
        child: ChatText(
          text,
          style: scope.styles.small,
          textAlign: TextAlign.center,
          onOpenLink: scope.onOpenLink,
        ),
      ),
    );
  }
}

/// One run of the same voice: the bubbles, then a byline under them — the face, the name, an "AI"
/// tag where it applies, and the time. Signed underneath, like a letter, so the bubbles get the
/// full width and the name is read after what was said.
class RunView extends StatelessWidget {
  const RunView({
    super.key,
    required this.run,
    required this.anchor,
    required this.onShowQuoted,
  });

  final ThreadRun run;
  final GlobalKey Function(String id) anchor;
  final ValueChanged<String> onShowQuoted;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final messages = run.messages;
    final last = messages.last;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final maxWidth = math.min(constraints.maxWidth * 0.8, 520.0);
        return Column(
          crossAxisAlignment: run.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < messages.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: MessageBubble(
                    key: anchor(messages[i].id),
                    message: messages[i],
                    mine: run.mine,
                    first: i == 0,
                    last: i == messages.length - 1,
                    onShowQuoted: onShowQuoted,
                  ),
                ),
              ),
            if (!last.failed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Byline(run: run, scope: scope),
              ),
          ],
        );
      }),
    );
  }
}

/// Under a run: who and when.
class Byline extends StatelessWidget {
  const Byline({super.key, required this.run, required this.scope});

  final ThreadRun run;
  final ChatScope scope;

  @override
  Widget build(BuildContext context) {
    final l10n = scope.l10n;
    final first = run.messages.first;
    final last = run.messages.last;
    final style = scope.styles.caption;
    final when = last.pending ? l10n.t('sending') : l10n.clock(last.createdAt);
    final business = scope.controller.inbox?.business ?? scope.theme.title;
    final name = first.sender?.name ?? business;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!run.mine) ...[
          Face(sender: first.sender, fallbackName: business, size: 20),
          const SizedBox(width: 6),
          Flexible(
            child: ChatText(
              name,
              style: style.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (first.speaker == CnctSpeaker.ai) ...[
            const SizedBox(width: 6),
            _AiTag(scope: scope),
          ],
          Text('  ·  ', style: style),
        ],
        Text(when, style: style),
        if (run.seen) ...[
          Text('  ·  ', style: style),
          Icon(Icons.done_all, size: 14, color: scope.theme.accentOn(scope.theme.background)),
          const SizedBox(width: 3),
          Text(l10n.t('seen'), style: style),
        ],
      ],
    );
  }
}

class _AiTag extends StatelessWidget {
  const _AiTag({required this.scope});
  final ChatScope scope;

  @override
  Widget build(BuildContext context) {
    final theme = scope.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'AI',
        style: scope.styles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// One message: its quote, a flow's picture, the words, a flow's footer, its files, and — when it
/// did not send — the way to try again.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.first,
    required this.last,
    required this.onShowQuoted,
  });

  final CnctChatMessage message;
  final bool mine;
  final bool first;
  final bool last;
  final ValueChanged<String> onShowQuoted;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final l10n = scope.l10n;
    final background = mine ? theme.visitorBubble : theme.agentBubble;
    final ink = mine ? theme.onVisitorBubble : theme.onAgentBubble;
    final words = message.words;
    final hasWords = words.trim().isNotEmpty;
    final images = message.attachments.where((file) => file.isImage).toList();
    final documents = message.attachments.where((file) => !file.isImage).toList();
    final onlyPictures = !hasWords &&
        documents.isEmpty &&
        message.replyTo == null &&
        message.flow?.media == null &&
        images.isNotEmpty;

    // Runs tuck in towards their speaker: the corners between two bubbles of one voice are small,
    // on the speaker's side, so a run reads as one turn.
    final big = Radius.circular(theme.cornerRadius);
    final small = Radius.circular(math.min(theme.cornerRadius, 6));
    final radius = BorderRadiusDirectional.only(
      topStart: !mine && !first ? small : big,
      bottomStart: !mine && !last ? small : big,
      topEnd: mine && !first ? small : big,
      bottomEnd: mine && !last ? small : big,
    ).resolve(Directionality.of(context));
    final inner = Radius.circular(math.max(0, theme.cornerRadius - 6));

    final speaker = mine
        ? l10n.t('you')
        : (message.sender?.name ?? scope.controller.inbox?.business ?? theme.title);
    final content = <Widget>[
      if (message.replyTo != null)
        QuoteView(
          quote: message.replyTo!,
          ink: ink,
          background: background,
          onShowQuoted: onShowQuoted,
        ),
      if (message.flow?.media != null)
        FlowMediaView(media: message.flow!.media!, radius: inner, ink: ink),
      if (hasWords)
        Semantics(
          container: true,
          label: mine
              ? l10n.t('youSaid', {'text': words})
              : l10n.t('theySaid', {'name': speaker, 'text': words}),
          excludeSemantics: true,
          child: ChatText(
            words,
            style: scope.styles.body.copyWith(color: ink),
            linkColor: ink,
            onOpenLink: scope.onOpenLink,
          ),
        ),
      if (message.flow?.footer != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: ChatText(
            message.flow!.footer!,
            style: scope.styles.small.copyWith(color: ink.withValues(alpha: 0.78)),
          ),
        ),
      for (final image in images)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: ImageAttachment(
            attachment: image,
            radius: onlyPictures ? radius : BorderRadius.all(inner),
          ),
        ),
      for (final document in documents)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: FileAttachment(attachment: document, ink: ink, background: background),
        ),
    ];

    Widget bubble = onlyPictures
        ? Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: content,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: radius,
              // A hairline where the bubble is the colour of the page, so it still reads as one.
              border: contrastBorder(background, theme.background, theme.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content,
              ),
            ),
          );
    if (message.pending) bubble = Opacity(opacity: 0.62, child: bubble);
    if (!message.failed) return bubble;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        bubble,
        Semantics(
          button: true,
          child: InkWell(
            onTap: () => scope.controller.retry(message),
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: minTouchTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 16, color: theme.danger),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l10n.t('notSent'),
                        style: scope.styles.caption.copyWith(
                          color: theme.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A hairline border when a bubble is near the colour behind it, and none when it stands out on
/// its own.
Border? contrastBorder(Color bubble, Color page, Color line) =>
    bubble.toARGB32() == page.toARGB32() || _closeTo(bubble, page) ? Border.all(color: line) : null;

bool _closeTo(Color a, Color b) {
  final x = a.toARGB32();
  final y = b.toARGB32();
  var distance = 0;
  for (final shift in const [16, 8, 0]) {
    distance += (((x >> shift) & 0xFF) - ((y >> shift) & 0xFF)).abs();
  }
  return distance < 40;
}

/// The message this one replies to, drawn above its words: a bar, whose it was, and its first
/// words or the kind of file it was. Tapping it scrolls to that message, if it is in the thread.
class QuoteView extends StatelessWidget {
  const QuoteView({
    super.key,
    required this.quote,
    required this.ink,
    required this.background,
    required this.onShowQuoted,
  });

  final CnctChatQuote quote;
  final Color ink;
  final Color background;
  final ValueChanged<String> onShowQuoted;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final l10n = scope.l10n;
    final words = quote.excerpt ??
        (quote.attachmentKind == null
            ? l10n.t('quoteEarlier')
            : l10n.t('quote${quote.attachmentKind!.wireName}'));
    final body = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: BorderDirectional(start: BorderSide(color: ink.withValues(alpha: 0.6), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quote.mine)
            Text(
              l10n.t('quoteYou'),
              style: scope.styles.caption.copyWith(color: ink, fontWeight: FontWeight.w700),
            ),
          ChatText(
            words,
            style: scope.styles.small.copyWith(color: ink.withValues(alpha: 0.85)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    final id = quote.messageId;
    if (id == null) return body;
    return Semantics(
      button: true,
      label: l10n.t('showQuoted'),
      child: GestureDetector(onTap: () => onShowQuoted(id), child: body),
    );
  }
}

/// A flow's picture above its words. Public, so it needs no token.
class FlowMediaView extends StatelessWidget {
  const FlowMediaView({super.key, required this.media, required this.radius, required this.ink});

  final CnctFlowMedia media;
  final Radius radius;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    if (media.kind == CnctAttachmentKind.image) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.all(radius),
          child: Image.network(
            media.url.toString(),
            fit: BoxFit.cover,
            semanticLabel: scope.l10n.t('quoteIMAGE'),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    }
    final name = media.filename ?? scope.l10n.t('attachment');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        link: true,
        label: scope.l10n.t('openDocument', {'name': name}),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => scope.onOpenLink(media.url),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                media.kind == CnctAttachmentKind.video ? Icons.play_circle_outline : Icons.link,
                color: ink,
                size: 20,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: ChatText(
                  name,
                  style:
                      scope.styles.body.copyWith(color: ink, decoration: TextDecoration.underline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A picture in the thread, in its own shape, fetched with the visitor's token and cached by id.
/// Tapping it opens the full-screen viewer.
class ImageAttachment extends StatefulWidget {
  const ImageAttachment({super.key, required this.attachment, required this.radius});

  final CnctChatAttachment attachment;
  final BorderRadius radius;

  /// The longest side a thumbnail takes in the thread.
  static const maxSide = 240.0;

  @override
  State<ImageAttachment> createState() => _ImageAttachmentState();
}

class _ImageAttachmentState extends State<ImageAttachment> {
  Future<Uint8List>? _bytes;
  String? _for;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final l10n = scope.l10n;
    if (_for != widget.attachment.id) {
      _for = widget.attachment.id;
      _bytes = scope.controller.fileBytes(widget.attachment.id);
    }
    final label = withoutIsolates([
      l10n.t('quoteIMAGE'),
      if (widget.attachment.bytes != null) l10n.size(widget.attachment.bytes),
    ].join(', '));
    final placeholder = Container(
      width: ImageAttachment.maxSide,
      height: ImageAttachment.maxSide * 0.66,
      color: theme.surface,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: theme.textMuted),
    );

    return Semantics(
      container: true,
      image: true,
      button: true,
      label: label,
      child: ClipRRect(
        borderRadius: widget.radius,
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Container(
                padding: const EdgeInsets.all(12),
                color: theme.surface,
                child: Text(
                  l10n.t('couldNotLoad', {'name': widget.attachment.filename ?? ''}),
                  style: scope.styles.small,
                ),
              );
            }
            final bytes = snapshot.data;
            if (bytes == null) return placeholder;
            return GestureDetector(
              onTap: () => showImageViewer(
                context,
                bytes: bytes,
                attachment: widget.attachment,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ImageAttachment.maxSide,
                  maxHeight: ImageAttachment.maxSide,
                ),
                child: Image.memory(
                  bytes,
                  // Decoded at the size it is drawn, not at the size the camera took it.
                  cacheWidth:
                      (ImageAttachment.maxSide * MediaQuery.devicePixelRatioOf(context)).round(),
                  excludeFromSemantics: true,
                  gaplessPlayback: true,
                  frameBuilder: (_, child, frame, synchronous) =>
                      frame == null && !synchronous ? placeholder : child,
                  errorBuilder: (_, __, ___) => placeholder,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Anything that is not a picture: an icon for its kind, its name and its size. Tapping it
/// downloads it with the visitor's token and hands it to the platform to open or share.
class FileAttachment extends StatelessWidget {
  const FileAttachment({
    super.key,
    required this.attachment,
    required this.ink,
    required this.background,
  });

  final CnctChatAttachment attachment;
  final Color ink;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final l10n = scope.l10n;
    final name = attachment.filename ?? l10n.t('attachment');
    final dot = name.lastIndexOf('.');
    final extension = dot > 0 ? name.substring(dot + 1).toUpperCase() : '';
    final details = [l10n.size(attachment.bytes), extension].where((part) => part.isNotEmpty);
    return Semantics(
      container: true,
      button: true,
      label: withoutIsolates(
          '${l10n.t('openDocument', {'name': name})}, ${l10n.size(attachment.bytes)}'),
      excludeSemantics: true,
      child: Material(
        color: ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: Builder(builder: (context) {
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              final box = context.findRenderObject() as RenderBox?;
              final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
              scope.controller.openAttachment(attachment, origin: origin);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: minTouchTarget, minWidth: 200),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(iconFor(attachment.kind, attachment.mimeType), color: ink),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChatText(
                            name,
                            style: scope.styles.body.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            details.join(' · '),
                            style:
                                scope.styles.caption.copyWith(color: ink.withValues(alpha: 0.75)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.download_rounded, size: 20, color: ink.withValues(alpha: 0.8)),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// An icon for a kind of file.
IconData iconFor(CnctAttachmentKind kind, String mimeType) {
  if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
  return switch (kind) {
    CnctAttachmentKind.image || CnctAttachmentKind.sticker => Icons.image_outlined,
    CnctAttachmentKind.video => Icons.movie_outlined,
    CnctAttachmentKind.audio => Icons.graphic_eq,
    _ => mimeType.contains('sheet') || mimeType == 'text/csv'
        ? Icons.table_chart_outlined
        : Icons.description_outlined,
  };
}

/// What a flow is waiting for: its choices, as pills, or as rows when they carry descriptions or
/// the flow asked for a list. Tapping one sends its title with its id.
class ChoicesView extends StatelessWidget {
  const ChoicesView({super.key, required this.flow});

  final CnctChatFlow flow;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final controller = scope.controller;
    final accent = theme.accentOn(theme.background);
    final rows = flow.layout == CnctFlowLayout.list ||
        flow.choices.any((choice) => choice.description != null);
    final label = flow.listButton ?? scope.l10n.t('choices');

    if (!rows) {
      return Semantics(
        container: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in flow.choices)
                OutlinedButton(
                  onPressed: () => controller.choose(choice),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                    minimumSize: const Size(minTouchTarget, minTouchTarget),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: StadiumBorder(side: BorderSide(color: accent)),
                    textStyle: scope.styles.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: ChatText(choice.title, style: scope.styles.body.copyWith(color: accent)),
                ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          decoration: BoxDecoration(
            color: theme.surface,
            border: Border.all(color: theme.border),
            borderRadius: BorderRadius.circular(theme.cornerRadius.clamp(4, 18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (flow.listButton != null)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 4),
                  child: ChatText(flow.listButton!, style: scope.styles.small),
                ),
              for (final (index, choice) in flow.choices.indexed) ...[
                if (index > 0) Divider(height: 1, color: theme.border),
                InkWell(
                  onTap: () => controller.choose(choice),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: minTouchTarget),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ChatText(
                                  choice.title,
                                  style: scope.styles.body.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (choice.description != null)
                                  ChatText(choice.description!, style: scope.styles.small),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: theme.textMuted),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Replies the assistant offered with its last answer, as chips on the visitor's side: tap one and
/// it is sent.
class SuggestionsView extends StatelessWidget {
  const SuggestionsView({super.key, required this.suggestions});

  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final accent = theme.accentOn(theme.background);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final suggestion in suggestions)
            ActionChip(
              onPressed: () => scope.controller.suggest(suggestion),
              label: ChatText(suggestion, style: scope.styles.body.copyWith(color: accent)),
              backgroundColor: theme.background,
              side: BorderSide(color: accent),
              shape: const StadiumBorder(),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      ),
    );
  }
}

/// Three dots where the team's next words will be.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Still where motion is switched off: the dots say "typing" without moving.
    if (MediaQuery.disableAnimationsOf(context)) {
      _beat.stop();
    } else if (!_beat.isAnimating) {
      _beat.repeat();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        liveRegion: true,
        label: scope.l10n.t('teamTyping'),
        child: Container(
          margin: const EdgeInsets.only(top: 2, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.agentBubble,
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            border: contrastBorder(theme.agentBubble, theme.background, theme.border),
          ),
          child: AnimatedBuilder(
            animation: _beat,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : 5),
                    child: Opacity(
                      opacity: _dot(i),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: theme.onAgentBubble,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _dot(int index) {
    final phase = (_beat.value - index * 0.18) % 1;
    return 0.35 + 0.65 * math.max(0, math.sin(phase * math.pi));
  }
}
