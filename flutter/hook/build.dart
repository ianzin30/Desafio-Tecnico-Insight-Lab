// Flutter build hook (Native Assets): compiles the Rust bridge crate with
// cargo and bundles the library for the target platform.
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await const FlutterRustBridgeNativeAssetsBuilder(
      cratePath: '../rust/bridge',
    ).run(input: input, output: output);
  });
}
