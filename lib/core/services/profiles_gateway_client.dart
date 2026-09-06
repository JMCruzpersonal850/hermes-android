import '../models/hermes_profile.dart';
import 'capability_registry.dart';
import 'ws_client.dart';

typedef ProfilesGatewayRpcCall = Future<Map<String, dynamic>> Function(
  String method,
  Map<String, dynamic> params,
);

class ProfilesUnsupportedException implements Exception {
  final String method;
  final String message;

  const ProfilesUnsupportedException(this.method, this.message);

  @override
  String toString() => 'ProfilesUnsupportedException($method): $message';
}

class ProfilesSnapshot {
  final List<HermesProfile> profiles;
  final bool botModeProtocol;

  const ProfilesSnapshot({
    required this.profiles,
    required this.botModeProtocol,
  });
}

/// Android client for Hermes Bot Mode's profile RPC family.
///
/// Profiles are the bots. Keeping this client gateway-backed means Android and
/// Desktop always see the same roster instead of maintaining a second mobile
/// bot database.
class ProfilesGatewayClient {
  static const _unknownMethodCode = -32601;
  static const _probeMethod = 'profiles.list';

  final ProfilesGatewayRpcCall _call;
  final CapabilityRegistry? capabilities;
  bool? _supported;

  ProfilesGatewayClient(this._call, {this.capabilities});

  bool? get cachedSupport => _supported;

  Future<bool> isSupported() async {
    final known = _supported;
    if (known != null) return known;
    try {
      await list(includeSessions: false);
      return true;
    } on ProfilesUnsupportedException {
      return false;
    }
  }

  Future<ProfilesSnapshot> list({bool includeSessions = true}) async {
    final result = await _request('profiles.list', {
      'include_sessions': includeSessions,
    });
    final rawProfiles = result['profiles'];
    final profiles = <HermesProfile>[];
    if (rawProfiles is List) {
      for (final raw in rawProfiles) {
        if (raw is Map) {
          profiles.add(
            HermesProfile.fromJson(Map<String, dynamic>.from(raw)),
          );
        }
      }
    }
    return ProfilesSnapshot(
      profiles: List<HermesProfile>.unmodifiable(profiles),
      botModeProtocol: result['bot_mode_protocol'] == true,
    );
  }

  Future<HermesProfile> create({
    required String name,
    String description = '',
    String soul = '',
    String? cloneFrom,
    String? model,
    String? provider,
    bool cloneAll = false,
    bool noSkills = false,
    bool shareAuth = true,
    bool mirrorCredentials = true,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A bot name is required');
    }
    final params = <String, dynamic>{
      'name': trimmedName,
      'mirror_credentials': mirrorCredentials,
      'share_auth': shareAuth,
    };
    final trimmedDescription = description.trim();
    final trimmedSoul = soul.trim();
    if (trimmedDescription.isNotEmpty) params['description'] = trimmedDescription;
    if (trimmedSoul.isNotEmpty) params['soul'] = trimmedSoul;
    if (cloneFrom?.trim().isNotEmpty == true) params['clone_from'] = cloneFrom!.trim();
    if (model?.trim().isNotEmpty == true) params['model'] = model!.trim();
    if (provider?.trim().isNotEmpty == true) params['provider'] = provider!.trim();
    if (cloneAll) params['clone_all'] = true;
    if (noSkills) params['no_skills'] = true;

    await _request('profiles.create', params);

    // profiles.create responses have changed across Hermes versions. Re-read
    // the authoritative roster instead of coupling the app to one response
    // shape.
    final snapshot = await list();
    for (final profile in snapshot.profiles) {
      if (profile.name == trimmedName) return profile;
    }
    throw JsonRpcError(
      'profiles.create',
      'Hermes created the bot but it was not present in the refreshed roster',
    );
  }

  Future<Map<String, dynamic>> describe(String name) {
    return _request('profiles.describe', {'name': _requireName(name)});
  }

  Future<Map<String, dynamic>> configure({
    required String name,
    String? displayName,
    String? description,
    String? soul,
    String? model,
    String? provider,
  }) {
    final params = <String, dynamic>{'name': _requireName(name)};
    if (displayName != null) params['display_name'] = displayName.trim();
    if (description != null) params['description'] = description.trim();
    if (soul != null) params['soul'] = soul;
    if (model != null) params['model'] = model.trim();
    if (provider != null) params['provider'] = provider.trim();
    return _request('profiles.configure', params);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final registry = capabilities;
    if (registry != null && registry.isUnsupported(method)) {
      if (method == _probeMethod) _supported = false;
      throw ProfilesUnsupportedException(
        method,
        'This Hermes gateway does not support $method',
      );
    }

    final Map<String, dynamic> response;
    try {
      response = await _call(method, params);
    } catch (error) {
      registry?.recordFailure(method, error);
      rethrow;
    }

    final error = response['error'];
    if (error != null) {
      final rpcError = error is Map
          ? JsonRpcError.fromGateway(
              method,
              error,
              fallbackMessage: 'Gateway Bot Mode call failed',
            )
          : JsonRpcError(method, 'Gateway Bot Mode call failed');
      registry?.recordFailure(method, rpcError);
      if (_isUnknownMethod(rpcError)) {
        if (method == _probeMethod) _supported = false;
        throw ProfilesUnsupportedException(method, rpcError.message);
      }
      _supported = true;
      throw rpcError;
    }

    _supported = true;
    registry?.recordSuccess(method);
    final result = response['result'];
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  static bool _isUnknownMethod(JsonRpcError error) {
    if (error.code == _unknownMethodCode) return true;
    final message = error.message.toLowerCase();
    return message.contains('unknown method') ||
        message.contains('method not found') ||
        message.contains('no handler for');
  }

  static String _requireName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A bot name is required');
    }
    return trimmed;
  }
}
