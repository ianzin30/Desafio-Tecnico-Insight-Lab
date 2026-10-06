import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/app/messenger_state.dart';
import 'package:messenger_app/ui/login_page.dart';

import 'ui_host.dart';

final server = find.byKey(const Key('login.server'));
final username = find.byKey(const Key('login.username'));
final password = find.byKey(const Key('login.password'));
final submit = find.byKey(const Key('login.submit'));

Finder field(Finder input) =>
    find.descendant(of: input, matching: find.byType(TextField));

bool submitEnabled(WidgetTester tester) =>
    tester
        .widget<TextButton>(
          find.descendant(of: submit, matching: find.byType(TextButton)),
        )
        .onPressed !=
    null;

void main() {
  late List<(String, String, String)> submitted;
  late int dismissed;

  setUp(() {
    submitted = [];
    dismissed = 0;
  });

  Future<void> show(
    WidgetTester tester, {
    AuthState auth = const AuthState(),
    String initialUsername = '',
  }) => pumpView(
    tester,
    LoginView(
      auth: auth,
      initialServer: 'matrix.org',
      initialUsername: initialUsername,
      onSubmit: (s, u, p) => submitted.add((s, u, p)),
      onDismissMessage: () => dismissed++,
    ),
  );

  testWidgets('submits only when every field is filled', (tester) async {
    await show(tester);
    expect(find.text('Entrar na sua conta'), findsOneWidget);
    expect(find.text('https://'), findsOneWidget);
    expect(submitEnabled(tester), isFalse);

    await tester.enterText(field(username), 'ana');
    await tester.pump();
    expect(submitEnabled(tester), isFalse);
    await tester.enterText(field(password), 'segredo 123 ');
    await tester.pump();
    expect(submitEnabled(tester), isTrue);

    // Enter in any field submits; the password is not altered.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, [('matrix.org', 'ana', 'segredo 123 ')]);

    await tester.enterText(field(server), '');
    await tester.pump();
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('the https:// prefix hides when a scheme is typed', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('https://'), findsOneWidget);

    await tester.enterText(field(server), 'http://localhost:8008');
    await tester.pump();
    expect(find.text('https://'), findsNothing);
  });

  testWidgets('while logging in, fields and button are disabled', (
    tester,
  ) async {
    await show(tester, auth: const AuthState(submitting: true));

    expect(find.text('Entrando…'), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
    expect(tester.widget<TextField>(field(username)).enabled, isFalse);
  });

  testWidgets('invalid credentials: error on the password, focused', (
    tester,
  ) async {
    await show(tester);
    await show(
      tester,
      auth: const AuthState(failure: AuthFailure.invalidCredentials),
    );
    await tester.pump();

    expect(find.text('Usuário ou senha incorretos.'), findsOneWidget);
    expect(
      tester.widget<TextField>(field(password)).focusNode!.hasFocus,
      isTrue,
    );

    // Editing the field clears its error.
    await tester.enterText(field(password), 'outra');
    await tester.pump();
    expect(find.text('Usuário ou senha incorretos.'), findsNothing);
  });

  testWidgets('invalid address: error on the server field', (tester) async {
    await show(
      tester,
      auth: const AuthState(failure: AuthFailure.invalidHomeserver),
    );

    expect(
      find.text('Endereço inválido. Use um formato como matrix.org.'),
      findsOneWidget,
    );
    expect(
      find.text('Endereço do seu servidor Matrix. Ex.: matrix.org'),
      findsNothing,
    );
  });

  testWidgets('unreachable server and network share one alert with retry', (
    tester,
  ) async {
    await show(tester, auth: const AuthState(failure: AuthFailure.network));

    expect(find.text('Não foi possível conectar.'), findsOneWidget);
    await tester.enterText(field(username), 'ana');
    await tester.enterText(field(password), 'x');
    await tester.pump();
    await tester.tap(find.text('Tentar de novo'));
    expect(submitted, hasLength(1));
  });

  testWidgets('unexpected failure shows the generic alert', (tester) async {
    await show(tester, auth: const AuthState(failure: AuthFailure.unexpected));

    expect(find.text('Algo deu errado ao entrar.'), findsOneWidget);
  });

  testWidgets('expired session: info, prefilled user, focus on password', (
    tester,
  ) async {
    await show(
      tester,
      auth: const AuthState(notice: AuthNotice.sessionExpired),
      initialUsername: 'ana',
    );
    await tester.pump();

    expect(find.text('Sua sessão expirou.'), findsOneWidget);
    expect(find.byTooltip('Fechar aviso'), findsNothing);
    expect(find.text('ana'), findsOneWidget);
    expect(
      tester.widget<TextField>(field(password)).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('local-only logout notice can be closed', (tester) async {
    await show(
      tester,
      auth: const AuthState(notice: AuthNotice.loggedOutLocallyOnly),
    );

    expect(find.text('Você saiu deste computador.'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar aviso'));
    expect(dismissed, 1);
  });

  testWidgets('fits the minimum window and the dark theme', (tester) async {
    await pumpView(
      tester,
      LoginView(
        auth: const AuthState(failure: AuthFailure.network),
        initialServer: 'matrix.org',
        initialUsername: '',
        onSubmit: (_, _, _) {},
        onDismissMessage: () {},
      ),
      size: const Size(720, 480),
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });
}
