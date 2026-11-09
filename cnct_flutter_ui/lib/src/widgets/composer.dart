import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bidi.dart';
import '../controller.dart';
import 'fields.dart';
import 'parts.dart';
import 'scope.dart';
import 'thread.dart' show iconFor;

/// Everything under the thread: the line that says what went wrong, the tray of picked files, and
/// then the composer — or the "End this chat?" question, or "Start a new conversation" once it is
/// over — and the "Powered by" line.
class ChatFooter extends StatelessWidget {
  const ChatFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final controller = scope.controller;
    final Widget main;
    if (!controller.isLive) {
      main = Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SizedBox(
          width: double.infinity,
          child: PrimaryButton(label: scope.l10n.t('startNew'), onPressed: controller.startNew),
        ),
      );
    } else if (controller.confirmingEnd) {
      main = const _EndConfirm();
    } else {
      main = const Composer();
    }
    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(top: BorderSide(color: theme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.notice != null) _Notice(controller.notice!.resolve(scope.l10n)),
            if (controller.uploads.isNotEmpty && controller.isLive) const UploadTray(),
            main,
            if (theme.showPoweredBy) const PoweredBy() else const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.info_outline, size: 18, color: scope.theme.danger),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: scope.styles.small.copyWith(color: scope.theme.text)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "End this chat? You can always start a new one."
class _EndConfirm extends StatelessWidget {
  const _EndConfirm();

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final controller = scope.controller;
    final l10n = scope.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.t('endConfirm'), style: scope.styles.body, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: controller.keepChatting,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scope.theme.text,
                    side: BorderSide(color: scope.theme.border),
                    minimumSize: const Size(minTouchTarget, minTouchTarget),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(scope.theme.cornerRadius.clamp(4, 24)),
                    ),
                  ),
                  child: Text(l10n.t('keepChatting')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: PrimaryButton(label: l10n.t('endChat'), onPressed: controller.end)),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Powered by CNCT".
class PoweredBy extends StatelessWidget {
  const PoweredBy({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final style = scope.styles.caption;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${scope.l10n.t('poweredBy')} '),
          // The product's name, which reads left to right in either language.
          TextSpan(text: '\u2066CNCT\u2069', style: style.copyWith(fontWeight: FontWeight.w700)),
        ]),
        style: style,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// The box, the paperclip and the send button.
///
/// It grows to five lines and then scrolls; send is off while there is nothing to send or a file is
/// still on its way; and the keyboard follows what the flow asked for, so a phone number brings up
/// the number pad.
class Composer extends StatefulWidget {
  const Composer({super.key});

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _send(ChatController controller) async {
    if (await controller.send(_text.text)) _text.clear();
  }

