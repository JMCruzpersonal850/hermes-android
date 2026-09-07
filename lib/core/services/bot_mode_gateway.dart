import '../models/hermes_profile.dart';
import 'connection_manager.dart';
import 'desktop_gateway_client.dart';
import 'profiles_gateway_client.dart';
import 'ws_client.dart';

/// One profile-scoped Hermes Bot Mode connection.
///
/// Bot chats must carry `profile` on create/resume. The regular mobile chat
/// client is intentionally profile-agnostic, so this small transport keeps Bot
/// Mode isolated instead of risking cross-profile resumes.
class BotModeGateway {
  static const canonicalChatTitle = 'Bot Chat';

  final SavedConnection connection;
  WsClient? _ws;
  DashboardClient? _dashboard;
  late final ProfilesGatewayClient profiles = ProfilesGatewayClient(_rpc);

  BotModeGateway(this.connection);

  Future<WsClient> _connect() async {
    final existing = _ws;
    if (existing != null && existing.isConnected) return existing;

    final baseUrl = DesktopGatewayClient.normalizedGatewayBaseUrl(connection);
    final uri = Uri.parse(baseUrl);
    final pathPrefix = uri.path == '/' ? '' : uri.path;
    final dashboard = DashboardClient(
      host: uri.host,
      port: uri.port,
      useHttps: uri.scheme == 'https',
      pathPrefix: pathPrefix,
      proxied: connection.dashboardProxied,
        username: connection.dashboardUsername,
      password: connection.dashboardPassword,
    );
    _dashboard?.close();
    _dashboard = dashboard;

    final ticket = await dashboard.mintWebSocketTicket();
    final client = WsClient(baseUrl, ticket: ticket);
    await client.connect();
    await client.waitForGatewayReady();
    _ws?.close();
    _ws = client;
    return client;
  }

  Future<Map<String, dynamic>> _rpc(
    String method,
    Map<String, dynamic> params,
  ) async {
    final client = await _connect();
    return client.send(method, params);
  }

  Future<Map<String, dynamic>> _result(
    String method,
    Map<String, dynamic> params,
  ) async {
    final response = await _rpc(method, params);
    final error = response['error'];
    if (error != null) {
      if (error is Map) {
        throw JsonRpcError.fromGateway(
          method,
          error,
          fallbackMessage: 'Hermes Bot Mode request failed',
        );
      }
      throw JsonRpcError(method, 'Hermes Bot Mode request failed');
    }
    final result = response['result'];
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  /// Opens the profile's one canonical forever-chat.
  ///
  /// The exact-title lookup is authoritative and window-free. A transient
  /// lookup failure is allowed to fail the open instead of being interpreted
  /// as "no chat" because blindly creating there can fork a bot's history.
  Future<BotChatOpenResult> openCanonicalChat(HermesProfile profile) async {
    final name = profile.name.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(profile.name, 'profile.name', 'Bot name required');
    }

    final lookup = await _result('session.list', {
      'profile': name,
      'title': canonicalChatTitle,
      'include_hidden': true,
      'limit': 200,
    });
    final rows = lookup['sessions'];
    Map<String, dynamic>? canonical;
    if (rows is List) {
      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final title = (row['root_title'] ?? row['title'] ?? '').toString();
        if (title == canonicalChatTitle) {
          canonical = row;
          break;
        }
      }
    }

    if (canonical == null && profile.canonicalSession?.id.isNotEmpty == true) {
      throw StateError(
        'Hermes reported an existing Bot Chat but could not confirm it. Try again instead of creating a duplicate.',
      );
    }

    if (canonical != null) {
      final storedId = (canonical['id'] ?? '').toString();
      final openId = (canonical['resolved_id'] ?? storedId).toString();
      final result = await _result('session.resume', {
        'session_id': openId,
        'profile': name,
        'omit_messages': false,
        'lazy': false,
      });
      final runtimeId = (result['session_id'] ?? '').toString();
      if (runtimeId.isEmpty) {
        throw StateError('Hermes did not return a runtime session for this bot.');
      }
      return BotChatOpenResult(
        runtimeSessionId: runtimeId,
        storedSessionId: storedId.isEmpty ? openId : storedId,
        messages: _messages(result['messages']),
        created: false,
      );
    }

    final created = await _result('session.create', {
      'profile': name,
      'title': canonicalChatTitle,
      'hidden': true,
      'follow_profile_config': true,
      'source': 'hermes_mobile_bot',
    });
    final runtimeId = (created['session_id'] ?? '').toString();
    final storedId = (created['stored_session_id'] ?? '').toString();
    if (runtimeId.isEmpty) {
      throw StateError('Hermes did not return a runtime session for this bot.');
    }
    return BotChatOpenResult(
      runtimeSessionId: runtimeId,
      storedSessionId: storedId,
      messages: _messages(created['messages']),
      created: true,
    );
  }

  Future<void> submitPrompt({
    required String runtimeSessionId,
    required String text,
    required StreamCallback onEvent,
  }) async {
    final client = await _connect();
    await client.submitPrompt(
      text,
      sessionId: runtimeSessionId,
      onEvent: onEvent,
    );
  }

  Future<void> respondToApproval({
    required String runtimeSessionId,
    required String choice,
  }) async {
    await _result('approval.respond', {
      'session_id': runtimeSessionId,
      'choice': choice,
    });
  }

  Future<void> interrupt(String runtimeSessionId) async {
    await _result('session.interrupt', {'session_id': runtimeSessionId});
  }

  static List<Map<String, dynamic>> _messages(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  void close() {
    _ws?.close();
    _ws = null;
    _dashboard?.close();
    _dashboard = null;
  }
}

class BotChatOpenResult {
  final String runtimeSessionId;
  final String storedSessionId;
  final List<Map<String, dynamic>> messages;
  final bool created;

  const BotChatOpenResult({
    required this.runtimeSessionId,
    required this.storedSessionId,
    required this.messages,
    required this.created,
  });
}
