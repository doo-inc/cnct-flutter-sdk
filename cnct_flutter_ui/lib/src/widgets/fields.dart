import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bidi.dart';
import 'scope.dart';

/// A text field in the chat's own colours, whose text takes its own direction as it is typed:
/// Arabic typed into an English chat runs right to left, and the reverse.
class ChatTextField extends StatefulWidget {
  const ChatTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.forceLeftToRight = false,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.radius,
  });

  final TextEditingController controller;
  final String hint;
  final String? label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final int? maxLength;
  final int? minLines;
  final int? maxLines;

  /// Phone numbers and emails are typed left to right in either language.
  final bool forceLeftToRight;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final double? radius;

  @override
  State<ChatTextField> createState() => _ChatTextFieldState();
}

class _ChatTextFieldState extends State<ChatTextField> {
  TextDirection? _direction;

  @override
  void initState() {
    super.initState();
    _direction = firstStrongDirection(widget.controller.text);
    widget.controller.addListener(_follow);
  }

  @override
  void didUpdateWidget(ChatTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_follow);
      widget.controller.addListener(_follow);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_follow);
    super.dispose();
  }

  void _follow() {
    final next = firstStrongDirection(widget.controller.text);
    if (next != _direction) setState(() => _direction = next);
  }

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final radius = BorderRadius.circular(widget.radius ?? theme.cornerRadius.clamp(6, 22));
    OutlineInputBorder outline(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textDirection:
          widget.forceLeftToRight ? TextDirection.ltr : (_direction ?? Directionality.of(context)),
      textAlign: widget.forceLeftToRight && Directionality.of(context) == TextDirection.rtl
          ? TextAlign.right
          : TextAlign.start,
      style: scope.styles.body,
      cursorColor: theme.accentOn(theme.background),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: theme.background,
        hintText: widget.hint,
        labelText: widget.label,
        hintStyle: scope.styles.body.copyWith(color: theme.textMuted),
        labelStyle: scope.styles.small,
        hintMaxLines: 1,
        counterText: '',
        // Tall enough to be a 48-point target with one line in it.
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: outline(theme.border),
        enabledBorder: outline(theme.border),
        focusedBorder: outline(theme.accentOn(theme.background), 1.5),
      ),
    );
  }
}
