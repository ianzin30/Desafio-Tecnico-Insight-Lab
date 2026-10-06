import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:messenger_app/messenger_core.dart';

/// Loads the bridge library built by `cargo build -p messenger_bridge` (run
/// from `rust/`): plain `flutter test` runs on the Dart VM, outside an app
/// bundle.
Future<void> initRustForTests() async {
  final file = Platform.isWindows
      ? 'messenger_bridge.dll'
      : Platform.isMacOS
      ? 'libmessenger_bridge.dylib'
      : 'libmessenger_bridge.so';
  final path = '../rust/target/debug/$file';
  if (!File(path).existsSync()) {
    throw StateError(
      '$path not found: run `cargo build -p messenger_bridge` in rust/ first.',
    );
  }
  await RustLib.init(externalLibrary: ExternalLibrary.open(path));
}
