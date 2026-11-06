import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';

import '../services/ai_chat_service.dart';
import '../services/place_search_service.dart';
import '../services/transit_planner_service.dart';
import 'location_details_screen.dart';

class AiChatScreen extends StatefulWidget {
  final String? initialPrompt;
  final AiChatService? service;

  const AiChatScreen({super.key, this.initialPrompt, this.service});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  final List<AiChatMessage> _messages = <AiChatMessage>[];
  late final AiChatService _service;

  bool _isSending = false;
  String? _retryPrompt;
  String? _selectedRouteTitle;
  int _conversationGeneration = 0;
  late String _sessionId;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AiChatService();
    _sessionId = const Uuid().v4();
    if (widget.initialPrompt != null &&
        widget.initialPrompt!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _submitPrompt(widget.initialPrompt!);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _submitPrompt(String rawText, {bool retry = false}) async {
    final text = rawText.trim();
    if (text.isEmpty || _isSending) return;

    final history = _messages.where((message) => !message.isError).toList();
    if (retry && history.isNotEmpty) {
      history.removeLast();
    }
    final generation = _conversationGeneration;
    setState(() {
      if (retry && _messages.length >= 2) {
        _messages.removeLast();
        _messages.removeLast();
      }
      _retryPrompt = null;
      _messages.add(AiChatMessage.user(text));
      _isSending = true;
      _controller.clear();
    });
    _scrollToBottom();

    late AiChatMessage assistantReply;
    var canRetry = false;
    try {
      final response = await _service.sendMessage(
        message: text,
        sessionId: _sessionId,
        history: history,
        selectedRouteTitle: _selectedRouteTitle,
      );
      assistantReply = AiChatMessage.assistant(
        response.userFacingMessage,
        isError: !response.hasUsableAnswer,
        routeRecommendations: response.routeRecommendations,
      );
      canRetry =
          !response.hasUsableAnswer &&
          !{
            'quota_exceeded',
            'not_configured',
            'unauthorized',
            'provider_quota_exceeded',
          }.contains(response.status);
    } catch (error) {
      assistantReply = AiChatMessage.assistant(
        error is StateError ? error.message : 'Could not reach MapParaan AI. Check your connection and try again.',
        isError: true,
      );
      canRetry = error is! StateError;
    }
    if (!mounted || generation != _conversationGeneration) return;
    setState(() {
      _messages.add(assistantReply);
      _retryPrompt = canRetry ? text : null;
      _isSending = false;
    });
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

  void _newConversation() {
    _conversationGeneration++;
    _sessionId = const Uuid().v4();
    setState(() {
      _messages.clear();
      _isSending = false;
      _retryPrompt = null;
      _selectedRouteTitle = null;
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
                      final retryPrompt = _retryPrompt;
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: isUser
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.82,
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
                                    color: isUser
                                        ? colorScheme.onPrimary
                                        : colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                  horizontalRuleDecoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: isUser
                                            ? colorScheme.onPrimary.withValues(
                                                alpha: 0.35,
                                              )
                                            : colorScheme.outlineVariant,
                                      ),
                                    ),
                                  ),
                                  blockSpacing: 6,
                                  listIndent: 18,
                                ),
                              ),
                            ),
                            if (!isUser &&
                                message.routeRecommendations.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _RouteRecommendationCards(
                                  key: ValueKey('routes-$index'),
                                  recommendations: message.routeRecommendations,
                                  selectedRouteTitle: _selectedRouteTitle,
                                  onSelectRoute: (title) {
                                    setState(() {
                                      _selectedRouteTitle = title;
                                    });
                                  },
                                ),
                              ),
                            if (message.isError &&
                                index == _messages.length - 1 &&
                                retryPrompt != null)
                              TextButton.icon(
                                onPressed: _isSending
                                    ? null
                                    : () => _submitPrompt(
                                        retryPrompt,
                                        retry: true,
                                      ),
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: const Text('Retry'),
                              ),
                          ],
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
                  top: BorderSide(color: colorScheme.outlineVariant),
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
                        focusNode: _inputFocusNode,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText:
                              'Ask about routes, fares, or nearby places…',
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
                    onPressed: _isSending
                        ? null
                        : () => _submitPrompt(_controller.text),
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

class _RouteRecommendationCards extends StatefulWidget {
  final List<AiChatRouteRecommendation> recommendations;
  final String? selectedRouteTitle;
  final ValueChanged<String> onSelectRoute;

  const _RouteRecommendationCards({
    super.key,
    required this.recommendations,
    required this.selectedRouteTitle,
    required this.onSelectRoute,
  });

  @override
  State<_RouteRecommendationCards> createState() =>
      _RouteRecommendationCardsState();
}

class _RouteRecommendationCardsState extends State<_RouteRecommendationCards> {
  final Set<String> _expandedRoutes = {};

  String _routeKey(AiChatRouteRecommendation recommendation, int index) =>
      '${recommendation.origin.name}:${recommendation.destination.name}:'
      '${recommendation.options[index].title}:$index';

  void _select(
    AiChatRouteRecommendation recommendation,
    TransitPlanOption option,
  ) {
    widget.onSelectRoute(
      '${recommendation.origin.name} to ${recommendation.destination.name}: '
      '${option.title}',
    );
  }

