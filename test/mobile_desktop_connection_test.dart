import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads older desktop chats and deduplicates pinned rows across pages', () async {
    final offsets = <String?>[];
    final client = ApiClient(
      baseUrl: 'http://gateway.test:8642',
      apiKey: 'fixture-key',
      httpClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer fixture-key');
        offsets.add(request.url.queryParameters['offset']);
        final secondPage = offsets.length == 2;
        return http.Response(jsonEncode({
          'data': [
            {'id': 'pinned', 'title': 'Pinned', 'source': 'desktop'},
            if (secondPage)
              {'id': 'older', 'title': 'Older desktop chat', 'source': 'desktop'}
            else
              {'id': 'recent', 'title': 'Recent chat', 'source': 'api_server'},
          ],
          'has_more': !secondPage,
          'limit': 1,
        }), 200);
      }),
    );
    addTearDown(client.close);
    final sessions = await client.getSessions();
    expect(offsets, ['0', '1']);
    expect(sessions.map((session) => session.id), ['pinned', 'recent', 'older']);
  });

  test('dashboard authentication times out instead of leaving bots loading', () async {
    final client = DashboardClient(
      host: 'desktop.test',
      username: 'hermes',
      password: 'fixture-key',
      requestTimeout: const Duration(milliseconds: 20),
      httpClient: MockClient((_) => Completer<http.Response>().future),
    );
    addTearDown(client.close);
    await expectLater(client.mintWebSocketTicket(), throwsA(isA<TimeoutException>()));
  });

  test('dashboard credentials enable desktop projects without an override URL', () {
    final connection = SavedConnection(
      id: 'home', label: 'Home', host: 'desktop.test', port: 8642,
      apiKey: 'fixture-key', dashboardUsername: 'hermes',
      dashboardPassword: 'fixture-key',
    );
    expect(connection.hasDesktopGateway, isTrue);
    expect(connection.copyWith(clearDashboardPassword: true).hasDesktopGateway, isFalse);
  });
}
