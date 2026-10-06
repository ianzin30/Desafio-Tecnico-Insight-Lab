# Decisões técnicas

Curtas e com o motivo. Detalhes de comportamento estão nos READMEs de
[`rust/`](../rust/README.md) e [`flutter/`](../flutter/README.md).

## Matrix Rust SDK no core

O SDK oficial resolve protocolo, sync, criptografia ponta a ponta e
persistência. Reimplementar isso em Dart seria maior e menos seguro. O core
(`messenger_core`) encapsula o SDK e expõe uma API própria e pequena; nenhum
tipo do SDK ou do Ruma sai dele.

## Flutter Rust Bridge 2 + Native Assets

FRB gera bindings Dart tipados (structs, enums com payload, `Stream`, erros)
a partir do Rust, sem JSON nem FFI manual. O build usa o backend oficial
**Native Assets** (`hook/build.dart`): o `flutter build` compila o crate em
qualquer plataforma, sem podspec/CMake/scripts próprios. Versões fixadas
(crate, pacote Dart e codegen `2.13.0`). Um crate adaptador separado
(`messenger_bridge`) mantém o core livre de FRB.

## Um Client por core

Cada `MessengerCore` tem um único `matrix_sdk::Client`, criado uma vez e
reutilizado por login, salas, mensagens e sync. Ele só é recriado,
internamente, quando a sessão é descartada (logout, revogação), para que uma
nova conta nunca reutilize o store de outra. No app há um único motor por vez,
substituído apenas ao entrar em outro homeserver (desautenticado).

## SQLite do SDK, um store por login

O estado Matrix fica no store SQLite oficial do SDK, em `stores/<id>/` dentro
do diretório de dados. Cada login cria um store novo; stores sem sessão
restaurável são apagados. Não existe banco próprio de mensagens.

O store é **criptografado** pelo mecanismo oficial do SDK (store cipher) com
uma chave aleatória de 256 bits por store (`SqliteStoreConfig::key`, sem
derivação de passphrase, já que a chave não é escolhida por humano).

## Segredos no cofre do sistema (SEC-01)

Os segredos da sessão (access token, refresh token, chave do store) ficam no
cofre de credenciais do sistema — Keychain (macOS), Credential Manager
(Windows), Secret Service (Linux) — via crate `keyring`, **inteiramente no
Rust**: nunca atravessam a bridge, nunca vão para logs nem para erros.
`session.json` guarda só metadata não sensível (homeserver, store, IDs de
usuário e dispositivo). Senha nunca é armazenada.

- Salvar: segredo primeiro, metadata depois (atômico); falha não deixa nada
  restaurável.
- Cofre indisponível ≠ sessão inválida: nada é descartado, o erro é
  reportado e a sessão volta quando o cofre volta.
- Formato anterior (token no `session.json`) é migrado na primeira leitura;
  se o cofre falhar, o arquivo antigo continua válido e a migração é tentada
  de novo. Nunca ficam dois segredos ativos depois da migração.
- Testes usam um cofre em memória explícito (`SecretStorage.inMemory`), para
  não tocar no cofre do usuário; o E2E usa o Keychain real.

## Restauração de sessão e startup offline

A restauração não faz requisições: uma sessão salva é restaurada mesmo sem
rede, com as salas do store local, e o app fica em "reconectando". Só uma
evidência real (`M_UNKNOWN_TOKEN` do servidor, metadata/segredo inválidos)
encerra a sessão.

## Sync contínuo próprio

Loop próprio sobre `Client::sync_once` em vez do `sync_stream` do SDK, para
controlar: baseline (o primeiro sync de cada execução não emite histórico
como "novo"), filtro (sem timeline no baseline), backoff em erro (1 s → 30 s),
cancelamento imediato e revogação terminal. Eventos vão por um canal limitado
(256); quem atrasa recebe `EventsLost` em vez de perda silenciosa.

Política de rede central: 5 s por tentativa, 2 tentativas. O Event Cache do
SDK não é usado: o histórico vem de `/messages` (sempre fresco), e o sync já
entrega os eventos novos.

## DTOs tipados na fronteira

A bridge usa tipos próprios pequenos (`RoomSummary`, `Message`, `CoreEvent`,
`ApiError`…), convertidos explicitamente do core: números de 64 bits viram
`int` no Dart e erros perdem as causas internas (que podem conter detalhes do
SDK).

## Riverpod e um coordenador

Um `MessengerController` (Notifier) é dono do gateway e da única assinatura de
eventos, e mantém um estado imutável fatiado (fase, auth, salas, conversa,
conexão). Um coordenador só evita corridas entre controllers que reagiriam ao
mesmo evento. Contadores de geração descartam resultados obsoletos (troca
rápida de sala, logout no meio de uma chamada); recargas são agrupadas.

Por causa de uma limitação do FRB 2.13 (o cancelamento de um `Stream` só
conclui no próximo evento), a assinatura nunca é cancelada durante o uso: o
`dispose()` do motor fecha o stream.

## Estratégia de testes

- **Rust**: homeserver falso (`wiremock`), diretórios temporários, cofre em
  memória; reinícios simulados com duas instâncias do core.
- **Dart (VM)**: bridge e state layer sobre o **motor Rust real** e um
  homeserver falso em Dart; UI por widget tests com estados construídos.
- **App real (macOS)**: smoke da bridge e E2E pela interface, com Keychain.
- Nada depende de internet; suítes assíncronas executadas repetidamente.
