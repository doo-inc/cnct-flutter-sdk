import 'package:cnct_flutter_sdk/cnct_flutter_sdk.dart';
import 'package:flutter/material.dart';

import '../bidi.dart';
import '../controller.dart';
import 'parts.dart';
import 'scope.dart';

/// The bar at the top: the logo, the title, who the visitor is talking to or when the team is
/// back, "End chat" where the business allows it, and close where the app gave somewhere to go.
class ChatHeader extends StatelessWidget {
  const ChatHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = ChatScope.of(context);
    final theme = scope.theme;
    final controller = scope.controller;
    final l10n = scope.l10n;
    final line = controller.phase == ChatPhase.chat ? _line(scope) : null;

    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
          child: Row(
            children: [
              const BrandMark(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChatText(
                        theme.title,
                        style: scope.styles.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (line != null) ...[
                        const SizedBox(height: 2),
                        Text(line, style: scope.styles.small, maxLines: 2),
                      ],
                    ],
                  ),
                ),
              ),
              if (controller.canEnd && !controller.confirmingEnd)
                QuietButton(
                  label: l10n.t('endChat'),
                  onPressed: controller.askToEnd,
                  color: theme.accentOn(theme.surface),
                ),
              if (scope.onClose != null)
                ChatIconButton(
                  icon: Icons.close,
                  label: l10n.t('closeChat'),
                  onPressed: scope.onClose,
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Who the visitor is talking to, as specifically as can honestly be said — the hosted widget's
  /// rules, in its order.
  String _line(ChatScope scope) {
    final controller = scope.controller;
    final l10n = scope.l10n;
    final conversation = controller.conversation;
    if (conversation != null && !controller.isLive) {
      return l10n.endedWhen(conversation.closedAt ?? conversation.startedAt);
    }
    if (conversation?.withPerson ?? false) return l10n.t('withPerson');
    if (_assistantLeads(controller.messages)) {
      return '${l10n.t('aiAssistant')} · ${l10n.t('teamCanHelp')}';
    }
    return l10n.availability(controller.inbox?.availability);
  }

  /// The assistant spoke last of the business's voices, and no person has taken over since.
  static bool _assistantLeads(List<CnctChatMessage> messages) {
    for (final message in messages.reversed) {
      if (message.sender?.isAssistant ?? false) return true;
      if (message.speaker == CnctSpeaker.operator) return false;
    }
    return false;
  }
}
