// Renders a view with the app theme at a desktop window size.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:messenger_app/ui/theme.dart';

Future<void> pumpView(
  WidgetTester tester,
  Widget view, {
  Size size = const Size(1280, 800),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: buildTheme(brightness), home: view),
  );
  await tester.pump();
}
