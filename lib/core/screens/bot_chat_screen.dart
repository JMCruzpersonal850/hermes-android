import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/hermes_profile.dart';
import '../services/bot_mode_gateway.dart';
import '../services/connection_manager.dart';
import '../services/ws_client.dart';
import '../utils/message_content.dart';

/// A deliberately small, profile-aware Bot Mode chat.
///
/// The existing general ChatScreen assumes the launch/default profile for REST
/// history. BotChatScreen instead keeps create/resume/prompt calls on the bot's
/// own profile so a mobile open can never drift into another bot's state.db.
class BotChatScreen extends StatefulWidget {
  final SavedConnection connection;
  final HermesProfile profile;

  const BotChatScreen({
    required this.connection,
    required this.profile,
    super.key,
  });

  @override
  State<BotChatScreen> createState() => _BotChatScreenState();
}

class _BotChatScreenState extends State<BotChatScreen> {
  late final BotModeGateway _gateway = BotModeGateway(widget.connection);
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];

  String? _runtimeSessionId;
  String? _error;
  String? _status;
  bool _loading = true;
  bool _sending = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _generation++;
    _gateway.close();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final opened = await _gateway.openCanonicalChat(widget.profile);
      if (!mounted) return;
      setState(() {
        _runtimeSessionId = opened.runtimeSessionId;
        _messages
          ..clear()
          ..addAll(opened.messages);
        _loading = false;
      });
      _scrollToEnd();

      // Hermes Desktop gives a brand-new bot this same first prompt so the
      // lazily-created "Bot Chat" is persisted immediately and the bot gets a
      // chance to introduce itself. Existing bots never receive it again.
      if (opened.created && mounted) {
        await _sendText('Hey, tell me about yourself!', automatic: true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await _sendText(text);
  }

  Future<void> _sendText(String text, {bool automatic = false}) async {
    final runtime = _runtimeSessionId;
    if (runtime == null || runtime.isEmpty || _sending) {
      if (!automatic) _composer.text = text;
      return;
    }

    final generation = ++_generation;
    setState(() {
      _sending = true;
      _status = 'Hermes is thinking…';
      _messages.add({'role': 'user', 'content': text});
      _messages.add({'role': 'assistant', 'content': ''});
    });
    _scrollToEnd();

    try {
      await _gateway.submitPrompt(
        runtimeSessionId: runtime,
        text: text,
        onEvent: (event) => _onEvent(event, generation),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _sending = false;
        _status = null;
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _sending = false;
        _status = null;
        final last = _messages.isEmpty ? null : _messages.last;
        if (last != null &&
            last['role'] == 'assistant' &&
            messageContentToText(last['content']).trim().isEmpty) {
          _messages.removeLast();
        }
        _error = 'Message failed: $error';
      });
      if (!automatic) _composer.text = text;
    }
  }

  void _onEvent(StreamEvent event, int generation) {
    if (!mounted || generation != _generation) return;

    if (event.type == 'message.delta') {
      final token = event.data['text']?.toString() ?? '';
      if (token.isEmpty) return;
      setState(() {
        _status = null;
        final assistant = _lastAssistant();
        if (assistant != null) {
          assistant['content'] =
              '${messageContentToText(assistant['content'])}$token';
        }
      });
      _scrollToEnd();
      return;
    }

    if (event.type == 'message.interim') {
      final text = event.data['text']?.toString() ?? '';
      if (text.isEmpty) return;
      setState(() {
        _status = null;
        final assistant = _lastAssistant();
        if (assistant != null) assistant['content'] = text;
      });
      _scrollToEnd();
      return;
    }

    if (event.type == 'message.complete') {
      final text =
          event.data['rendered']?.toString() ??
          event.data['text']?.toString() ??
          '';
      if (text.isNotEmpty) {
        setState(() {
          final assistant = _lastAssistant();
          if (assistant != null) assistant['content'] = text;
        });
        _scrollToEnd();
      }
      return;
    }

    if (event.type == 'approval.request') {
      unawaited(_showApproval(event.data, generation));
      return;
    }

    if (event.type.startsWith('tool.')) {
      final name =
          event.data['name']?.toString() ??
          event.data['tool_name']?.toString() ??
          'tool';
      if (event.type.endsWith('start') || event.type.endsWith('call')) {
        setState(() => _status = 'Using $name…');
      }
      return;
    }

    if (event.type.startsWith('subagent.')) {
      final goal =
          event.data['goal']?.toString() ??
          event.data['name']?.toString() ??
          'another agent';
      setState(() => _status = 'Delegating to $goal…');
      return;
    }

    if (event.type == 'turn.error' || event.type == 'error') {
      final message = event.data['message']?.toString() ?? 'Hermes turn failed';
      setState(() => _error = message);
    }
  }

  Map<String, dynamic>? _lastAssistant() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i]['role'] == 'assistant') return _messages[i];
    }
    return null;
  }

  Future<void> _showApproval(
    Map<String, dynamic> data,
    int generation,
  ) async {
    if (!mounted || generation != _generation) return;
    final command =
        data['command']?.toString() ??
        data['description']?.toString() ??
        data['tool']?.toString() ??
        'Hermes wants permission to continue.';

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Hermes needs approval'),
        content: Text(command),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'deny'),
            child: const Text('Deny'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'once'),
            child: const Text('Allow once'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'session'),
            child: const Text('Allow for chat'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted || generation != _generation) return;
    try {
      await _gateway.respondToApproval(
        runtimeSessionId: _runtimeSessionId!,
        choice: choice,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not answer approval: $error');
    }
  }

  Future<void> _stop() async {
    final runtime = _runtimeSessionId;
    if (runtime == null || !_sending) return;
    try {
      await _gateway.interrupt(runtime);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _status = null;
        });
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final modelLine = [
      if (profile.provider.trim().isNotEmpty) profile.provider.trim(),
      if (profile.model.trim().isNotEmpty) profile.model.trim(),
    ].join(' • ');
    final initial = profile.title.isEmpty ? 'H' : profile.title[0].toUpperCase();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(
          children: [
            CircleAvatar(child: Text(initial)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (modelLine.isNotEmpty)
                    Text(
                      modelLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(child: _buildConversation()),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status!)),
                ],
              ),
            ),
          SafeArea(top: false, child: _composerBar()),
        ],
      ),
    );
  }

  Widget _buildConversation() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.smart_toy_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                'Chat with ${widget.profile.title}',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.profile.description.trim().isEmpty
                    ? 'This is the bot’s permanent Hermes conversation.'
                    : widget.profile.description.trim(),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final role = message['role']?.toString() ?? '';
        if (role != 'user' && role != 'assistant') {
          return const SizedBox.shrink();
        }
        final user = role == 'user';
        final text = messageContentToText(message['content']).trim();
        if (text.isEmpty && !(!user && _sending && index == _messages.length - 1)) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        return Align(
          alignment: user ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: user ? scheme.primaryContainer : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
            ),
            child: text.isEmpty
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : user
                ? SelectableText(text)
                : MarkdownBody(data: text, selectable: true),
          ),
        );
      },
    );
  }

  Widget _composerBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _composer,
              enabled: !_loading,
              minLines: 1,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Message ${widget.profile.title}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
              ),
              onSubmitted: (_) {
                if (!_sending) unawaited(_send());
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: _sending ? 'Stop' : 'Send',
            onPressed: _loading
                ? null
                : _sending
                ? () => unawaited(_stop())
                : () => unawaited(_send()),
            icon: Icon(_sending ? Icons.stop_rounded : Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
