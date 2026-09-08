import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bot_mode_gateway.dart';
import '../services/connection_manager.dart';
import '../widgets/bots_pane.dart';
import 'bot_chat_screen.dart';

class BotsHomePane extends StatefulWidget {
  final SavedConnection connection;
  const BotsHomePane({required this.connection, super.key});
  @override
  State<BotsHomePane> createState() => _BotsHomePaneState();
}

class _BotsHomePaneState extends State<BotsHomePane> {
  late final _gateway = BotModeGateway(widget.connection);
  List<Map<String, dynamic>> _rooms = [];
  Set<String> _pins = {};
  String? _error;
  String get _key => 'group-pins-${widget.connection.host}:${widget.connection.dashboardPort}';
  @override
  void initState() { super.initState(); unawaited(_load()); }
  @override
  void dispose() { _gateway.close(); super.dispose(); }
  Future<void> _load() async {
    try {
      final result = await _gateway.groupRequest('groups.list', {});
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _rooms = (result['rooms'] as List? ?? []).whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList();
        _pins = (prefs.getStringList(_key) ?? []).toSet();
        _rooms.sort((a,b) => (_pins.contains(b['room_id']) ? 1 : 0).compareTo(_pins.contains(a['room_id']) ? 1 : 0));
        _error = null;
      });
    } catch (e) { if (mounted) setState(() => _error = 'Groups unavailable: $e'); }
  }
  Future<void> _pin(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final pins = {..._pins};
    if (!pins.add(id)) pins.remove(id);
    await prefs.setStringList(_key, pins.toList());
    await _load();
  }
  Future<void> _create() async {
    try {
      final snapshot = await _gateway.profiles.list(includeSessions: false);
      if (!mounted) return;
      final selected = <String>{};
      final name = TextEditingController();
      final accepted = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('New group'),
          content: SizedBox(width: 360, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Group name')),
            for (final bot in snapshot.profiles)
              CheckboxListTile(title: Text(bot.title), value: selected.contains(bot.name), onChanged: (value) => update(() { if (value == true) { selected.add(bot.name); } else { selected.remove(bot.name); } })),
          ]))),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: selected.length < 2 ? null : () => Navigator.pop(context, true), child: const Text('Create'))],
        ),
      ));
      final title = name.text.trim();
      // The dialog route retains its text field during the exit animation.
      if (accepted != true) return;
      final result = await _gateway.groupRequest('groups.create', {
        'room_id': 'mobile-${DateTime.now().microsecondsSinceEpoch}',
        'name': title.isEmpty ? selected.join(', ') : title,
        'members': selected.map((p) => {'profile': p, 'handle': p}).toList(),
      });
      await _load();
      if (!mounted) return;
      await _open(Map<String, dynamic>.from(result['room'] as Map));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create group: $e'))); }
  }
  Future<void> _open(Map<String, dynamic> room) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupChatScreen(connection: widget.connection, room: room)));
    await _load();
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _create, icon: const Icon(Icons.group_add), label: const Text('New group'))),
    if (_error != null) ListTile(title: Text(_error!, maxLines: 2), trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh))),
    if (_rooms.isNotEmpty) SizedBox(height: 112, child: ListView(scrollDirection: Axis.horizontal, children: [
      for (final room in _rooms) SizedBox(width: 132, child: InkWell(onTap: () => _open(room), onLongPress: () => _pin(room['room_id'].toString()), child: Column(children: [
        CircleAvatar(child: Icon(_pins.contains(room['room_id']) ? Icons.push_pin : Icons.group)),
        Text(room['name']?.toString() ?? 'Group', maxLines: 2, textAlign: TextAlign.center),
        TextButton(onPressed: () => _pin(room['room_id'].toString()), child: Text(_pins.contains(room['room_id']) ? 'Unpin' : 'Pin')),
      ]))),
    ])),
    Expanded(child: BotsPane(profiles: _gateway.profiles, pinStorageKey: 'bot-pins-${widget.connection.host}:${widget.connection.dashboardPort}', onOpenBot: (profile) async {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BotChatScreen(connection: widget.connection, profile: profile)));
    })),
  ]);
}

class GroupChatScreen extends StatefulWidget {
  final SavedConnection connection;
  final Map<String, dynamic> room;
  const GroupChatScreen({required this.connection, required this.room, super.key});
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}
class _GroupChatScreenState extends State<GroupChatScreen> {
  late final _gateway = BotModeGateway(widget.connection);
  final _text = TextEditingController();
  final _events = <Map<String,dynamic>>[];
  Timer? _poll;
  int _seq = 0;
  bool _reading = false;
  bool _sending = false;
  String? _error;
  String? _pendingId;
  String? _pendingText;
  String get _id => widget.room['room_id'].toString();
  @override
  void initState() { super.initState(); unawaited(_read()); _poll = Timer.periodic(const Duration(seconds: 2), (_) => _read()); }
  @override
  void dispose() { _poll?.cancel(); _gateway.close(); _text.dispose(); super.dispose(); }
  Future<void> _read() async {
    if (_reading) return;
    _reading = true;
    try {
      final result = await _gateway.groupRequest('groups.log', {'room_id': _id, 'since_seq': _seq, 'limit': 100});
      if (!mounted) return;
      setState(() {
        for (final raw in result['events'] as List? ?? []) {
          final event = Map<String,dynamic>.from(raw as Map);
          final seq = (event['seq'] as num?)?.toInt() ?? 0;
          if (seq <= _seq) continue;
          _seq = seq;
          _events.add(event);
        }
        _error = null;
      });
    } catch (e) { if (mounted) setState(() => _error = 'Could not refresh group: $e'); }
    finally { _reading = false; }
  }
  Future<void> _send() async {
    final text = _text.text.trim();
    if (_sending || text.isEmpty) return;
    if (_pendingText != text) { _pendingText = text; _pendingId = 'mobile-${DateTime.now().microsecondsSinceEpoch}'; }
    setState(() => _sending = true);
    try {
      await _gateway.groupRequest('groups.send', {'room_id': _id, 'event_id': _pendingId, 'payload': {'text': text}});
      if (!mounted) return;
      _text.clear(); _pendingText = null; _pendingId = null;
      await _read();
    } catch (e) { if (mounted) setState(() => _error = 'Message failed: $e'); }
    finally { if (mounted) setState(() => _sending = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.room['name']?.toString() ?? 'Group'), actions: [IconButton(tooltip: 'Stop group', icon: const Icon(Icons.stop), onPressed: () async {
      try { await _gateway.groupRequest('groups.stop', {'room_id': _id, 'cancel_id': 'mobile-${DateTime.now().microsecondsSinceEpoch}'}); }
      catch (e) { if (mounted) setState(() => _error = 'Could not stop group: $e'); }
    })]),
    body: SafeArea(child: Column(children: [
      const Padding(padding: EdgeInsets.all(12), child: Text('Mention a bot with @handle to direct your message.')),
      if (_error != null) Text(_error!),
      Expanded(child: ListView(children: [for (final event in _events)
        if (event['type'] == 'message.user' || event['type'] == 'message.member')
          ListTile(title: Text(event['actor_id']?.toString() ?? (event['type'] == 'message.user' ? 'You' : 'Bot')),
            subtitle: Text((event['payload'] is Map ? (event['payload']['text'] ?? event['payload']['content'] ?? '') : '').toString())),
      ])),
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 5, decoration: const InputDecoration(hintText: 'Message group', border: OutlineInputBorder()))), IconButton(onPressed: _sending ? null : _send, icon: const Icon(Icons.send))])),
    ])),
  );
}
