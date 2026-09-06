import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/profiles_gateway_client.dart';

void main() {
  test('lists Hermes profiles and Bot Mode protocol support', () async {
    final client = ProfilesGatewayClient((method, params) async {
      expect(method, 'profiles.list');
      expect(params['include_sessions'], true);
      return {
        'result': {
          'bot_mode_protocol': true,
          'profiles': [
            {
              'name': 'developer',
              'display_name': 'Developer',
              'model': 'model-x',
              'provider': 'provider-x',
              'canonical_session': {
                'id': 'bot-chat',
                'title': 'Bot Chat',
              },
            },
          ],
        },
      };
    });

    final snapshot = await client.list();
    expect(snapshot.botModeProtocol, isTrue);
    expect(snapshot.profiles, hasLength(1));
    expect(snapshot.profiles.single.title, 'Developer');
    expect(snapshot.profiles.single.canonicalSession?.id, 'bot-chat');
  });

  test('create refreshes the authoritative profile roster', () async {
    var created = false;
    final client = ProfilesGatewayClient((method, params) async {
      if (method == 'profiles.create') {
        created = true;
        expect(params['name'], 'research');
        return {'result': {'created': true}};
      }
      if (method == 'profiles.list') {
        return {
          'result': {
            'bot_mode_protocol': true,
            'profiles': created
                ? [
                    {
                      'name': 'research',
                      'display_name': 'Research',
                    },
                  ]
                : [],
          },
        };
      }
      fail('Unexpected method $method');
    });

    final profile = await client.create(name: 'research');
    expect(profile.name, 'research');
    expect(profile.title, 'Research');
  });
}
