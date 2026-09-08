// Bots + Skills browser. Bot Mode is gateway-backed so Android and Desktop
// always see the same Hermes profiles.
import 'package:flutter/material.dart';

import '../services/bot_mode_gateway.dart';
import '../services/connection_manager.dart';
import '../widgets/bots_pane.dart';
import 'bot_chat_screen.dart';

class SkillsScreen extends StatefulWidget {
  final SavedConnection connection;
  const SkillsScreen({required this.connection, super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  late DashboardClient _client;
  late final BotModeGateway _botGateway;
  List<Map<String, dynamic>> _skills = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = DashboardClient(
      host: widget.connection.host,
      port: widget.connection.dashboardPort,
      pathPrefix: widget.connection.dashboardPrefix ?? "",
      proxied: widget.connection.dashboardProxied,
      useHttps: widget.connection.useHttps,
      username: widget.connection.dashboardUsername,
      password: widget.connection.dashboardPassword,
    );
    _botGateway = BotModeGateway(widget.connection);
    _load();
  }

  @override
  void dispose() {
    _botGateway.close();
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _client.getSkills();
      if (!mounted) return;
      setState(() {
        _skills = raw.whereType<Map<String, dynamic>>().toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bots & Skills'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.smart_toy_outlined), text: 'Bots'),
              Tab(icon: Icon(Icons.auto_awesome_outlined), text: 'Skills'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            BotsPane(
              profiles: _botGateway.profiles,
              onOpenBot: (profile) async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BotChatScreen(
                      connection: widget.connection,
                      profile: profile,
                    ),
                  ),
                );
              },
            ),
            _buildSkillsBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Could not connect to desktop skills',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Check Dashboard / Proxy Settings on your saved connection. '
                '${_error!}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_skills.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_off, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No skills found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _skills.length,
        itemBuilder: (_, i) {
          final skill = _skills[i];
          final name = skill['name'] as String? ?? '';
          final enabled = skill['enabled'] as bool? ?? false;
          final description = skill['description'] as String? ?? '';
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(
                name,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              subtitle: description.isNotEmpty
                  ? Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
              trailing: Icon(
                enabled ? Icons.check_circle : Icons.block,
                color: enabled ? Colors.green : Colors.orange,
                size: 18,
              ),
            ),
          );
        },
      ),
    );
  }
}
