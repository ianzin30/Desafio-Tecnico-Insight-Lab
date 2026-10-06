// Login screen (high-fidelity prototype "HF · Login").
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/messenger_state.dart';
import '../app/providers.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// Username typed at the last login attempt (memory only), so the login
/// after an expired session comes prefilled.
final lastUsernameProvider = NotifierProvider<LastUsername, String>(
  LastUsername.new,
);

class LastUsername extends Notifier<String> {
  @override
  String build() => '';

  void remember(String username) => state = username;
}

/// Connects [LoginView] to the application layer.
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final homeserver = ref.watch(
      messengerProvider.select((state) => state.homeserver),
    );
    return LoginView(
      auth: auth,
      initialServer: homeserverInputFromUrl(homeserver) == ''
          ? 'matrix.org'
          : homeserverInputFromUrl(homeserver),
      initialUsername: ref.read(lastUsernameProvider),
      onSubmit: (server, username, password) {
        ref.read(lastUsernameProvider.notifier).remember(username);
        ref
            .read(messengerProvider.notifier)
            .login(
              homeserver: homeserverUrlFromInput(server),
              username: username,
              password: password,
            );
      },
      onDismissMessage: () =>
          ref.read(messengerProvider.notifier).dismissAuthMessage(),
    );
  }
}

enum _Field { server, username, password }

class LoginView extends StatefulWidget {
  const LoginView({
    super.key,
    required this.auth,
    required this.initialServer,
    required this.initialUsername,
    required this.onSubmit,
    required this.onDismissMessage,
  });

  final AuthState auth;
  final String initialServer;
  final String initialUsername;
  final void Function(String server, String username, String password) onSubmit;
  final VoidCallback onDismissMessage;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  late final _server = TextEditingController(text: widget.initialServer);
  late final _username = TextEditingController(text: widget.initialUsername);
  final _password = TextEditingController();
  final _focus = {for (final field in _Field.values) field: FocusNode()};

  /// Fields edited since the last failure: their error is hidden.
  final _edited = <_Field>{};

  @override
  void initState() {
    super.initState();
    for (final controller in [_server, _username, _password]) {
      controller.addListener(() => setState(() {}));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final firstEmpty = [
        (_Field.server, _server),
        (_Field.username, _username),
        (_Field.password, _password),
      ].where((entry) => entry.$2.text.isEmpty).firstOrNull;
      _focus[firstEmpty?.$1 ?? _Field.password]!.requestFocus();
    });
  }

  @override
  void didUpdateWidget(LoginView old) {
    super.didUpdateWidget(old);
    final failure = widget.auth.failure;
    if (failure != null && failure != old.auth.failure) {
      _edited.clear();
      // After an error, the focus goes to the field at fault.
      final culprit = switch (failure) {
        AuthFailure.invalidHomeserver => _Field.server,
        AuthFailure.invalidCredentials => _Field.password,
        _ => null,
      };
      if (culprit != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _focus[culprit]!.requestFocus(),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [_server, _username, _password]) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  bool get _busy => widget.auth.submitting;

  bool get _hasScheme {
    final server = _server.text.trimLeft();
    return server.startsWith('http://') || server.startsWith('https://');
  }

  bool get _ready =>
      !_busy &&
      _server.text.trim().isNotEmpty &&
      _username.text.trim().isNotEmpty &&
      _password.text.isNotEmpty;

  void _submit() {
    if (!_ready) return;
    widget.onSubmit(_server.text, _username.text.trim(), _password.text);
  }

  void _edit(_Field field) {
    if (widget.auth.failure != null) setState(() => _edited.add(field));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final failure = widget.auth.failure;
    final serverError =
        failure == AuthFailure.invalidHomeserver &&
        !_edited.contains(_Field.server);
    final passwordError =
        failure == AuthFailure.invalidCredentials &&
        !_edited.contains(_Field.password);

    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: Column(
            children: [
              Container(
                width: 400,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: c.raised,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Brand(),
                    const SizedBox(height: 18),
                    Text(
                      'Entrar na sua conta',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Use sua conta de qualquer servidor Matrix.',
                      style: TextStyle(fontSize: 14, color: c.text2),
                    ),
                    ..._alert(),
                    const SizedBox(height: 18),
                    _InputField(
                      key: const Key('login.server'),
                      label: 'Servidor',
                      controller: _server,
                      focusNode: _focus[_Field.server]!,
                      // Hidden when the user types the scheme (e.g. a
                      // local http:// server).
                      prefix: _hasScheme ? null : 'https://',
                      mono: true,
                      enabled: !_busy,
                      error: serverError
                          ? 'Endereço inválido. Use um formato como matrix.org.'
                          : null,
                      help: 'Endereço do seu servidor Matrix. Ex.: matrix.org',
                      onChanged: () => _edit(_Field.server),
                      onSubmitted: _submit,
                    ),
                    const SizedBox(height: 18),
                    _InputField(
                      key: const Key('login.username'),
                      label: 'Usuário',
                      controller: _username,
                      focusNode: _focus[_Field.username]!,
                      hint: 'ana ou @ana:matrix.org',
                      enabled: !_busy,
                      onChanged: () => _edit(_Field.username),
                      onSubmitted: _submit,
                    ),
                    const SizedBox(height: 18),
                    _InputField(
                      key: const Key('login.password'),
                      label: 'Senha',
                      controller: _password,
                      focusNode: _focus[_Field.password]!,
                      obscure: true,
                      enabled: !_busy,
                      error: passwordError
                          ? 'Usuário ou senha incorretos.'
                          : null,
                      onChanged: () => _edit(_Field.password),
                      onSubmitted: _submit,
                    ),
                    const SizedBox(height: 18),
                    AppButton(
                      key: const Key('login.submit'),
                      label: _busy ? 'Entrando…' : 'Entrar',
                      icon: _busy ? const Spinner(size: 15) : null,
                      onPressed: _ready ? _submit : null,
                      height: 44,
                      fontSize: 15,
                      expand: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Protocolo aberto Matrix · sua conta funciona em qualquer '
                'cliente compatível',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _alert() {
    final retry = InlineAction(label: 'Tentar de novo', onTap: _submit);
    final alert = switch ((widget.auth.failure, widget.auth.notice)) {
      (AuthFailure.network, _) => AlertBox(
        kind: AlertKind.error,
        title: 'Não foi possível conectar.',
        text:
            'Verifique sua conexão com a internet ou tente novamente em '
            'instantes.',
        action: retry,
      ),
      (AuthFailure.unexpected, _) => AlertBox(
        kind: AlertKind.error,
        title: 'Algo deu errado ao entrar.',
        text: 'Tente novamente. Se continuar, reinicie o aplicativo.',
        action: retry,
      ),
      (null, AuthNotice.sessionExpired) => const AlertBox(
        kind: AlertKind.info,
        title: 'Sua sessão expirou.',
        text: 'Entre novamente para continuar.',
      ),
      (null, AuthNotice.loggedOutLocallyOnly) => AlertBox(
        kind: AlertKind.info,
        title: 'Você saiu deste computador.',
        text:
            'Não conseguimos avisar o servidor agora; isso não impede você '
            'de entrar de novo.',
        onClose: widget.onDismissMessage,
      ),
      _ => null,
    };
    return alert == null ? const [] : [const SizedBox(height: 18), alert];
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        const _AppMark(size: 32),
        const SizedBox(width: 10),
        Text(
          'Insight Lab',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: c.text,
          ),
        ),
      ],
    );
  }
}

/// The app icon at small sizes: a solid bubble on the graphite plate (same
/// geometry as `tool/icon/macos_solid.svg`, plate cropped).
class _AppMark extends StatelessWidget {
  const _AppMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 18 / 80),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C313A), Color(0xFF121418)],
        ),
      ),
      child: CustomPaint(painter: _BubblePainter()),
    ),
  );
}

