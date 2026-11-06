enum LegalDocumentType { termsOfService, privacyNotice }

class LegalDocumentSection {
  final String heading;
  final String body;

  const LegalDocumentSection(this.heading, this.body);
}

class LegalDocument {
  final LegalDocumentType type;
  final String title;
  final String version;
  final String introduction;
  final List<LegalDocumentSection> sections;
  final String closing;

  const LegalDocument({
    required this.type,
    required this.title,
    required this.version,
    required this.introduction,
    required this.sections,
    required this.closing,
  });
}

abstract final class LegalDocuments {
  static const termsVersion = '2026-11-07-v1';
  static const privacyVersion = '2026-11-07-v1';

  static const terms = LegalDocument(
    type: LegalDocumentType.termsOfService,
    title: 'Terms of Service',
    version: termsVersion,
    introduction:
        'Please read these terms before creating an account or using '
        'Mapparaan account features.',
    sections: [
      LegalDocumentSection(
        '1. Using Mapparaan',
        'By creating an account, you agree to these Terms of Service. '
            'You may use Mapparaan without an account as a guest, but saved '
            'account features require sign-in and acknowledgement of the '
            'current terms and privacy notice. We may ask you to review a '
            'revised version before continuing to use account features.',
      ),
      LegalDocumentSection(
        '2. What the app does',
        'Mapparaan helps people plan commutes around the City of Manila. It '
            'can search for places, suggest public-transport and walking '
            'options, estimate travel times and fares, and provide '
            'location-based results. Availability of transport modes and '
            'features depends on the data and services currently connected '
            'to the app.',
      ),
      LegalDocumentSection(
        '3. Information may be incomplete',
        'Routes, schedules, fares, travel times, place information, and '
            'recommendations may be incomplete, estimated, delayed, or '
            'out of date. Mapparaan does not guarantee that a route or '
            'transport service is operating, accessible, safe, or available. '
            'Check signs, official announcements, operators, and conditions '
            'on the ground before travelling.',
      ),
      LegalDocumentSection(
        '4. Your responsibilities',
        'Provide accurate account information, protect your sign-in details, '
            'and use the app lawfully and respectfully. You are responsible '
            'for checking route information and choosing whether a suggested '
            'trip is appropriate for you.',
      ),
      LegalDocumentSection(
        '5. Location services',
        'If you allow location access, the app can use your device location '
            'for nearby search and route planning. You can deny or turn off '
            'location permission and enter a place manually. When you use '
            'location-based search or request a route, the relevant search '
            'text or route coordinates may be sent to the providers needed '
            'to return that result. See the Data Privacy Notice for details.',
      ),
      LegalDocumentSection(
        '6. Automated and AI-assisted features',
        'The current app interprets some natural-language search requests '
            'on your device and uses place and route services to find '
            'results. Any automated interpretation or route suggestion is '
            'for general information only. It is not a guaranteed travel '
            'instruction, emergency service, or substitute for checking '
            'current conditions.',
      ),
      LegalDocumentSection(
        '7. Availability and third-party services',
        'The app and third-party services may be unavailable, change, or '
            'return incomplete information. Mapparaan cannot guarantee '
            'uninterrupted service, complete accuracy, or the safety and '
            'availability of third-party transport operators, maps, or '
            'network services.',
      ),
      LegalDocumentSection(
        '8. Photos and sharing',
        'You are responsible for the photos and information you upload. '
            'Memory photos are private unless you deliberately share them '
            'with selected friends through the app. A recipient may save or '
            'copy information they can view; removing access cannot recall '
            'copies already made.',
      ),
      LegalDocumentSection(
        '9. Changes and contact',
        'We may update these terms as the app changes. If an update affects '
            'account use, we will ask you to review and acknowledge the new '
            'version. Questions about these terms: [Mapparaan project '
            'contact to be provided before public release].',
      ),
    ],
    closing:
        'These terms are a plain-language project draft and should be '
        'reviewed by the project owner and a qualified Philippine legal '
        'professional before public release.',
  );

