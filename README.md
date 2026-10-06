# Desafio-Tecnico-Insight-Lab

Cliente desktop de mensageria (Flutter + Rust + Matrix Rust SDK), alvo macOS,
Windows e Linux.

## Estrutura

```text
rust/                    workspace Cargo
├── src/                 messenger_core — engine Matrix (login, sessão, salas, mensagens, sync)
└── bridge/              messenger_bridge — adaptador Flutter Rust Bridge (FFI), sem regra de negócio
flutter/                 app Flutter desktop (messenger_app)
├── lib/messenger_core.dart   API Dart da engine (exporta os bindings gerados)
├── lib/src/rust/        bindings GERADOS — não editar
├── hook/build.dart      build hook (Native Assets) que compila rust/bridge
├── test/                testes da bridge na VM Dart
└── integration_test/    testes dentro do app desktop real
```

Arquivos gerados (`flutter_rust_bridge_codegen generate`, nunca editados à mão):
`flutter/lib/src/rust/**` e `rust/bridge/src/frb_generated.rs`.

## Pré-requisitos

- Rust via [rustup](https://rustup.rs). O crate `rust/bridge` fixa o toolchain
  `1.99.0` em `rust-toolchain.toml` (instalado automaticamente pelo rustup).
- Flutter stable ≥ 3.47 (Dart ≥ 3.13) com suporte desktop, e o toolchain
  nativo da plataforma (Xcode no macOS; Visual Studio no Windows; clang/CMake/GTK no Linux).
- Codegen do Flutter Rust Bridge, **mesma versão** do crate e do pacote Dart:

  ```bash
  cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
  ```

## Rodar

```bash
cd flutter
flutter pub get
flutter run -d macos   # ou windows / linux
```

O build hook compila `rust/bridge` (release) e empacota a biblioteca no app —
sem passos manuais. O primeiro build compila o Matrix SDK e leva alguns minutos.

## Verificar

```bash
cd rust
cargo check --workspace
cargo test --workspace
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
```

```bash
cd rust && cargo build -p messenger_bridge   # biblioteca usada por `flutter test`
cd ../flutter
flutter analyze
flutter test                                   # bridge na VM Dart (homeserver falso local)
flutter test integration_test -d macos         # dentro do app desktop real
```

Detalhes: [`rust/README.md`](rust/README.md) (engine) e
[`flutter/README.md`](flutter/README.md) (bridge e API Dart).
