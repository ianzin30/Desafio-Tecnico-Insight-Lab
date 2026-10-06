// Root widget: theme and one screen per application phase.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/messenger_state.dart';
import '../app/providers.dart';
import 'chat_page.dart';
import 'login_page.dart';
import 'theme.dart';
import 'widgets.dart';

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Matrix Desktop',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: ThemeMode.system,
    home: const PhaseRouter(),
  );
}

/// Shows the screen of the current [AppPhase].
class PhaseRouter extends ConsumerStatefulWidget {
  const PhaseRouter({super.key});

  @override
  ConsumerState<PhaseRouter> createState() => _PhaseRouterState();
}

class _PhaseRouterState extends ConsumerState<PhaseRouter> {
  /// The session ended while in use: the modal comes before the login.
  bool _expired = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(messengerProvider, (previous, next) {
      if (previous?.phase == AppPhase.authenticated &&
          next.phase == AppPhase.unauthenticated &&
          next.auth.notice == AuthNotice.sessionExpired) {
        setState(() => _expired = true);
      }
    });
    final phase = ref.watch(appPhaseProvider);
    return switch (phase) {
      AppPhase.initializing => const StartupView(),
      AppPhase.fatalError => FatalView(
        onRetry: ref.read(messengerProvider.notifier).retryStartup,
      ),
      AppPhase.unauthenticated when _expired => ExpiredView(
        onContinue: () => setState(() => _expired = false),
      ),
      AppPhase.unauthenticated => const LoginPage(),
      AppPhase.authenticated => const ChatPage(),
    };
  }
}

/// Opening the app: nothing until 300 ms, then "Abrindo…".
class StartupView extends StatelessWidget {
  const StartupView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: DelayedVisibility(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Spinner(color: c.text2),
              const SizedBox(height: 10),
              Text('Abrindo…', style: TextStyle(fontSize: 13, color: c.text2)),
            ],
          ),
        ),
      ),
    );
  }
}

class FatalView extends StatelessWidget {
  const FatalView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).bg,
    body: NeutralState(
      icon: Icons.error_outline,
      error: true,
      title: 'Não foi possível iniciar o aplicativo',
      text:
          'Verifique o espaço em disco e as permissões da pasta do '
          'aplicativo e tente de novo.',
      action: AppButton(
        label: 'Tentar de novo',
        primary: false,
        icon: const Icon(Icons.refresh, size: 15),
        onPressed: onRetry,
      ),
    ),
  );
}

/// "Sua sessão expirou": single action, no dismissal.
class ExpiredView extends StatelessWidget {
  const ExpiredView({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).bg,
    body: ModalScrim(
      child: AppDialog(
        icon: Icons.schedule,
        title: 'Sua sessão expirou',
        text:
            'Por segurança, entre novamente para continuar usando suas '
            'conversas.',
        actions: [
          AppButton(
            key: const Key('expired.continue'),
            label: 'Entrar novamente',
            onPressed: onContinue,
          ),
        ],
      ),
    ),
  );
}
