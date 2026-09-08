import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final String pinStorageKey;

  const BotsPane({
    required this.profiles,
    required this.onOpenBot,
    this.pinStorageKey = 'bot-pins',
    super.key,
  });

  @override
  State<BotsPane> createState() => _BotsPaneState();
}

class _BotsPaneState extends State<BotsPane> {
  late Future<ProfilesSnapshot> _snapshot = widget.profiles.list();
  bool _opening = false;
  String _query = '';
  Set<String> _pins = {};

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _pins = (prefs.getStringList(widget.pinStorageKey) ?? []).toSet());
  }

  Future<void> _togglePin(String name) async {
    final updated = {..._pins};
    if (!updated.add(name)) updated.remove(name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(widget.pinStorageKey, updated.toList());
    if (mounted) setState(() => _pins = updated);
  }


  void _refresh() {
    final next = widget.profiles.list();
    setState(() { _snapshot = next; });
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
                : 'Check Dashboard / Proxy Settings on your saved connection and '
                    'make sure the desktop service is running. $error',
            buttonLabel: 'Try again',
            onPressed: _refresh,
          );
        }

        final data = snapshot.data!;
        final profiles = data.profiles.where((p) => p.title.toLowerCase().contains(_query.toLowerCase())).toList();
        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await _snapshot;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search bots', border: OutlineInputBorder()),
                  onChanged: (value) => setState(() => _query = value),
                ),
              )),
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
                              'Conversations',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text('Hold a conversation to pin it.'),
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
              if (_pins.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 112,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final profile in profiles.where((p) => _pins.contains(p.name)))
                          SizedBox(
                            width: 100,
                            child: InkWell(
                              onTap: _opening ? null : () => _open(profile),
                              onLongPress: () => _togglePin(profile.name),
                              child: Column(children: [
                                CircleAvatar(child: Text(_BotCard._initials(profile.title))),
                                const SizedBox(height: 8),
                                Text(profile.title, maxLines: 2, textAlign: TextAlign.center),
                              ]),
                            ),
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
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => _BotCard(
                      profile: profiles[index],
                      enabled: !_opening,
                      pinned: _pins.contains(profiles[index].name),
                      onPin: () => _togglePin(profiles[index].name),
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
  final VoidCallback onPin;
  final bool enabled;
  final bool pinned;
  const _BotCard({required this.profile, required this.onTap, required this.enabled, required this.onPin, required this.pinned});

  @override
  Widget build(BuildContext context) {
    final session = profile.conversation;
    final palette = [Colors.deepPurple, Colors.blue, Colors.teal, Colors.orange, Colors.pink];
    final color = palette[profile.name.codeUnits.fold<int>(0, (sum, n) => sum + n) % palette.length];
    final lastActive = session?.lastActive ?? 0;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch((lastActive * 1000).round()));
    final time = lastActive <= 0 ? '' : age.inDays > 0 ? '${age.inDays}d' : age.inHours > 0 ? '${age.inHours}h' : 'Now';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      onTap: enabled ? onTap : null,
      onLongPress: onPin,
      leading: CircleAvatar(radius: 25, backgroundColor: color, foregroundColor: Colors.white, child: Text(_initials(profile.title))),
      title: Text(profile.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(session?.preview.trim().isNotEmpty == true ? session!.preview : 'No messages yet', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(time, style: Theme.of(context).textTheme.labelSmall),
        if (pinned) const Icon(Icons.push_pin, size: 14),
      ]),
    );
  }
  static String _initials(String value) {
    final words = value.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return 'H';
    return words.first.substring(0, 1).toUpperCase();
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
