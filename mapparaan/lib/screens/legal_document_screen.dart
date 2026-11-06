import 'package:flutter/material.dart';

import '../legal/legal_documents.dart';

class LegalDocumentScreen extends StatefulWidget {
  final LegalDocument document;

  const LegalDocumentScreen({super.key, required this.document});

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkReachedEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkReachedEnd());
  }

  void _checkReachedEnd() {
    if (!mounted || _reachedEnd) return;
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter <= 16) {
      setState(() => _reachedEnd = true);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_checkReachedEnd)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Version ${document.version}',
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          document.introduction,
                          style: textTheme.bodyLarge?.copyWith(height: 1.55),
                        ),
                        const SizedBox(height: 20),
                        for (final section in document.sections) ...[
                          Text(
                            section.heading,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            section.body,
                            style: textTheme.bodyMedium?.copyWith(height: 1.55),
                          ),
                          const SizedBox(height: 20),
                        ],
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            document.closing,
                            style: textTheme.bodySmall?.copyWith(height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('legal-document-done'),
                  onPressed: _reachedEnd ? () => Navigator.pop(context, true) : null,
                  child: const Text('Done reading'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
