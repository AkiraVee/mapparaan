import 'package:supabase_flutter/supabase_flutter.dart';

import '../legal/legal_documents.dart';

class LegalAcknowledgementException implements Exception {
  const LegalAcknowledgementException(this.message);

  final String message;

  @override
  String toString() => message;
}

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
    final rows = await _client
        .from('legal_document_versions')
        .select('document_type, version')
        .eq('is_current', true);
    final currentVersions = <String, String>{
      for (final row in rows)
        if (row['document_type'] is String && row['version'] is String)
          row['document_type'] as String: row['version'] as String,
    };
    if (currentVersions['terms_of_service'] != LegalDocuments.termsVersion ||
        currentVersions['privacy_notice'] != LegalDocuments.privacyVersion) {
      final databasePrivacyVersion =
          currentVersions['privacy_notice'] ?? 'missing';
      throw LegalAcknowledgementException(
        'The privacy notice version in Supabase ($databasePrivacyVersion) '
        'does not match this app (${LegalDocuments.privacyVersion}). Apply '
        'supabase/migrations/20261107_update_ai_privacy_notice.sql in the '
        'Supabase project, then try again.',
      );
    }

    await _client.rpc(
      'record_current_legal_acknowledgements',
      params: {
        'p_terms_version': LegalDocuments.termsVersion,
        'p_privacy_version': LegalDocuments.privacyVersion,
      },
    );
    if (!await hasCurrentAcknowledgements()) {
      throw const LegalAcknowledgementException(
        'The current acknowledgements were not saved. Please try again.',
      );
    }
  }
}
