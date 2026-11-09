import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bidi.dart';
import 'parts.dart';
import 'scope.dart';

/// A picture, full screen: pinch to zoom, drag down or press Escape to close, and a close button
/// for anybody who does neither.
Future<void> showImageViewer(
  BuildContext context, {
  required Uint8List bytes,
  required CnctChatAttachment attachment,
}) {
  final scope = ChatScope.of(context);
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, __, ___) => scope.wrap(ImageViewer(bytes: bytes, attachment: attachment)),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

class ImageViewer extends StatefulWidget {
  const ImageViewer({super.key, required this.bytes, required this.attachment});

  final Uint8List bytes;
  final CnctChatAttachment attachment;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  final _zoom = TransformationController();
  double _drag = 0;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  bool get _zoomedIn => _zoom.value.getMaxScaleOnAxis() > 1.01;

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final l10n = scope.l10n;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Colors.black,
          child: Stack(
            children: [
              // A listener rather than a gesture, so dragging down to close does not fight the
              // viewer for the pan. Only when not zoomed in: then a drag is for looking around.
              Listener(
                onPointerMove: (event) {
                  if (_zoomedIn) return;
                  setState(() => _drag = (_drag + event.delta.dy).clamp(0, 400));
                },
                onPointerUp: (_) {
                  if (_drag > 120) {
                    Navigator.maybePop(context);
                  } else {
                    setState(() => _drag = 0);
                  }
                },
                child: Transform.translate(
                  offset: Offset(0, _drag),
                  child: Opacity(
                    opacity: (1 - _drag / 400).clamp(0.3, 1),
                    child: InteractiveViewer(
                      transformationController: _zoom,
                      minScale: 1,
                      maxScale: 5,
                      child: Center(
                        child: Image.memory(
                          widget.bytes,
                          fit: BoxFit.contain,
                          semanticLabel: withoutIsolates([
                            l10n.t('quoteIMAGE'),
                            if (widget.attachment.bytes != null) l10n.size(widget.attachment.bytes),
                          ].join(', ')),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChatIconButton(
                      icon: Icons.close,
                      label: l10n.t('back'),
                      color: Colors.white,
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
