import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import 'fields.dart';
import 'parts.dart';
import 'scope.dart';

/// A card in the thread, under the messages.
class ThreadCard extends StatelessWidget {
  const ThreadCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ChatScope.of(context).theme;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(theme.cornerRadius.clamp(4, 20)),
      ),
      child: child,
    );
  }
}

/// "Who are we talking to?" — asked in the thread once an anonymous visitor has said something.
class DetailsCard extends StatefulWidget {
  const DetailsCard({super.key});

  @override
  State<DetailsCard> createState() => _DetailsCardState();
}

class _DetailsCardState extends State<DetailsCard> {
  // Held here, not rebuilt with the thread, so a reply arriving never eats what they were typing.
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final controller = scope.controller;
    final l10n = scope.l10n;
    void save() => controller.saveProfile(name: _name.text, phone: _phone.text);
    return ThreadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.t('detailsTitle'), style: scope.styles.title),
          const SizedBox(height: 4),
          Text(l10n.t('detailsBody'), style: scope.styles.small),
          const SizedBox(height: 12),
          ChatTextField(
            controller: _name,
            hint: l10n.t('yourName'),
            autofillHints: const [AutofillHints.givenName],
            maxLength: 60,
            textInputAction: TextInputAction.next,
          ),
          if (controller.inbox?.requirePhone ?? false) ...[
            const SizedBox(height: 8),
            ChatTextField(
              controller: _phone,
              hint: l10n.t('detailsPhone'),
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              maxLength: 32,
              forceLeftToRight: true,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: PrimaryButton(
              label: l10n.t('detailsSave'),
              busy: controller.profileBusy,
              onPressed: save,
            ),
          ),
          if (controller.profileError != null) ...[
            const SizedBox(height: 8),
            ErrorLine(controller.profileError!.resolve(l10n)),
          ],
        ],
      ),
    );
  }
}

/// "Thanks, Layla — the team will see your name."
class NamedNote extends StatelessWidget {
  const NamedNote({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return ThreadCard(
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: scope.theme.accentOn(scope.theme.surface)),
          const SizedBox(width: 10),
          Expanded(child: Text(scope.l10n.t('detailsThanks', {'name': name}))),
        ],
      ),
    );
  }
}

/// "This conversation has ended", between two rules.
class EndedDivider extends StatelessWidget {
  const EndedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: scope.theme.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(scope.l10n.t('endedDivider'), style: scope.styles.caption),
          ),
          Expanded(child: Divider(color: scope.theme.border)),
        ],
      ),
    );
  }
}

/// "How did we do?" — five faces, worst to best, each with its word, because a face is read
/// differently across cultures and a screen reader reads none of them well.
class RatingCard extends StatefulWidget {
  const RatingCard({super.key});

  static const faces = [
    Icons.sentiment_very_dissatisfied,
    Icons.sentiment_dissatisfied,
    Icons.sentiment_neutral,
    Icons.sentiment_satisfied,
    Icons.sentiment_very_satisfied,
  ];

  @override
  State<RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<RatingCard> {
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final controller = scope.controller;
    final l10n = scope.l10n;
    final stage = controller.ratingStage;
    final score = controller.ratingScore;
    final ratable = controller.conversation?.ratable ?? false;

    return ThreadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            stage == RatingStage.faces ? l10n.t('ratePrompt') : l10n.t('rated'),
            style: scope.styles.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Semantics(
            container: true,
            label: l10n.t('ratePrompt'),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var value = 1; value <= 5; value++)
                  _Face(
                    icon: RatingCard.faces[value - 1],
                    label: l10n.t('rating$value'),
                    selected: score == value,
                    onTap:
                        ratable && stage == RatingStage.faces ? () => controller.rate(value) : null,
                  ),
              ],
            ),
          ),
          if (score != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.t('rating$score'),
                style: scope.styles.small,
                textAlign: TextAlign.center,
              ),
            ),
          if (stage == RatingStage.comment) ...[
            const SizedBox(height: 12),
            ChatTextField(
              controller: _comment,
              hint: l10n.t('tellUsMore'),
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                QuietButton(label: l10n.t('skip'), onPressed: controller.skipRatingComment),
                const SizedBox(width: 8),
                PrimaryButton(
                  label: l10n.t('send'),
                  onPressed: () => controller.sendRatingComment(_comment.text),
                ),
              ],
            ),
          ] else if (controller.conversation?.rating?.comment != null) ...[
            const SizedBox(height: 8),
            Text(
              '“${controller.conversation!.rating!.comment!}”',
              style: scope.styles.small.copyWith(fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ],
          if (controller.ratingError != null) ...[
            const SizedBox(height: 8),
            ErrorLine(controller.ratingError!.resolve(l10n)),
          ],
        ],
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.icon, required this.label, required this.selected, this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ChatScope.of(context).theme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        radius: 26,
        child: Container(
          width: minTouchTarget,
          height: minTouchTarget,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? theme.primary : null,
          ),
          child: Icon(icon, size: 30, color: selected ? theme.onPrimary : theme.textMuted),
        ),
      ),
    );
  }
}

/// A sentence that went wrong, in the danger colour, read out as it appears.
class ErrorLine extends StatelessWidget {
  const ErrorLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(text, style: scope.styles.small.copyWith(color: scope.theme.danger)),
    );
  }
}
