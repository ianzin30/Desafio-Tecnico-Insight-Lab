// Conversation timeline (prototype `.tl`): states, grouping and scrolling.
import 'package:flutter/material.dart';

import '../app/messenger_controller.dart';
import '../app/messenger_state.dart';
import '../messenger_core.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// Distance from the end under which the user counts as "at the bottom".
const atBottomThreshold = 80.0;

class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.conversation,
    required this.roomName,
    required this.compact,
    required this.onRetry,
    this.now,
  });

  final ConversationState conversation;
  final String roomName;
  final bool compact;
  final VoidCallback onRetry;

  /// Clock for day labels (tests).
  final DateTime Function()? now;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  final _scroll = ScrollController();
  bool _atBottom = true;

  /// New messages from others received while reading above.
  int _unseen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _toEnd();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final atBottom =
        position.maxScrollExtent - position.pixels <= atBottomThreshold;
    if (atBottom != _atBottom || (atBottom && _unseen > 0)) {
      setState(() {
        _atBottom = atBottom;
        if (atBottom) _unseen = 0;
      });
    }
  }

  /// Scrolls to the newest message once the frame is laid out.
  void _toEnd({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    final before = old.conversation;
    final now = widget.conversation;
    if (before.roomId != now.roomId) {
      _unseen = 0;
      _toEnd();
      return;
    }
    // First load, or a reconciliation that replaced the timeline.
    if ((before.loading && !now.loading) ||
        (before.reconciling && !now.reconciling && _atBottom)) {
      _toEnd();
      return;
    }
    if (identical(before.messages, now.messages)) return;
    final known = {for (final message in before.messages) message.id};
    final added = now.messages.where((m) => !known.contains(m.id)).toList();
    if (added.isEmpty) return;
    if (added.any((message) => message.isOwn)) {
      _toEnd(animate: true);
    } else if (_atBottom) {
      _toEnd(animate: true);
    } else {
      setState(() => _unseen += added.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    if (conversation.loading) return const _LoadingTimeline();
    if (conversation.failure != null && conversation.messages.isEmpty) {
      return NeutralState(
        icon: Icons.error_outline,
        error: true,
        title: 'Não foi possível carregar as mensagens',
        text: 'Verifique sua conexão e tente de novo.',
        action: AppButton(
          label: 'Tentar de novo',
          primary: false,
          icon: const Icon(Icons.refresh, size: 15),
          onPressed: widget.onRetry,
        ),
      );
    }
    if (conversation.messages.isEmpty) {
      return NeutralState(
        icon: Icons.chat_outlined,
        title: 'Nenhuma mensagem ainda',
        text: 'Envie a primeira mensagem para ${widget.roomName}.',
      );
    }

    final now = (widget.now ?? DateTime.now)();
    final items = buildTimeline(conversation.messages, now);
    final padding = widget.compact
        ? const EdgeInsets.fromLTRB(16, 16, 16, 10)
        : const EdgeInsets.fromLTRB(28, 20, 28, 12);
    return Stack(
      children: [
        Semantics(
          label: 'Mensagens de ${widget.roomName}',
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              controller: _scroll,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                // Bottom-aligned: a short timeline sits above the composer.
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 940),
                    child: Padding(
                      padding: padding,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (conversation.messages.length >=
                              MessengerController.messagesLimit)
                            const _OlderHint(),
                          for (final item in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: switch (item) {
                                DaySeparator(:final label) => _DayRow(label),
                                MessageGroup() => _GroupView(
                                  group: item,
                                  compact: widget.compact,
                                  now: now,
                                ),
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_unseen > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: _NewMessagesPill(
                count: _unseen,
                onPressed: () => _toEnd(animate: true),
              ),
            ),
          ),
      ],
    );
  }
}

class _LoadingTimeline extends StatelessWidget {
  const _LoadingTimeline();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      label: 'Carregando mensagens',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Skeleton(height: 14, width: 160, radius: 6),
            const SizedBox(height: 12),
            const Skeleton(height: 40, widthFactor: 0.52),
            const SizedBox(height: 12),
            const Skeleton(height: 40, widthFactor: 0.38),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerRight,
              child: Skeleton(height: 40, widthFactor: 0.44),
            ),
            const SizedBox(height: 12),
            const Skeleton(height: 14, width: 180, radius: 6),
            const SizedBox(height: 12),
            const Skeleton(height: 58, widthFactor: 0.6),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Spinner(color: c.text2),
                const SizedBox(width: 8),
                Text(
                  'Carregando mensagens…',
                  style: TextStyle(fontSize: 13, color: c.text2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OlderHint extends StatelessWidget {
  const _OlderHint();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      'Mostrando as mensagens mais recentes',
      textAlign: TextAlign.center,
      style: AppText.meta(AppColors.of(context)),
    ),
  );
}

class _DayRow extends StatelessWidget {
  const _DayRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final line = Expanded(child: Container(height: 1, color: c.line));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          line,
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.text2,
            ),
          ),
          const SizedBox(width: 12),
          line,
        ],
      ),
    );
  }
}

class _GroupView extends StatelessWidget {
  const _GroupView({
    required this.group,
    required this.compact,
    required this.now,
  });

  final MessageGroup group;
  final bool compact;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final own = group.isOwn;
    final first = messageTime(group.messages.first);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth * (compact ? 0.86 : 0.68);
        return Align(
          alignment: own ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: own
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: own
                            ? Text(
                                'Você',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: c.text,
                                ),
                              )
                            : Tooltip(
                                message: group.sender,
                                child: Text(
                                  group.sender,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.mono(c),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Text(timeLabel(first), style: AppText.meta(c)),
                    ],
                  ),
                ),
                for (final message in group.messages)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: _Bubble(message: message, now: now),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({required this.message, required this.now});

  final Message message;
  final DateTime now;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final message = widget.message;
    final own = message.isOwn;
    final time = messageTime(message);
    final bubble = Flexible(
      child: Tooltip(
        message: '${dayLabel(time, widget.now)}, ${timeLabel(time)}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: own ? c.own : c.other,
            border: Border.all(color: own ? c.ownLine : c.line),
            borderRadius: own
                ? const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(6),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  )
                : const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
          ),
          child: SelectableText(message.body, style: AppText.body(c)),
        ),
      ),
    );
    final hoverTime = AnimatedOpacity(
      opacity: _hover ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: Text(
        timeLabel(time),
        style: TextStyle(fontSize: 11, color: c.text2),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: own
            ? [hoverTime, const SizedBox(width: 8), bubble]
            : [bubble, const SizedBox(width: 8), hoverTime],
      ),
    );
  }
}

class _NewMessagesPill extends StatelessWidget {
  const _NewMessagesPill({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: c.raised,
        ),
        child: TextButton.icon(
          key: const Key('timeline.newMessages'),
          onPressed: onPressed,
          icon: Icon(Icons.arrow_downward, size: 15, color: c.accentInk),
          label: Text(
            count == 1 ? '1 nova mensagem' : '$count novas mensagens',
          ),
          style: TextButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: c.accentInk,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontFamily: sansFont,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