  Future<void> _openMap(
    AiChatRouteRecommendation recommendation,
    TransitPlanOption option,
  ) async {
    _select(recommendation, option);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LocationDetailsScreen(
          place: PlaceResult(
            name: recommendation.destination.name,
            subtitle: 'From ${recommendation.origin.name}',
            coordinates: recommendation.destination.coordinates,
          ),
          userLocation: recommendation.origin.coordinates,
          origin: recommendation.origin.name,
          passengerType: recommendation.passengerCategory,
          initialPreference: option.routePreference,
          initialRouteOption: option,
        ),
      ),
    );
  }

  List<String> _comparisonLabels(
    AiChatRouteRecommendation recommendation,
    TransitPlanOption option,
  ) {
    final options = recommendation.options;
    if (options.length < 2) return const [];
    final passengerType = recommendation.passengerCategory;
    final labels = <String>[];
    final cheapest = options.reduce(
      (a, b) => a.effectiveFare(passengerType) <= b.effectiveFare(passengerType)
          ? a
          : b,
    );
    final fastest = options.reduce(
      (a, b) => a.etaMinutes <= b.etaMinutes ? a : b,
    );
    final fewestTransfers = options.reduce(
      (a, b) => a.transfers <= b.transfers ? a : b,
    );
    if (identical(option, cheapest)) labels.add('Cheapest returned');
    if (identical(option, fastest)) labels.add('Fastest returned');
    if (identical(option, fewestTransfers)) {
      labels.add('Fewest transfers');
    }
    return labels;
  }

  Widget _buildLeg(BuildContext context, TransitLeg leg, int index) {
    final theme = Theme.of(context);
    final mode = leg.isWalk ? 'Walk' : (leg.modeLabel ?? leg.mode ?? 'Transit');
    final route = leg.routeCode ?? leg.routeName;
    final fare = leg.isWalk
        ? 'No fare'
        : leg.fare == null
        ? null
        : 'Fare ${formatPeso(leg.fare!)}'
              '${leg.fareMax != null && leg.fareMax! > leg.fare! ? '–${formatPeso(leg.fareMax!)}' : ''}';
    final details = <String>[
      '$mode${route == null || route.isEmpty ? '' : ' · $route'}',
      '${leg.minutes} min${leg.waitMinutes != null && leg.waitMinutes! > 0 ? ' + ~${leg.waitMinutes} min wait' : ''}',
      ?fare,
      if (leg.meters != null) '${leg.meters} m',
    ];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: leg.color.withValues(alpha: 0.14),
        child: Text('${index + 1}', style: TextStyle(color: leg.color)),
      ),
      title: Text(
        leg.isWalk
            ? 'Walk from ${leg.from} to ${leg.to}'
            : 'Board at ${leg.from}; alight at ${leg.to}',
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(details.join(' · ')),
    );
  }

  Widget _buildRouteCard(
    BuildContext context,
    AiChatRouteRecommendation recommendation,
    TransitPlanOption option,
    int index,
  ) {
    final theme = Theme.of(context);
    final key = _routeKey(recommendation, index);
    final selected =
        widget.selectedRouteTitle ==
        '${recommendation.origin.name} to ${recommendation.destination.name}: '
            '${option.title}';
    final labels = _comparisonLabels(recommendation, option);
    final hasMapGeometry =
        option.legs.any((leg) => leg.path.length >= 2) &&
        option.allPoints.isNotEmpty;
    final summary = <String>[
      if (option.etaMinutes > 0) '~${option.etaMinutes} min',
      if (option.fare >= 0)
        option.hasFareRange(recommendation.passengerCategory)
            ? '${formatPeso(option.effectiveFare(recommendation.passengerCategory))}–${formatPeso(option.effectiveFareUpTo(recommendation.passengerCategory))}'
            : formatPeso(
                option.effectiveFare(recommendation.passengerCategory),
              ),
      '${option.transfers} transfer${option.transfers == 1 ? '' : 's'}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${recommendation.origin.name} → ${recommendation.destination.name}',
              style: theme.textTheme.labelMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(option.title, style: theme.textTheme.titleSmall),
            if (option.summary.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(option.summary, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 4),
            Text(summary.join(' · '), style: theme.textTheme.bodySmall),
            if (option.modes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: option.modes
                      .map(
                        (mode) => Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(mode),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                      .toList(),
                ),
              ),
            if (labels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  children: labels
                      .map(
                        (label) => Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(label),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                      .toList(),
                ),
              ),
            ExpansionTile(
              key: PageStorageKey<String>(key),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              initiallyExpanded: _expandedRoutes.contains(key),
              onExpansionChanged: (expanded) {
                setState(() {
                  if (expanded) {
                    _expandedRoutes.add(key);
                  } else {
                    _expandedRoutes.remove(key);
                  }
                });
              },
              title: const Text('View details'),
              children: [
                if (option.legs.isEmpty)
                  const ListTile(
                    dense: true,
                    title: Text('Step-by-step leg details are unavailable.'),
                  )
                else
                  ...option.legs.asMap().entries.map(
                    (entry) => _buildLeg(context, entry.value, entry.key),
                  ),
                if (option.isPartial && option.partialMessage != null)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline),
                    title: Text(option.partialMessage!),
                  ),
                if (recommendation.dataNotice != null)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text(recommendation.dataNotice!),
                  ),
              ],
            ),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _select(recommendation, option),
                  icon: Icon(selected ? Icons.check_circle : Icons.check),
                  label: Text(selected ? 'Selected' : 'Select route'),
                ),
                OutlinedButton.icon(
                  onPressed: hasMapGeometry
                      ? () => _openMap(recommendation, option)
                      : null,
                  icon: const Icon(Icons.map_outlined),
                  label: Text(
                    hasMapGeometry ? 'View on map' : 'Map geometry unavailable',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * 0.92,
    ),
    child: Column(
      children: [
        for (final recommendation in widget.recommendations)
          for (var index = 0; index < recommendation.options.length; index++)
            _buildRouteCard(
              context,
              recommendation,
              recommendation.options[index],
              index,
            ),
      ],
    ),
  );
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
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.08,
                    ),
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
