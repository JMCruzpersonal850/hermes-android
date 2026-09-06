import 'session.dart';

/// One Hermes profile as exposed by the Desktop Gateway `profiles.list` RPC.
///
/// Hermes Bot Mode treats profiles as named agents. The gateway is the source
/// of truth for identity, model/provider selection and the canonical "Bot Chat"
/// session, so the Android client never invents a parallel bot registry.
class HermesProfile {
  final String name;
  final String displayName;
  final String description;
  final String model;
  final String provider;
  final bool isDefault;
  final int skillCount;
  final bool hasAvatar;
  final Map<String, dynamic> uiMeta;
  final HermesProfileSession? canonicalSession;
  final HermesProfileSession? lastSession;
  final HermesProfileWorkerSession? workerSession;

  const HermesProfile({
    required this.name,
    required this.displayName,
    required this.description,
    required this.model,
    required this.provider,
    required this.isDefault,
    required this.skillCount,
    required this.hasAvatar,
    required this.uiMeta,
    this.canonicalSession,
    this.lastSession,
    this.workerSession,
  });

  String get title => displayName.trim().isNotEmpty ? displayName.trim() : name;

  /// The best existing conversation target for this bot.
  ///
  /// Bot Mode's canonical session wins. `last_session` is only a compatibility
  /// fallback for older gateways that predate the canonical Bot Chat field.
  HermesProfileSession? get conversation => canonicalSession ?? lastSession;

  factory HermesProfile.fromJson(Map<String, dynamic> json) {
    HermesProfileSession? parseSession(Object? raw) {
      if (raw is! Map) return null;
      return HermesProfileSession.fromJson(Map<String, dynamic>.from(raw));
    }

    HermesProfileWorkerSession? parseWorker(Object? raw) {
      if (raw is! Map) return null;
      return HermesProfileWorkerSession.fromJson(
        Map<String, dynamic>.from(raw),
      );
    }

    final rawMeta = json['ui_meta'];
    return HermesProfile(
      name: (json['name'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      provider: (json['provider'] ?? '').toString(),
      isDefault: json['is_default'] == true,
      skillCount: _asInt(json['skill_count']),
      hasAvatar: json['has_avatar'] == true,
      uiMeta: rawMeta is Map
          ? Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(rawMeta))
          : const <String, dynamic>{},
      canonicalSession: parseSession(json['canonical_session']),
      lastSession: parseSession(json['last_session']),
      workerSession: parseWorker(json['worker_session']),
    );
  }
}

/// A human-facing Bot Mode conversation summary returned inside profiles.list.
class HermesProfileSession {
  final String id;
  final String resolvedId;
  final String title;
  final String rootTitle;
  final String preview;
  final double startedAt;
  final double lastActive;
  final int messageCount;

  const HermesProfileSession({
    required this.id,
    required this.resolvedId,
    required this.title,
    required this.rootTitle,
    required this.preview,
    required this.startedAt,
    required this.lastActive,
    required this.messageCount,
  });

  String get openId => resolvedId.trim().isNotEmpty ? resolvedId : id;

  factory HermesProfileSession.fromJson(Map<String, dynamic> json) {
    return HermesProfileSession(
      id: (json['id'] ?? '').toString(),
      resolvedId: (json['resolved_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      rootTitle: (json['root_title'] ?? '').toString(),
      preview: (json['preview'] ?? '').toString(),
      startedAt: _asDouble(json['started_at']),
      lastActive: _asDouble(json['last_active']),
      messageCount: _asInt(json['message_count']),
    );
  }

  /// Adapts a gateway profile session to the app's existing chat model.
  Session toSession(HermesProfile profile) {
    return Session(
      id: openId,
      title: profile.title,
      model: profile.model,
      source: 'bot:${profile.name}',
      messageCount: messageCount,
      isActive: true,
      preview: preview,
      startedAt: startedAt,
      lastActive: lastActive,
    );
  }
}

/// Recent worker activity for a profile. Hermes uses this to signal that a bot
/// is actively working even though worker sessions stay out of chat lists.
class HermesProfileWorkerSession {
  final String id;
  final String source;
  final String title;
  final double lastActive;

  const HermesProfileWorkerSession({
    required this.id,
    required this.source,
    required this.title,
    required this.lastActive,
  });

  factory HermesProfileWorkerSession.fromJson(Map<String, dynamic> json) {
    return HermesProfileWorkerSession(
      id: (json['id'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      lastActive: _asDouble(json['last_active']),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
