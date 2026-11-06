import 'package:flutter/material.dart';

import '../services/legal_acknowledgement_service.dart';
import '../widgets/legal_acknowledgement_controls.dart';

class LegalAcknowledgementScreen extends StatefulWidget {
  final VoidCallback onAcknowledged;
  final Future<void> Function() onSignOut;

  const LegalAcknowledgementScreen({
    super.key,
    required this.onAcknowledged,
    required this.onSignOut,
  });

  @override
  State<LegalAcknowledgementScreen> createState() =>
      _LegalAcknowledgementScreenState();
}

class _LegalAcknowledgementScreenState
    extends State<LegalAcknowledgementScreen> {
  bool _termsAccepted = false;
  bool _privacyAcknowledged = false;
  bool _showValidation = false;
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _signOut() async {
    try {
      await widget.onSignOut();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription(
            'while signing out from the legal acknowledgement screen',
          ),
        ),
      );
      if (mounted) {
        setState(
          () => _errorMessage =
              'We could not sign you out. Check your connection and try again.',
        );
      }
    }
  }

  Future<void> _continue() async {
    setState(() {
      _showValidation = true;
      _errorMessage = null;
    });
    if (!_termsAccepted || !_privacyAcknowledged) return;

    setState(() => _isSaving = true);
    try {
      await LegalAcknowledgementService.recordCurrentAcknowledgements();
      if (mounted) widget.onAcknowledged();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription(
            'while recording current legal acknowledgements',
          ),
        ),
      );
      if (mounted) {
        setState(
          () => _errorMessage =
              'We could not save your acknowledgement. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Review updated notices')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              'Your acknowledgement is needed',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Please review both current documents. Account features will '
              'remain locked until you acknowledge them.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            LegalAcknowledgementControls(
              termsAccepted: _termsAccepted,
              privacyAcknowledged: _privacyAcknowledged,
              onTermsChanged: (value) =>
                  setState(() => _termsAccepted = value),
              onPrivacyChanged: (value) =>
                  setState(() => _privacyAcknowledged = value),
              showValidation: _showValidation,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isSaving ? null : _continue,
              child: _isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Acknowledge and continue'),
            ),
            TextButton(
              onPressed: _isSaving ? null : _signOut,
              child: const Text('Sign out and continue as a guest'),
            ),
          ],
        ),
      ),
    );
  }
}
