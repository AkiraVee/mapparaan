import 'package:supabase_flutter/supabase_flutter.dart';

import '../legal/legal_documents.dart';

class LegalAcknowledgementService {
  static SupabaseClient get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw StateError('Cloud services are not configured.');
    }
  }

  static Future<bool> hasCurrentAcknowledgements() async {
    final result = await _client.rpc('has_current_legal_acknowledgements');
    if (result is! bool) {
      throw const FormatException(
        'The acknowledgement service returned an invalid response.',
      );
    }
    return result;
  }

  static Future<void> recordCurrentAcknowledgements() async {
    await _client.rpc(
      'record_current_legal_acknowledgements',
      params: {
        'p_terms_version': LegalDocuments.termsVersion,
        'p_privacy_version': LegalDocuments.privacyVersion,
      },
    );
    if (!await hasCurrentAcknowledgements()) {
      throw StateError(
        'The current acknowledgements were not saved. Please try again.',
      );
    }
  }
}
