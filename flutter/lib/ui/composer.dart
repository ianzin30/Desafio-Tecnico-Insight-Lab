// Message composer (prototype `.cmp`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'widgets.dart';

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.roomName,
    required this.draft,
    required this.onDraftChanged,
    required this.onSend,
    required this.offline,
    required this.unavailable,
    required this.compact,
  });

  final String roomName;

  /// Text kept for this room while the app is open.
  final String draft;
  final ValueChanged<String> onDraftChanged;

  /// Sends the text; completes with whether the homeserver accepted it.
  final Future<bool> Function(String body) onSend;

  /// No connection: sending is disabled until it comes back.
  final bool offline;

  /// The conversation could not be loaded: nothing to send to yet.
  final bool unavailable;
  final bool compact;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  late final _text = TextEditingController(text: widget.draft);
  late final _focus = FocusNode(onKeyEvent: _onKey);
  bool _sending = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      widget.onDraftChanged(_text.text);
      setState(() {});
    });
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _text.text.trim().isNotEmpty &&
      !_sending &&
      !widget.offline &&
      !widget.unavailable;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      node.unfocus();
      return KeyEventResult.handled;
    }
    final enter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (enter && !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _failed = false;
    });
    final sent = await widget.onSend(_text.text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _failed = !sent;
    });
    if (sent) {
      _text.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final placeholder = widget.unavailable
        ? 'Disponível após carregar a conversa'
        : 'Mensagem para ${widget.roomName}';
    final hint = widget.offline
        ? 'Você poderá enviar quando a conexão voltar.'
        : widget.unavailable
        ? 'Disponível depois que a conversa carregar.'
        : 'Enter para enviar  ·  Shift + Enter para nova linha';
    final textStyle = TextStyle(fontSize: 14, height: 1.45, color: c.text);
    return Container(
      color: c.bg,
      padding: widget.compact
          ? const EdgeInsets.fromLTRB(14, 10, 14, 12)
          : const EdgeInsets.fromLTRB(24, 12, 24, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 940),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_failed) ...[
                AlertBox(
                  kind: AlertKind.error,
                  title: 'Não foi possível enviar.',
                  text: 'Sua mensagem continua no campo abaixo.',
                  action: InlineAction(label: 'Tentar de novo', onTap: _send),
                  onClose: () => setState(() => _failed = false),
                ),
                const SizedBox(height: 8),
              ],
              Opacity(
                opacity: widget.unavailable ? 0.7 : 1,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _focus.hasFocus ? c.accent : c.line2,
                    ),
                    boxShadow: _focus.hasFocus
                        ? [BoxShadow(color: c.accentSoft, spreadRadius: 3)]
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('composer.input'),
                          controller: _text,
                          focusNode: _focus,
                          enabled: !widget.unavailable,
                          readOnly: _sending,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          style: textStyle,
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: placeholder,
                            hintStyle: textStyle.copyWith(color: c.text2),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        key: const Key('composer.send'),
                        label: _sending ? 'Enviando' : 'Enviar',
                        icon: _sending
                            ? const Spinner(size: 14)
                            : const Icon(Icons.send_outlined, size: 15),
                        onPressed: _canSend ? _send : null,
                        height: 36,
                        fontSize: 13.5,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                  hint,
                  style: TextStyle(fontSize: 11.5, color: c.text2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
