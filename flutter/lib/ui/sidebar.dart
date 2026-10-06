// Rooms sidebar (prototype `.side`).
import 'package:flutter/material.dart';

import '../app/messenger_state.dart';
import '../messenger_core.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.width,
    required this.rooms,
    required this.selectedRoomId,
    required this.userId,
    required this.connection,
    required this.onSelect,
    required this.onRetry,
    required this.onLogout,
  });

  final double width;
  final RoomsState rooms;
  final String? selectedRoomId;
  final String? userId;
  final ConnectionStatus connection;
  final ValueChanged<String> onSelect;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      label: 'Conversas',
      container: true,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: c.side,
          border: Border(right: BorderSide(color: c.line)),
        ),
        child: Column(
          children: [
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline,
                      size: 16,
                      color: c.accentInk,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Conversas',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _list(context)),
            _AccountFooter(
              userId: userId,
              syncing: connection == ConnectionStatus.connecting,
              onLogout: onLogout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final c = AppColors.of(context);
    if (rooms.loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton(height: 14, widthFactor: 0.8, radius: 4),
            SizedBox(height: 14),
            Skeleton(height: 14, widthFactor: 0.65, radius: 4),
            SizedBox(height: 14),
            Skeleton(height: 14, widthFactor: 0.75, radius: 4),
            SizedBox(height: 14),
            Skeleton(height: 14, widthFactor: 0.55, radius: 4),
          ],
        ),
      );
    }
    if (rooms.rooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: rooms.failure != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Não foi possível carregar as conversas.',
                    style: TextStyle(fontSize: 13, color: c.text2),
                  ),
                  InlineAction(label: 'Tentar de novo', onTap: onRetry),
                ],
              )
            : Text(
                'Nenhuma conversa.',
                style: TextStyle(fontSize: 13, color: c.text2),
              ),
      );
    }

    // Alphabetical, ignoring the `@`/`#`/`!` of Matrix identifiers.
    String sortKey(RoomSummary room) =>
        _name(room).toLowerCase().replaceFirst(RegExp(r'^[@#!]'), '');
    int byName(RoomSummary a, RoomSummary b) =>
        sortKey(a).compareTo(sortKey(b));
    final direct = rooms.rooms.where((room) => room.isDirect).toList()
      ..sort(byName);
    final groups = rooms.rooms.where((room) => !room.isDirect).toList()
      ..sort(byName);
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      children: [
        if (direct.isNotEmpty) ...[
          const _Section('Diretas'),
          for (final room in direct) _item(room),
        ],
        if (groups.isNotEmpty) ...[
          const _Section('Grupos'),
          for (final room in groups) _item(room),
        ],
      ],
    );
  }

  Widget _item(RoomSummary room) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: _RoomItem(
      room: room,
      name: _name(room),
      selected: room.id == selectedRoomId,
      onTap: () => onSelect(room.id),
    ),
  );

  /// Display name, falling back to the room ID when empty.
  static String _name(RoomSummary room) =>
      room.displayName.trim().isEmpty ? room.id : room.displayName;
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
    child: Text(
      label.toUpperCase(),
      style: AppText.section(AppColors.of(context)),
    ),
  );
}

class _RoomItem extends StatelessWidget {
  const _RoomItem({
    required this.room,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final RoomSummary room;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final mono = isMatrixId(name);
    return Tooltip(
      message: name,
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? c.sel : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: Key('room.${room.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            hoverColor: c.hover,
            focusColor: c.hover,
            child: SizedBox(
              height: 38,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    RoomMark(isDirect: room.isDirect, selected: selected),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: mono ? monoFont : sansFont,
                          fontSize: mono ? 12.5 : 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected ? c.selInk : c.text,
                        ),
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

class _AccountFooter extends StatelessWidget {
  const _AccountFooter({
    required this.userId,
    required this.syncing,
    required this.onLogout,
  });

  final String? userId;
  final bool syncing;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final user = userId ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: syncing
                ? Row(
                    children: [
                      Spinner(size: 12, color: c.text2),
                      const SizedBox(width: 8),
                      Text(
                        'Sincronizando…',
                        style: TextStyle(fontSize: 12.5, color: c.text2),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sua conta',
                        style: TextStyle(fontSize: 11, color: c.text2),
                      ),
                      Tooltip(
                        message: user,
                        child: Text(
                          user,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: monoFont,
                            fontSize: 12.5,
                            color: c.text,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          PopupMenuButton<void>(
            key: const Key('account.menu'),
            tooltip: 'Menu da conta',
            position: PopupMenuPosition.over,
            offset: const Offset(0, -110),
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: c.line2),
            ),
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conectado como',
                      style: TextStyle(fontSize: 12, color: c.text2),
                    ),
                    Text(
                      user,
                      style: TextStyle(
                        fontFamily: monoFont,
                        fontSize: 12.5,
                        color: c.text,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<void>(
                key: const Key('account.logout'),
                onTap: onLogout,
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 16, color: c.text),
                    const SizedBox(width: 10),
                    Text('Sair', style: TextStyle(fontSize: 14, color: c.text)),
                  ],
                ),
              ),
            ],
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.line2),
              ),
              child: Icon(Icons.more_horiz, size: 16, color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}