  static const privacy = LegalDocument(
    type: LegalDocumentType.privacyNotice,
    title: 'Data Privacy Notice',
    version: privacyVersion,
    introduction:
        'This notice explains what the current Mapparaan app processes and '
        'why. Acknowledging this notice confirms that you have read it; it '
        'is not blanket consent to unrelated or optional processing.',
    sections: [
      LegalDocumentSection(
        '1. Information the app processes',
        'Account: your name and email address, plus authentication records '
            'managed by Supabase. The app sends your password to Supabase '
            'for sign-in or account creation; it does not store the password '
            'in its own app tables.\n\n'
            'Location and searches: if you choose location-based features, '
            'the app obtains your device location after operating-system '
            'permission. Place search sends the search text to OpenStreetMap '
            'Nominatim. Nearby search sends a location and category to the '
            'OpenStreetMap Overpass service. Route requests send origin and '
            'destination coordinates, passenger category, and any selected '
            'departure time or avoided modes to the Mapparaan route planner '
            'hosted on Render.\n\n'
            'Account features: if you use them while signed in, Supabase '
            'stores saved places, trip-history summaries (place names, '
            'preference, estimated duration and fare, and route summary), '
            'commute preferences, memory-photo metadata and image files, '
            'friend relationships, and photo-sharing choices. A shared '
            'memory can reveal its image and saved place/location to the '
            'specific friends you select.\n\n'
            'On-device data: recent place searches and some app preferences '
            'are stored locally using device storage. The code reviewed does '
            'not show a separate chatbot-conversation store or an analytics '
            'SDK. Natural-language requests are parsed in the app; the '
            'destination search text may then be sent to Nominatim. Map tile '
            'requests go to OpenStreetMap or CARTO depending on configuration.',
      ),
      LegalDocumentSection(
        '2. Why and on what basis',
        'Account sign-in and requested saved features are processed to '
            'provide the account service you ask to use. Location access is '
            'optional: your device asks permission, and you can instead '
            'enter places manually. Location or route details are sent to '
            'the relevant provider only when you request a location-based '
            'search or route.\n\n'
            'Saving a place, trip, or memory is initiated by you. Sharing a '
            'photo and its associated location is a separate, deliberate '
            'choice for the selected friend(s); acknowledging this notice '
            'does not enable sharing or grant general consent for other '
            'purposes.\n\n'
            'The code review does not establish the project owner/controller '
            'or a documented lawful-basis assessment for every processing '
            'activity. Before release, the project owner must confirm the '
            'applicable basis under RA 10173 for each activity, especially '
            'any hosting/security logs, and update this notice accordingly.',
      ),
      LegalDocumentSection(
        '3. Where information is processed',
        'Supabase provides authentication, database, and private photo '
            'storage for account features. The route-planning API is hosted '
            'on Render. Place search and nearby search use OpenStreetMap '
            'Nominatim and Overpass; map tiles use OpenStreetMap or CARTO '
            'according to the app configuration. These providers receive '
            'the request data needed for their service and may process '
            'network/device metadata under their own terms and privacy '
            'practices. The project owner should confirm current provider '
            'locations, subprocessors, and retention settings.',
      ),
      LegalDocumentSection(
        '4. Retention and deletion',
        'The app provides controls to remove individual saved places, trip '
            'history entries, and memory photos. The reviewed app does not '
            'provide an in-app account-deletion flow or state a fixed '
            'retention period for all provider backups and operational logs. '
            'Account data may remain until deletion is requested and '
            'completed. To request access, correction, or deletion of your '
            'account data, contact [privacy contact to be provided before '
            'public release]. The project owner must publish a verified '
            'retention and account-deletion process before launch.',
      ),
      LegalDocumentSection(
        '5. Your rights under Philippine law',
        'Subject to the conditions and exceptions in the Data Privacy Act '
            'of 2012 (Republic Act No. 10173) and its rules, you may ask to '
            'be informed about processing, access your personal information, '
            'object to certain processing, correct inaccurate information, '
            'request erasure or blocking where legally applicable, and '
            'request data portability where applicable. You may also file a '
            'complaint with the National Privacy Commission. Use '
            '[privacy contact to be provided before public release] to make '
            'a request; the project owner must replace this placeholder '
            'with a monitored contact channel and explain identity '
            'verification and response timelines.',
      ),
      LegalDocumentSection(
        '6. Protection and limits',
        'The code uses Supabase authentication, user-scoped database access '
            'policies, and private-bucket signed photo URLs in the reviewed '
            'configuration. Requests to remote providers use HTTPS where '
            'configured. These measures reduce risk but cannot guarantee '
            'absolute security. The app does not provide end-to-end '
            'encryption: service providers process information needed to '
            'deliver their services. Do not upload sensitive information '
            'that is not needed for a memory photo.',
      ),
      LegalDocumentSection(
        '7. Questions and updates',
        'For privacy questions or requests, contact [privacy contact to be '
            'provided before public release]. We may revise this notice as '
            'the app or its providers change and may ask you to acknowledge '
            'a new version before using account features.',
      ),
    ],
    closing:
        'Project-owner action before public release: replace contact '
        'placeholders; confirm the data controller, lawful bases, provider '
        'retention and locations, and account-deletion process; then obtain '
        'a Philippine privacy/legal review. This notice is not legal advice.',
  );

  static LegalDocument forType(LegalDocumentType type) => switch (type) {
    LegalDocumentType.termsOfService => terms,
    LegalDocumentType.privacyNotice => privacy,
  };
}
