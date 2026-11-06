import 'package:flutter/material.dart';

import '../legal/legal_documents.dart';
import '../screens/legal_document_screen.dart';

class LegalAcknowledgementControls extends StatefulWidget {
  final bool termsAccepted;
  final bool privacyAcknowledged;
  final ValueChanged<bool> onTermsChanged;
  final ValueChanged<bool> onPrivacyChanged;
  final bool showValidation;

  const LegalAcknowledgementControls({
    super.key,
    required this.termsAccepted,
    required this.privacyAcknowledged,
    required this.onTermsChanged,
    required this.onPrivacyChanged,
    this.showValidation = false,
  });

  @override
  State<LegalAcknowledgementControls> createState() =>
      _LegalAcknowledgementControlsState();
}

class _LegalAcknowledgementControlsState
    extends State<LegalAcknowledgementControls> {
  bool _termsReviewed = false;
  bool _privacyReviewed = false;

  Future<void> _review(LegalDocument document) async {
    final reviewed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );
    if (!mounted || reviewed != true) return;
    setState(() {
      if (document.type == LegalDocumentType.termsOfService) {
        _termsReviewed = true;
      } else {
        _privacyReviewed = true;
      }
    });
  }

  Widget _item({
    required bool accepted,
    required bool reviewed,
    required String label,
    required String reviewLabel,
    required VoidCallback onReview,
    required ValueChanged<bool> onChanged,
    required bool showError,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: accepted,
          onChanged: reviewed ? (value) => onChanged(value ?? false) : null,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(label),
          subtitle: Text(
            reviewed ? 'Required before creating or using an account.' : 'Read the notice to enable this checkbox.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onReview,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(reviewLabel),
          ),
        ),
        if (showError && !accepted)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Text(
              'Required: review and acknowledge this document.',
              style: TextStyle(color: colors.error),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _item(
          accepted: widget.termsAccepted,
          reviewed: _termsReviewed,
          label: 'I have read and agree to the Terms of Service.',
          reviewLabel: 'Read Terms of Service',
          onReview: () => _review(LegalDocuments.terms),
          onChanged: widget.onTermsChanged,
          showError: widget.showValidation,
        ),
        _item(
          accepted: widget.privacyAcknowledged,
          reviewed: _privacyReviewed,
          label: 'I have read and acknowledge the Data Privacy Notice.',
          reviewLabel: 'Read Data Privacy Notice',
          onReview: () => _review(LegalDocuments.privacy),
          onChanged: widget.onPrivacyChanged,
          showError: widget.showValidation,
        ),
      ],
    );
  }
}
