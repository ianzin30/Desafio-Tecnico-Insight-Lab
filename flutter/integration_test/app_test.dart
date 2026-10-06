// Integration tests, run inside the real desktop app (launched once):
//   flutter test integration_test -d macos
import 'package:flutter_test/flutter_test.dart';

import 'app_e2e.dart' as app_e2e;
import 'bridge_smoke.dart' as bridge_smoke;

void main() {
  group('bridge', bridge_smoke.main);
  group('app (UI end-to-end)', app_e2e.main);
}
