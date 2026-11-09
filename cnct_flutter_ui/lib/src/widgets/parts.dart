import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/material.dart';

import 'scope.dart';

/// The smallest a control may be to the touch: 48 logical pixels, which is Android's 48 dp and
/// clears iOS's 44 pt.
const minTouchTarget = 48.0;

/// The first letter of a name, for a face with no picture. Never an empty disc.
String initialOf(String? name) {
  final trimmed = (name ?? '').trim();
  if (trimmed.isEmpty) return '?';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// The business's logo, or its first letter on its colour — the theme's `logo` and `title`.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final letter = _Letter(
      letter: initialOf(theme.title),
      size: size,
      background: theme.primary,
      foreground: theme.onPrimary,
      style: scope.styles.title,
    );
    final logo = theme.logo;
    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: logo == null
              ? letter
              : Image(
                  image: logo,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  // A logo that fails to load leaves the letter behind, never a broken-image icon
                  // on the screen that decides whether a stranger starts a conversation.
                  errorBuilder: (_, __, ___) => letter,
                  frameBuilder: (_, child, frame, synchronous) =>
                      frame == null && !synchronous ? letter : child,
                ),
        ),
      ),
    );
  }
}

/// The face beside a reply: the assistant's mark, or a person's first letter. CNCT's own drawn
/// faces are keys into the console's artwork, which an app does not have; the letter is what the
/// hosted widget falls back to as well.
class Face extends StatelessWidget {
  const Face({super.key, required this.sender, required this.fallbackName, this.size = 24});

  final CnctChatSender? sender;
  final String fallbackName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    if (sender == null) return BrandMark(size: size);
    if (sender!.isAssistant) {
      return ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: theme.primary, shape: BoxShape.circle),
          child: Icon(Icons.auto_awesome, size: size * 0.58, color: theme.onPrimary),
        ),
      );
    }
    final tint = Color.alphaBlend(theme.primary.withValues(alpha: 0.16), theme.surface);
    return _Letter(
      letter: initialOf(sender!.name ?? fallbackName),
      size: size,
      background: tint,
      foreground: theme.accentOn(tint),
      style: scope.styles.caption,
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter({
    required this.letter,
    required this.size,
    required this.background,
    required this.foreground,
    required this.style,
  });

  final String letter;
  final double size;
  final Color background;
  final Color foreground;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Text(
          letter,
          // The letter fills the disc; it does not grow with the text size, which would only push
          // it out of a circle that cannot grow with it.
          textScaler: TextScaler.noScaling,
          style: style.copyWith(
            color: foreground,
            fontSize: size * 0.44,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// An icon that does something: a full-size touch target, a tooltip and a label in the chat's
/// language, whatever size the icon is drawn at.
class ChatIconButton extends StatelessWidget {
  const ChatIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.size = 22,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon, size: size, color: color),
      constraints: const BoxConstraints(minWidth: minTouchTarget, minHeight: minTouchTarget),
      padding: EdgeInsets.zero,
    );
  }
}

/// A filled button in the brand colour.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: theme.primary,
        foregroundColor: theme.onPrimary,
        disabledBackgroundColor: theme.primary.withValues(alpha: 0.45),
        disabledForegroundColor: theme.onPrimary,
        minimumSize: const Size(minTouchTarget, minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.cornerRadius.clamp(4, 24)),
        ),
        textStyle: scope.styles.body.copyWith(fontWeight: FontWeight.w600),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

/// A quiet text button: "Keep chatting", "No thanks", "End chat".
class QuietButton extends StatelessWidget {
  const QuietButton({super.key, required this.label, required this.onPressed, this.color});

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color ?? scope.theme.text,
        minimumSize: const Size(minTouchTarget, minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: scope.styles.body.copyWith(fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
