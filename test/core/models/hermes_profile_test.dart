import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/hermes_profile.dart';

void main() {
  test('parses canonical Bot Chat and adapts it to Session', () {
    final profile = HermesProfile.fromJson({
      'name': 'marketing',
      'display_name': 'Marketing',
      'description': 'Campaigns and copy',
      'model': 'gpt-test',
      'provider': 'test',
      'skill_count': 4,
      'canonical_session': {
        'id': 'root-id',
        'resolved_id': 'tip-id',
        'title': 'Bot Chat',
        'root_title': 'Bot Chat',
        'preview': 'Ready to work',
        'started_at': 100,
        'last_active': 200,
        'message_count': 12,
      },
    });

    expect(profile.title, 'Marketing');
    expect(profile.skillCount, 4);
    expect(profile.canonicalSession?.openId, 'tip-id');

    final session = profile.canonicalSession!.toSession(profile);
    expect(session.id, 'tip-id');
    expect(session.title, 'Marketing');
    expect(session.source, 'bot:marketing');
    expect(session.messageCount, 12);
  });
}