  /// Enter sends — on a device with a real keyboard. On a phone the keyboard's return key is the
  /// only way to write a second line, so there it does what it says and the button sends.
  bool get _enterSends =>
      kIsWeb ||
      switch (defaultTargetPlatform) {
        TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final controller = scope.controller;
    final l10n = scope.l10n;
    final awaiting = controller.awaiting;
    final (hint, keyboard) = switch (awaiting?.expects) {
      CnctFlowExpects.name => (l10n.t('answerName'), TextInputType.name),
      CnctFlowExpects.number => (
          l10n.t('answerNumber'),
          const TextInputType.numberWithOptions(decimal: true)
        ),
      CnctFlowExpects.email => (l10n.t('answerEmail'), TextInputType.emailAddress),
      CnctFlowExpects.phone => (l10n.t('answerPhone'), TextInputType.phone),
      CnctFlowExpects.date => (l10n.t('answerDate'), TextInputType.datetime),
      null => (
          (awaiting?.choices.isNotEmpty ?? false)
              ? l10n.t('chooseOrWrite')
              : l10n.t('writeMessage'),
          TextInputType.multiline
        ),
    };
    final hasFiles = controller.uploads.any((chip) => chip.status == UploadStatus.done);
    final canSend = !controller.uploading && (_text.text.trim().isNotEmpty || hasFiles);

    Widget field = ChatTextField(
      controller: _text,
      focusNode: _focus,
      hint: hint,
      keyboardType: keyboard,
      textInputAction: _enterSends ? TextInputAction.send : TextInputAction.newline,
      minLines: 1,
      maxLines: 5,
      maxLength: CnctChatClient.maxMessageLength,
      radius: 22,
      onChanged: (_) => controller.typed(),
    );
    if (_enterSends) {
      field = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () => _send(controller),
          const SingleActivator(LogicalKeyboardKey.numpadEnter): () => _send(controller),
        },
        child: field,
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (controller.canAttach)
            ChatIconButton(
              icon: Icons.attach_file,
              label: l10n.t('attach'),
              color: theme.textMuted,
              onPressed: () => showAttachSheet(context, scope),
            )
          else
            const SizedBox(width: 8),
          Expanded(child: field),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            enabled: canSend,
            label: controller.uploading ? l10n.t('uploading') : l10n.t('send'),
            excludeSemantics: true,
            child: Tooltip(
              message: controller.uploading ? l10n.t('uploading') : l10n.t('send'),
              child: InkResponse(
                onTap: canSend ? () => _send(controller) : null,
                radius: 26,
                child: Container(
                  width: minTouchTarget,
                  height: minTouchTarget,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: canSend ? theme.primary : theme.primary.withValues(alpha: 0.38),
                  ),
                  // `send` matches the text direction, so it points the way the line reads.
                  child: Icon(Icons.send_rounded, size: 22, color: theme.onPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Photo library, camera on phones, and files — the system's own pickers.
Future<void> showAttachSheet(BuildContext context, ChatScope scope) {
  final controller = scope.controller;
  final source = controller.files;
  final l10n = scope.l10n;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: scope.theme.background,
    builder: (sheet) => scope.wrap(
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SourceTile(
                icon: Icons.photo_library_outlined,
                label: l10n.t('photos'),
                onTap: () {
                  Navigator.pop(sheet);
                  controller.pick(source.photos);
                },
              ),
              if (source.hasCamera)
                _SourceTile(
                  icon: Icons.photo_camera_outlined,
                  label: l10n.t('camera'),
                  onTap: () {
                    Navigator.pop(sheet);
                    controller.pick(source.camera);
                  },
                ),
              _SourceTile(
                icon: Icons.insert_drive_file_outlined,
                label: l10n.t('files'),
                onTap: () {
                  Navigator.pop(sheet);
                  controller.pick(source.files);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return ListTile(
      minTileHeight: 56,
      leading: Icon(icon, color: scope.theme.accentOn(scope.theme.background)),
      title: Text(label, style: scope.styles.body.copyWith(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

/// The files picked for the next message, each with a thumbnail or its kind, its name and size, a
/// progress ring and a remove button.
class UploadTray extends StatelessWidget {
  const UploadTray({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final chip in scope.controller.uploads)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: UploadChipView(chip: chip, key: ValueKey(chip.key)),
            ),
        ],
      ),
    );
  }
}

class UploadChipView extends StatelessWidget {
  const UploadChipView({super.key, required this.chip});
  final UploadChip chip;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final l10n = scope.l10n;
    final failed = chip.status == UploadStatus.failed;
    return Semantics(
      container: true,
      label: withoutIsolates([
        chip.name,
        l10n.size(chip.length),
        if (chip.status == UploadStatus.uploading || chip.status == UploadStatus.preparing)
          l10n.t('uploading'),
        if (failed) l10n.t('uploadFailed', {'name': chip.name}),
      ].join(', ')),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(5, 5, 0, 5),
        decoration: BoxDecoration(
          color: theme.background,
          border: Border.all(color: failed ? theme.danger : theme.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: _Thumbnail(chip: chip)),
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 76),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChatText(
                      chip.name,
                      style: scope.styles.small.copyWith(
                        color: theme.text,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(l10n.size(chip.length), style: scope.styles.caption, maxLines: 1),
                  ],
                ),
              ),
            ),
            ChatIconButton(
              icon: Icons.close,
              size: 18,
              color: theme.textMuted,
              label: l10n.t('removeFile', {'name': chip.name}),
              onPressed: () => scope.controller.removeUpload(chip),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picture, or the file's kind, with how the upload is going drawn over it: a ring while it
/// goes up — filling the way the interface reads — a tick when it is there, a warning if it failed.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.chip});
  final UploadChip chip;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final preview = chip.preview;
    final dot = chip.name.lastIndexOf('.');
    final extension = dot > 0 ? chip.name.substring(dot + 1).toUpperCase() : '';
    final busy = chip.status == UploadStatus.uploading || chip.status == UploadStatus.preparing;
    final picture = preview != null
        ? Image.memory(
            preview,
            fit: BoxFit.cover,
            cacheWidth: 132,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => ColoredBox(color: theme.surface),
          )
        : ColoredBox(
            color: theme.surface,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  iconFor(CnctAttachmentKind.forMimeType(chip.mimeType), chip.mimeType),
                  size: 20,
                  color: theme.textMuted,
                ),
                if (extension.isNotEmpty && extension.length <= 4)
                  Text(
                    extension,
                    textScaler: TextScaler.noScaling,
                    style: scope.styles.caption
                        .copyWith(fontSize: 9, fontWeight: FontWeight.w700, height: 1.1),
                  ),
              ],
            ),
          );
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: picture),
          if (busy)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ValueListenableBuilder<double>(
                  valueListenable: chip.progress,
                  builder: (context, value, _) => Transform.flip(
                    flipX: Directionality.of(context) == TextDirection.rtl,
                    child: CircularProgressIndicator(
                      // Never a ring at zero: a sliver shows that something has started.
                      value: chip.status == UploadStatus.preparing ? null : value.clamp(0.04, 1.0),
                      strokeWidth: 3,
                      color: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
          if (chip.status == UploadStatus.done || chip.status == UploadStatus.failed)
            PositionedDirectional(
              end: -3,
              top: -3,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.background,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  chip.status == UploadStatus.done ? Icons.check_circle : Icons.error,
                  size: 18,
                  color: chip.status == UploadStatus.done
                      ? theme.accentOn(theme.background)
                      : theme.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "You're offline. Reconnecting…" while the socket is down. Not an error: the transcript is still
/// true and sends still go.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: scope.theme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined, size: 16, color: scope.theme.textMuted),
            const SizedBox(width: 8),
            Flexible(child: Text(scope.l10n.t('offline'), style: scope.styles.small)),
          ],
        ),
      ),
    );
  }
}
