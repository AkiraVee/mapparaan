import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';

import '../services/ai_chat_service.dart';
import '../services/auth_service.dart';

class AiChatScreen extends StatefulWidget {
  final String? initialPrompt;

  const AiChatScreen({super.key, this.initialPrompt});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AiChatMessage> _messages = <AiChatMessage>[];
  final AiChatService _service = AiChatService();

  bool _isSending = false;
  late String _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = const Uuid().v4();
    if (widget.initialPrompt != null && widget.initialPrompt!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _submitPrompt(widget.initialPrompt!);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitPrompt(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _isSending) return;
    if (AuthService.currentUser == null) {
      _showMessage('Please sign in to use MapParaan AI.');
      return;
    }

    final history = List<AiChatMessage>.from(_messages);
    setState(() {
      _messages.add(AiChatMessage.user(text));
      _isSending = true;
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final response = await _service.sendMessage(
        message: text,
        sessionId: _sessionId,
        history: history,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          AiChatMessage.assistant(
            response.userFacingMessage,
            isError: !response.isOk,
          ),
        );
        _isSending = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          AiChatMessage.assistant(
            error is StateError ? error.message : 'MapParaan AI could not answer that request right now.',
            isError: true,
          ),
        );
        _isSending = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _newConversation() {
    _sessionId = const Uuid().v4();
    setState(() {
      _messages.clear();
      _isSending = false;
    });
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surface = colorScheme.surface;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MapParaan AI'),
        actions: [
          IconButton(
            tooltip: 'New conversation',
            onPressed: _newConversation,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _WelcomeView(onPromptSelected: _submitPrompt)
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (_isSending && index == _messages.length) {
                        return _TypingBubble();
                      }
                      final message = _messages[index];
                      final isUser = message.role == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.82,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(isUser ? 16 : 4),
                              topRight: Radius.circular(isUser ? 4 : 16),
                              bottomLeft: const Radius.circular(16),
                              bottomRight: const Radius.circular(16),
                            ),
                          ),
                          child: MarkdownBody(
                            data: message.text,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                color: isUser
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                                fontSize: 15,
                                height: 1.5,
                              ),
                              strong: TextStyle(
                                color: isUser
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                              listBullet: TextStyle(
                                color: isUser
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                              ),
                              blockquote: TextStyle(
                                color: isUser
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                              ),
                              code: TextStyle(
                                color: isUser
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                                fontFamily: 'monospace',
                              ),
                              h1: TextStyle(
                                color: isUser
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              h2: TextStyle(
                                color: isUser
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                              h3: TextStyle(
                                color: isUser
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              a: TextStyle(
                                color: isUser ? colorScheme.onPrimary : colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                              horizontalRuleDecoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: isUser
                                        ? colorScheme.onPrimary.withValues(alpha: 0.35)
                                        : colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                              blockSpacing: 6,
                              listIndent: 18,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: surface,
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: TextField(
                        controller: _controller,
                        focusNode: FocusNode(),
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'Ask about routes, fares, or nearby places…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (value) {
                          if (!_isSending) {
                            _submitPrompt(value);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSending ? null : () => _submitPrompt(_controller.text),
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('Send'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeView extends StatelessWidget {
  final ValueChanged<String> onPromptSelected;

  const _WelcomeView({required this.onPromptSelected});

  static const List<String> _quickPrompts = [
    'How do I get to SM City Manila?',
    'Find nearby malls.',
    'How much is the LRT fare?',
    'What transportation options are available?',
    'How do I get to Universidad de Manila?',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.smart_toy_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Hi! I'm MapParaan AI. I can help you navigate around Manila, find nearby places, estimate transportation fares, and recommend commuting routes.",
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Quick prompts',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickPrompts
                .map(
                  (prompt) => ActionChip(
                    label: Text(prompt),
                    onPressed: () => onPromptSelected(prompt),
                    avatar: const Icon(Icons.chat_bubble_outline, size: 18),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Thinking…',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