class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Icon units: the plate spans 10..90, the bubble 0..100 scaled by .58
    // at 21,21.
    final unit = size.width / 80;
    canvas
      ..scale(unit)
      ..translate(11, 11)
      ..scale(.58);
    const r = Radius.circular(12);
    final bubble = Path()
      ..moveTo(30, 18)
      ..lineTo(70, 18)
      ..arcToPoint(const Offset(82, 30), radius: r)
      ..lineTo(82, 56)
      ..arcToPoint(const Offset(70, 68), radius: r)
      ..lineTo(40, 68)
      ..lineTo(27, 80)
      ..lineTo(27, 67.4)
      ..arcToPoint(const Offset(18, 56), radius: r)
      ..lineTo(18, 30)
      ..arcToPoint(const Offset(30, 18), radius: r)
      ..close();
    canvas.drawPath(bubble, Paint()..color = const Color(0xFFA9C0FA));
  }

  @override
  bool shouldRepaint(_BubblePainter oldDelegate) => false;
}

/// Labelled input of the prototype (`.fld` / `.ig`).
class _InputField extends StatefulWidget {
  const _InputField({
    super.key,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
    this.prefix,
    this.hint,
    this.help,
    this.error,
    this.mono = false,
    this.obscure = false,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;
  final String? prefix;
  final String? hint;
  final String? help;
  final String? error;
  final bool mono;
  final bool obscure;

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final focused = widget.focusNode.hasFocus;
    final error = widget.error;
    final textStyle = widget.mono
        ? TextStyle(fontFamily: monoFont, fontSize: 13.5, color: c.text)
        : TextStyle(fontSize: 14, color: c.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.text,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 42,
          decoration: BoxDecoration(
            color: widget.enabled ? c.surface : c.hover,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: error != null
                  ? c.errInk
                  : focused
                  ? c.accent
                  : c.line2,
              width: error != null ? 1.5 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: error != null ? c.errBg : c.accentSoft,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              if (widget.prefix != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: ExcludeSemantics(
                    child: Text(
                      widget.prefix!,
                      style: TextStyle(
                        fontFamily: monoFont,
                        fontSize: 13,
                        color: c.text2,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  enabled: widget.enabled,
                  obscureText: widget.obscure,
                  style: textStyle,
                  onChanged: (_) => widget.onChanged(),
                  onSubmitted: (_) => widget.onSubmitted(),
                  inputFormatters: widget.obscure
                      ? null
                      : [FilteringTextInputFormatter.deny('\n')],
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: textStyle.copyWith(color: c.text2),
                    contentPadding: EdgeInsets.only(
                      left: widget.prefix != null ? 2 : 12,
                      right: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 15, color: c.errInk),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: c.errInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (widget.help != null) ...[
          const SizedBox(height: 6),
          Text(widget.help!, style: TextStyle(fontSize: 12.5, color: c.text2)),
        ],
      ],
    );
  }
}
