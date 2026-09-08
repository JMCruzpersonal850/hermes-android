import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/services/profiles_gateway_client.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/bots_pane.dart';

void main() {
  testWidgets('returning from a bot refreshes the roster without a setState Future', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var reads = 0;
    var opens = 0;
    final profiles = ProfilesGatewayClient((method, params) async {
      reads++;
      return {'result': {'bot_mode_protocol': true, 'profiles': [
        {'name': 'default', 'display_name': 'Echo', 'model': 'test', 'provider': 'test'}
      ]}};
    });
    await tester.pumpWidget(MaterialApp(
      theme: hermesTheme(Brightness.dark),
      home: Scaffold(body: BotsPane(profiles: profiles, onOpenBot: (_) async { opens++; })),
    ));
    await tester.pumpAndSettle();
    final initialReads = reads;
    await tester.tap(find.text('Echo'));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(reads, greaterThan(initialReads));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not open'), findsNothing);
  });
}
