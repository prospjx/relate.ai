import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/orbit_theme.dart';
import 'attachment_views.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.myUid,
    required this.showSender,
    required this.onOpenActions,
    required this.onToggleReaction,
    required this.onShowReactions,
    this.senderLabel,
  });

  final Message message;

  /// Overrides the name stored on [message], e.g. a contact name looked up
  /// from the conversation's participants.
  final String? senderLabel;
  final bool mine;
  final String myUid;
  final bool showSender;
  final VoidCallback onOpenActions;
  final void Function(String emoji) onToggleReaction;
  final VoidCallback onShowReactions;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);

    if (message.kind == MessageKind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Center(
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.mutedInk,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    final maxWidth =
        (MediaQuery.sizeOf(context).width * 0.78).clamp(200.0, 520.0);
    final bare = !message.deleted &&
        message.text.isEmpty &&
        (message.kind == MessageKind.sticker ||
            message.kind == MessageKind.gif ||
            message.kind == MessageKind.image);
    final bg = mine ? palette.outgoingBubble : palette.incomingBubble;
    final fg = mine ? palette.onOutgoingBubble : palette.onIncomingBubble;
    final meta = mine
        ? palette.onOutgoingBubble.withValues(alpha: 0.76)
        : palette.mutedInk;
    final footerMeta = bare ? palette.mutedInk : meta;
    final time = DateFormat.jm().format(message.sentAt);

    final footer = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.edited) ...[
          Text(
            'edited',
            style: TextStyle(color: footerMeta, fontSize: 11),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          time,
          style: TextStyle(
            color: footerMeta,
            fontSize: 11,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    Widget content;
    if (message.deleted) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, size: 15, color: meta),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              mine ? 'You deleted this message' : 'This message was deleted',
              style: TextStyle(
                color: meta,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in message.attachments)
            Padding(
              padding: EdgeInsets.only(bottom: message.text.isEmpty ? 0 : 6),
              child: AttachmentView(attachment: a, mine: mine),
            ),
          if (message.text.isNotEmpty)
            Text(
              message.text,
              style: TextStyle(color: fg, fontSize: 15, height: 1.38),
            ),
        ],
      );
    }

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine ? 18 : 4),
      bottomRight: Radius.circular(mine ? 4 : 18),
    );

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding:
          bare ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: bare
          ? null
          : BoxDecoration(
              color: bg,
              borderRadius: radius,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          const SizedBox(height: 3),
          footer,
        ],
      ),
    );

    final groups = message.reactionGroups;

    return Padding(
      padding: EdgeInsets.only(top: showSender ? 8 : 2, bottom: 2),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showSender && !mine)
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 3),
              child: Text(
                senderLabel ?? message.senderLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: palette.secondaryInk,
                ),
              ),
            ),
          Semantics(
            hint: 'Opens message actions',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: radius,
                focusColor: palette.accent.withValues(alpha: 0.18),
                onTap: onOpenActions,
                onLongPress: onOpenActions,
                onSecondaryTap: onOpenActions,
                child: bubble,
              ),
            ),
          ),
          if (groups.isNotEmpty && !message.deleted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final entry in groups.entries)
                    _ReactionChip(
                      emoji: entry.key,
                      count: entry.value.length,
                      mine: entry.value.contains(myUid),
                      onTap: () => onToggleReaction(entry.key),
                      onLongPress: onShowReactions,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.onTap,
    required this.onLongPress,
  });

  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = MessengerPalette.of(context);
    return Semantics(
      button: true,
      selected: mine,
      label: '$emoji, $count ${count == 1 ? 'reaction' : 'reactions'}'
          '${mine ? ', including yours' : ''}',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Long press to see who reacted',
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: mine
                      ? palette.accent.withValues(alpha: 0.14)
                      : palette.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: mine
                        ? palette.accent.withValues(alpha: 0.55)
                        : palette.hairline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: mine ? palette.accent : palette.secondaryInk,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
