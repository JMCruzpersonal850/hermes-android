import 'package:flutter/material.dart';

import '../models/hermes_profile.dart';
import '../services/profiles_gateway_client.dart';
import '../theme/hermes_theme.dart';
import 'hermes_components.dart';

typedef BotSelected = Future<void> Function(HermesProfile profile);

/// Native Bot Mode roster for Android.
///
/// The roster comes directly from Hermes `profiles.list`, including each
/// profile's canonical Bot Chat. This deliberately does not create a second
/// mobile-only agent store.
class BotsPane extends StatefulWidget {
  final ProfilesGatewayClient profiles;
  final BotSelected onOpenBot;

  const BotsPane({
    required this.profiles,
    required this.onOpenBot,
    super.key,
  });

  @override
  State<BotsPane> createState() => _BotsPaneState();
}

class _BotsPaneState extends State<BotsPane> {
  late Future<ProfilesSnapshot> _snapshot = widget.profiles.list();
  bool _opening = false;

  void _refresh() {
    setState(() => _snapshot = widget.profiles.list());
  }

  Future<void> _createBot() async {
    final draft = await showModalBottomSheet<_BotDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _CreateBotSheet(),
    );
    if (draft == null || !mounted) return;

    try {
      await widget.profiles.create(
        name: draft.name,
        description: draft.description,
        soul: draft.soul,
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${draft.name} is ready.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create bot: $error')),
      );
    }
  }

  Future<void> _open(HermesProfile profile) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onOpenBot(profile);
      if (mounted) _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${profile.title}: $error')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfilesSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: HermesSpacing.lg),
            child: LoadingSkeleton(rows: 5),
          );
        }

        if (snapshot.hasError) {
          final error = snapshot.error;
          final unsupported = error is ProfilesUnsupportedException;
          return _BotsEmptyState(
            icon: unsupported ? Icons.system_update_alt_rounded : Icons.cloud_off_rounded,
            title: unsupported ? 'Update Hermes to use Bot Mode' : 'Could not load your bots',
            message: unsupported
                ? 'The PC gateway does not expose profiles.list yet. Update Hermes on the PC, then refresh.'
                : '$error',
            buttonLabel: 'Try again',
            onPressed: _refresh,
          );
        }

        final data = snapshot.data!;
        final profiles = data.profiles;
        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await _snapshot;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HermesSpacing.lg,
                    HermesSpacing.lg,
                    HermesSpacing.lg,
                    HermesSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bots',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text('Your Hermes agents, synced with your PC.'),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _createBot,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New bot'),
                      ),
                    ],
                  ),
                ),
              ),
              if (!data.botModeProtocol)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      HermesSpacing.lg,
                      0,
                      HermesSpacing.lg,
                      HermesSpacing.md,
                    ),
                    child: _ProtocolNotice(),
                  ),
                ),
              if (profiles.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _BotsEmptyState(
                    icon: Icons.smart_toy_outlined,
                    title: 'No bots yet',
                    message: 'Create your first Hermes agent and it will appear here and on Desktop.',
                    buttonLabel: 'Create a bot',
                    onPressed: _createBot,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    HermesSpacing.lg,
                    0,
                    HermesSpacing.lg,
                    HermesSpacing.xl,
                  ),
                  sliver: SliverList.separated(
                    itemCount: profiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: HermesSpacing.md),
                    itemBuilder: (context, index) => _BotCard(
                      profile: profiles[index],
                      enabled: !_opening,
                      onTap: () => _open(profiles[index]),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BotCard extends StatelessWidget {
  final HermesProfile profile;
  final VoidCallback onTap;
  final bool enabled;

  const _BotCard({
    required this.profile,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final session = profile.conversation;
    final working = _isWorking(profile.workerSession);
    final modelLine = [
      if (profile.provider.trim().isNotEmpty) profile.provider.trim(),
      if (profile.model.trim().isNotEmpty) profile.model.trim(),
    ].join(' • ');

    return HermesCard(
      onTap: enabled ? onTap : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: tokens.accent.withValues(alpha: 0.14),
            ),
            child: Text(
              _initials(profile.title),
              style: TextStyle(
                color: tokens.accent,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: HermesSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        profile.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (working)
                      const _StatusPill(label: 'Working', icon: Icons.bolt_rounded)
                    else if (profile.isDefault)
                      const _StatusPill(label: 'Default', icon: Icons.star_rounded),
                  ],
                ),
                if (profile.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    profile.description.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.muted),
                  ),
                ],
                if (session?.preview.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    session!.preview.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (modelLine.isNotEmpty || profile.skillCount > 0) ...[
                  const SizedBox(height: 9),
                  Text(
                    [
                      if (modelLine.isNotEmpty) modelLine,
                      if (profile.skillCount > 0)
                        '${profile.skillCount} skill${profile.skillCount == 1 ? '' : 's'}',
                    ].join('  •  '),
                    style: TextStyle(
                      color: tokens.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Padding(
            padding: EdgeInsets.only(top: 15),
            child: Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  static bool _isWorking(HermesProfileWorkerSession? worker) {
    if (worker == null || worker.lastActive <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    return now - worker.lastActive < 120;
  }

  static String _initials(String value) {
    final words = value.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return 'H';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first.substring(0, 1)}${words.last.substring(0, 1)}'.toUpperCase();
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;

  const _StatusPill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tokens.accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: tokens.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtocolNotice extends StatelessWidget {
  const _ProtocolNotice();

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(HermesSpacing.md),
      decoration: BoxDecoration(
        color: tokens.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This gateway supports profiles, but does not advertise the latest Bot Mode protocol. Update Hermes on the PC for bot-to-bot messaging.',
            ),
          ),
        ],
      ),
    );
  }
}

class _BotsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _BotsEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HermesSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44),
            const SizedBox(height: HermesSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: HermesSpacing.lg),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}

class _BotDraft {
  final String name;
  final String description;
  final String soul;

  const _BotDraft({
    required this.name,
    required this.description,
    required this.soul,
  });
}

class _CreateBotSheet extends StatefulWidget {
  const _CreateBotSheet();

  @override
  State<_CreateBotSheet> createState() => _CreateBotSheetState();
}

class _CreateBotSheetState extends State<_CreateBotSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _soul = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _soul.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _BotDraft(
        name: name,
        description: _description.text.trim(),
        soul: _soul.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          HermesSpacing.lg,
          0,
          HermesSpacing.lg,
          HermesSpacing.lg + bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Create a bot',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text('This creates a real Hermes profile on your PC.'),
            const SizedBox(height: HermesSpacing.lg),
            TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Marketing',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: HermesSpacing.md),
            TextField(
              controller: _description,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'What does this bot do?',
                hintText: 'Meta ads, campaign strategy and copy',
              ),
            ),
            const SizedBox(height: HermesSpacing.md),
            TextField(
              controller: _soul,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Instructions (optional)',
                hintText: 'You are my marketing specialist...',
              ),
            ),
            const SizedBox(height: HermesSpacing.lg),
            FilledButton.icon(
              onPressed: _name.text.trim().isEmpty ? null : _submit,
              icon: const Icon(Icons.smart_toy_rounded),
              label: const Text('Create bot'),
            ),
          ],
        ),
      ),
    );
  }
}
