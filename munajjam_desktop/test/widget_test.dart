import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:munajjam_desktop/core/server_manager.dart';
import 'package:munajjam_desktop/views/widgets/custom_title_bar.dart';

void main() {
  testWidgets(
    'desktop title bar shows connection status without claiming a GPU',
    (tester) async {
      ServerManager().isOnlineNotifier.value = false;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CustomTitleBar(localeCode: 'en')),
        ),
      );
      await tester.pump();
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('RTX DirectML'), findsNothing);
      if (Platform.isMacOS) {
        // macOS uses native window buttons above the Flutter content.
        expect(find.byIcon(Icons.close_rounded), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
