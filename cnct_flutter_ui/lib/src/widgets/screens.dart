import 'package:flutter/material.dart';

import '../bidi.dart';
import 'cards.dart' show ErrorLine;
import 'composer.dart';
import 'fields.dart';
import 'header.dart';
import 'parts.dart';
import 'scope.dart';
import 'thread.dart';

/// The conversation screen: header, the reconnecting line, the thread, and the footer.
class ConversationScreen extends StatelessWidget {
  const ConversationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ChatScope.of(context).controller;
    return Column(
      children: [
        const ChatHeader(),
        if (controller.isOffline) const OfflineBanner(),
        const Expanded(child: ChatThread()),
        const ChatFooter(),
      ],
    );
  }
}

/// Before the inbox has answered.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return Column(
      children: [
        _BareHeader(scope: scope),
        Expanded(
          child: Center(
            child: Semantics(
              liveRegion: true,
              label: scope.l10n.t('connecting'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 3, color: scope.theme.primary),
                  ),
                  const SizedBox(height: 14),
                  ExcludeSemantics(
                    child: Text(scope.l10n.t('connecting'), style: scope.styles.small),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A wrong link, an inbox switched off, or a platform that could not be reached.
class UnavailableScreen extends StatelessWidget {
  const UnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final controller = scope.controller;
    return Column(
      children: [
        _BareHeader(scope: scope),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forum_outlined, size: 40, color: scope.theme.textMuted),
                  const SizedBox(height: 16),
                  Text(
                    controller.unavailableTitle?.resolve(scope.l10n) ?? '',
                    style: scope.styles.title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.unavailableBody?.resolve(scope.l10n) ?? '',
                    style: scope.styles.small,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A header with nothing to say yet but how to leave.
class _BareHeader extends StatelessWidget {
  const _BareHeader({required this.scope});
  final ChatScope scope;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: scope.onClose == null
              ? null
              : ChatIconButton(
                  icon: Icons.close,
                  label: scope.l10n.t('closeChat'),
                  onPressed: scope.onClose,
                ),
        ),
      ),
    );
  }
}

/// "Your name" before the first message, for an inbox that asks first — and a phone number, where
/// it wants one.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final controller = scope.controller;
    final l10n = scope.l10n;
    final inbox = controller.inbox;
    void submit() => controller.submitIntro(name: _name.text, phone: _phone.text);

    return Column(
      children: [
        _BareHeader(scope: scope),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: BrandMark(size: 64)),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        child: ChatText(
                          theme.title,
                          style: scope.styles.heading,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if ((inbox?.greeting ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ChatText(
                          inbox!.greeting,
                          style: scope.styles.body.copyWith(color: theme.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(l10n.t('yourName'),
                          style: scope.styles.small.copyWith(
                            color: theme.text,
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(height: 6),
                      ChatTextField(
                        controller: _name,
                        hint: l10n.t('namePlaceholder'),
                        autofillHints: const [AutofillHints.givenName],
                        maxLength: 60,
                        textInputAction: (inbox?.requirePhone ?? false)
                            ? TextInputAction.next
                            : TextInputAction.go,
                        onSubmitted: (_) => submit(),
                      ),
                      if (inbox?.requirePhone ?? false) ...[
                        const SizedBox(height: 16),
                        Text(
                          '${l10n.t('phoneNumber')} · ${l10n.t('optional')}',
                          style: scope.styles.small.copyWith(
                            color: theme.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ChatTextField(
                          controller: _phone,
                          hint: '',
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          maxLength: 32,
                          forceLeftToRight: true,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => submit(),
                        ),
                        const SizedBox(height: 6),
                        Text(l10n.t('phoneHint'), style: scope.styles.caption),
                      ],
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: controller.introBusy ? l10n.t('starting') : l10n.t('startChatting'),
                        busy: controller.introBusy,
                        onPressed: _name.text.trim().isEmpty ? null : submit,
                      ),
                      if (controller.introError != null) ...[
                        const SizedBox(height: 10),
                        ErrorLine(controller.introError!.resolve(l10n)),
                      ],
                      const SizedBox(height: 16),
                      Text(l10n.t('legal'),
                          style: scope.styles.caption, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (theme.showPoweredBy) const SafeArea(top: false, child: PoweredBy()),
      ],
    );
  }
}
