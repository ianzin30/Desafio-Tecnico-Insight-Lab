// Chat screen (high-fidelity prototype "HF · Chat").
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/messenger_state.dart';
import '../app/providers.dart';
import 'composer.dart';
import 'sidebar.dart';
import 'theme.dart';
import 'timeline.dart';
import 'widgets.dart';

/// Window width under which the compact layout is used.
const compactWidth = 960.0;

/// Connects [ChatView] to the application layer.
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  /// Name of the open room that disappeared (left, kicked, ...).
  String? _removedRoomName;

  @override
  Widget build(BuildContext context) {
    ref.listen(messengerProvider, (previous, next) {
      final closed = previous?.conversation;
      if (closed != null &&
          next.conversation == null &&
          next.phase == AppPhase.authenticated &&
          !next.rooms.contains(closed.roomId)) {
        final room = previous!.rooms.rooms
            .where((room) => room.id == closed.roomId)
            .firstOrNull;
        setState(() => _removedRoomName = room?.displayName ?? closed.roomId);
      }
    });
    final app = ref.read(messengerProvider.notifier);
    return ChatView(
      userId: ref.watch(authStateProvider.select((auth) => auth.userId)),
      loggingOut: ref.watch(authStateProvider.select((a) => a.submitting)),
      rooms: ref.watch(roomsStateProvider),
      conversation: ref.watch(conversationStateProvider),
      connection: ref.watch(connectionStatusProvider),
      removedRoomName: _removedRoomName,
      onDismissRemoved: () => setState(() => _removedRoomName = null),
      onSelectRoom: (roomId) {
        setState(() => _removedRoomName = null);
        app.selectRoom(roomId);
      },
      onRetryRooms: app.refreshRooms,
      onRetryConversation: app.reloadConversation,
      onSend: app.sendMessage,
      onLogout: app.logout,
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.userId,
    required this.rooms,
    required this.conversation,
    required this.connection,
    required this.onSelectRoom,
    required this.onRetryRooms,
    required this.onRetryConversation,
    required this.onSend,
    required this.onLogout,
    this.loggingOut = false,
    this.removedRoomName,
    this.onDismissRemoved,
    this.bannerDelay = const Duration(seconds: 2),
    this.now,
  });

  final String? userId;
  final RoomsState rooms;
  final ConversationState? conversation;
  final ConnectionStatus connection;
  final ValueChanged<String> onSelectRoom;
  final VoidCallback onRetryRooms;
  final VoidCallback onRetryConversation;
  final Future<bool> Function(String body) onSend;
  final VoidCallback onLogout;
  final bool loggingOut;
  final String? removedRoomName;
  final VoidCallback? onDismissRemoved;

  /// How long a connection change lasts before the banner reacts.
  final Duration bannerDelay;
  final DateTime Function()? now;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  /// Unsent text per room, kept while the app is open.
  final _drafts = <String, String>{};
  bool _confirmLogout = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Column(
            children: [
              ConnectionBanner(
                status: widget.connection,
                delay: widget.bannerDelay,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < compactWidth;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Sidebar(
                          width: compact ? 224 : 272,
                          rooms: widget.rooms,
                          selectedRoomId: widget.conversation?.roomId,
                          userId: widget.userId,
                          connection: widget.connection,
                          onSelect: widget.onSelectRoom,
                          onRetry: widget.onRetryRooms,
                          onLogout: () => setState(() => _confirmLogout = true),
                        ),
                        Expanded(child: _main(compact)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          if (_confirmLogout)
            Positioned.fill(
              child: _LogoutDialog(
                loggingOut: widget.loggingOut,
                onCancel: () => setState(() => _confirmLogout = false),
                onConfirm: () {
                  setState(() => _confirmLogout = false);
                  widget.onLogout();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _main(bool compact) {
    final c = AppColors.of(context);
    final conversation = widget.conversation;
    if (conversation == null) {
      final noRooms = !widget.rooms.loading && widget.rooms.rooms.isEmpty;
      return Semantics(
        label: 'Conversa',
        container: true,
        child: Column(
          children: [
            if (widget.removedRoomName != null)
              _RemovedNotice(
                roomName: widget.removedRoomName!,
                onDismiss: widget.onDismissRemoved,
              ),
            Expanded(
              child: NeutralState(
                icon: Icons.chat_bubble_outline,
                title: noRooms
                    ? 'Você ainda não participa de nenhuma conversa'
                    : 'Nenhuma conversa aberta',
                text: noRooms
                    ? 'As conversas em que você entrar aparecerão aqui '
                          'automaticamente.'
                    : 'Selecione uma conversa na lista ao lado.',
              ),
            ),
          ],
        ),
      );
    }

    final room = widget.rooms.rooms
        .where((room) => room.id == conversation.roomId)
        .firstOrNull;
    final roomName = room == null || room.displayName.trim().isEmpty
        ? conversation.roomId
        : room.displayName;
    final loadFailed =
        conversation.failure != null && conversation.messages.isEmpty;
    return Semantics(
      label: 'Conversa',
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoomHeader(
            name: roomName,
            isDirect: room?.isDirect ?? false,
            compact: compact,
          ),
          if (conversation.reconciling && conversation.messages.isNotEmpty)
            DelayedVisibility(
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Spinner(color: c.text2),
                    const SizedBox(width: 8),
                    Text(
                      'Atualizando conversa…',
                      style: TextStyle(fontSize: 12.5, color: c.text2),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: TimelineView(
              conversation: conversation,
              roomName: roomName,
              compact: compact,
              onRetry: widget.onRetryConversation,
              now: widget.now,
            ),
          ),
          Composer(
            key: ValueKey(conversation.roomId),
            roomName: roomName,
            draft: _drafts[conversation.roomId] ?? '',
            onDraftChanged: (text) => _drafts[conversation.roomId] = text,
            onSend: widget.onSend,
            offline: widget.connection == ConnectionStatus.reconnecting,
            unavailable: loadFailed || conversation.loading,
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.name,
    required this.isDirect,
    required this.compact,
  });

  final String name;
  final bool isDirect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          RoomMark(isDirect: isDirect, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: name,
                  child: Text(
                    name,
                    key: const Key('room.header'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ),
                Text(
                  isDirect ? 'Conversa direta' : 'Grupo',
                  style: TextStyle(fontSize: 12.5, color: c.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemovedNotice extends StatelessWidget {
  const _RemovedNotice({required this.roomName, this.onDismiss});

  final String roomName;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540),
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.line2),
          boxShadow: c.raised,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Você não está mais em “$roomName”.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const TextSpan(text: ' A conversa foi fechada.'),
                  ],
                ),
                style: TextStyle(fontSize: 13.5, height: 1.45, color: c.text),
              ),
            ),
            const SizedBox(width: 12),
            AppButton(label: 'OK', primary: false, onPressed: onDismiss),
          ],
        ),
      ),
    );
  }
}

class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog({
    required this.loggingOut,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool loggingOut;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onCancel},
      child: Focus(
        autofocus: true,
        child: ModalScrim(
          child: AppDialog(
            title: 'Sair da conta?',
            text:
                'Você precisará entrar novamente com usuário e senha neste '
                'computador.',
            actions: [
              AppButton(label: 'Cancelar', primary: false, onPressed: onCancel),
              AppButton(
                key: const Key('logout.confirm'),
                label: 'Sair',
                onPressed: loggingOut ? null : onConfirm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dimmed backdrop centering a modal dialog; fills its parent.
class ModalScrim extends StatelessWidget {
  const ModalScrim({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.of(context).scrim,
    child: Center(
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );
}

/// Dialog card of the prototype (`.dlg`).
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.text,
    required this.actions,
    this.icon,
  });

  final String title;
  final String text;
  final List<Widget> actions;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: c.raised,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: c.accent),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              text,
              style: TextStyle(fontSize: 14, height: 1.5, color: c.text2),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final (index, action) in actions.indexed) ...[
                  if (index > 0) const SizedBox(width: 8),
                  action,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Top banner for connection problems (prototype `.banner`): shown when the
/// connection is lost for [delay], then "Conectado" for [delay] once back.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({
    super.key,
    required this.status,
    this.delay = const Duration(seconds: 2),
  });

  final ConnectionStatus status;
  final Duration delay;

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

enum _Banner { none, offline, back }

class _ConnectionBannerState extends State<ConnectionBanner> {
  _Banner _banner = _Banner.none;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _react(null);
  }

  @override
  void didUpdateWidget(ConnectionBanner old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _react(old.status);
  }

  void _react(ConnectionStatus? previous) {
    _timer?.cancel();
    if (widget.status == ConnectionStatus.reconnecting) {
      _timer = Timer(widget.delay, () => _show(_Banner.offline));
    } else if (_banner == _Banner.offline &&
        widget.status == ConnectionStatus.online) {
      _show(_Banner.back);
      _timer = Timer(widget.delay, () => _show(_Banner.none));
    } else {
      _show(_Banner.none);
    }
  }

  void _show(_Banner banner) {
    if (mounted && banner != _banner) setState(() => _banner = banner);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (_banner == _Banner.none) return const SizedBox.shrink();
    final offline = _banner == _Banner.offline;
    final foreground = offline ? c.warnInk : c.infoInk;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: Key(offline ? 'banner.offline' : 'banner.back'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: offline ? c.warnBg : c.infoBg,
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: sansFont,
            fontSize: 13,
            color: foreground,
          ),
          child: Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: offline
                ? [
                    Spinner(color: foreground),
                    const Text(
                      'Sem conexão.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Text('Tentando reconectar…'),
                    Opacity(
                      opacity: 0.85,
                      child: const Text(
                        'Você ainda pode ler as conversas abertas.',
                      ),
                    ),
                  ]
                : [
                    Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: foreground,
                    ),
                    const Text(
                      'Conectado',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}
